#!/bin/bash

# Business Integrations Graph - Backup & Version Policy Manager
# Gerencia backups automáticos e política de retenção de versões

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
CONFIG_FILE="$PROJECT_DIR/.backup-policy.json"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações padrão
DEFAULT_RETENTION_DAYS=30
DEFAULT_MAX_VERSIONS=10
DEFAULT_BACKUP_SCHEDULE="0 2 * * *"  # 2:00 AM daily
DEFAULT_S3_ENABLED=false

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Criar configuração padrão se não existir
create_default_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "Criando configuração padrão..."
        cat > "$CONFIG_FILE" << EOF
{
  "backup_policy": {
    "retention_days": $DEFAULT_RETENTION_DAYS,
    "max_versions": $DEFAULT_MAX_VERSIONS,
    "schedule": "$DEFAULT_BACKUP_SCHEDULE",
    "enabled": true,
    "compress": true,
    "encrypt": false
  },
  "version_policy": {
    "auto_cleanup": true,
    "keep_latest_major": 3,
    "keep_latest_minor": 5,
    "keep_latest_patch": 10,
    "cleanup_schedule": "0 3 * * 0"
  },
  "storage": {
    "local_enabled": true,
    "s3_enabled": $DEFAULT_S3_ENABLED,
    "s3_bucket": "",
    "s3_region": "",
    "encryption_key": ""
  },
  "notifications": {
    "enabled": false,
    "webhook_url": "",
    "email": "",
    "slack_channel": ""
  }
}
EOF
        log_success "Configuração criada: $CONFIG_FILE"
    fi
}

# Função para ler configuração
read_config() {
    local key=$1
    if [[ -f "$CONFIG_FILE" ]]; then
        python3 -c "import json; print(json.load(open('$CONFIG_FILE'))$key)" 2>/dev/null || echo ""
    fi
}

# Função para backup do Neo4j
backup_neo4j() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="business_graph_backup_$timestamp"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log_info "Iniciando backup do Neo4j..."
    
    # Criar diretório de backup
    mkdir -p "$backup_path"
    
    # Verificar se o container está rodando
    if ! docker ps | grep -q "business-integrations-graph"; then
        log_error "Container Neo4j não está rodando!"
        return 1
    fi
    
    # Backup usando neo4j-admin
    docker exec business-integrations-graph neo4j-admin database dump neo4j \
        --to-path=/var/lib/neo4j/dumps/ \
        --overwrite-destination=true
    
    # Copiar dump para o host
    docker cp business-integrations-graph:/var/lib/neo4j/dumps/neo4j.dump "$backup_path/"
    
    # Backup dos dados de configuração
    docker cp business-integrations-graph:/data "$backup_path/data"
    docker cp business-integrations-graph:/logs "$backup_path/logs"
    
    # Adicionar metadados
    cat > "$backup_path/metadata.json" << EOF
{
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "neo4j_version": "$(docker exec business-integrations-graph neo4j version 2>/dev/null || echo 'unknown')",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "docker_image": "$(docker inspect business-integrations-graph --format='{{.Config.Image}}')",
  "backup_size": "$(du -sh "$backup_path" | cut -f1)"
}
EOF
    
    # Comprimir se habilitado
    if [[ "$(read_config "['backup_policy']['compress']")" == "True" ]]; then
        log_info "Comprimindo backup..."
        tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "$backup_name"
        rm -rf "$backup_path"
        backup_path="$backup_path.tar.gz"
    fi
    
    log_success "Backup criado: $backup_path"
    
    # Upload para S3 se habilitado
    if [[ "$(read_config "['storage']['s3_enabled']")" == "True" ]]; then
        upload_to_s3 "$backup_path"
    fi
    
    # Enviar notificação
    send_notification "Backup realizado com sucesso" "$backup_path"
    
    echo "$backup_path"
}

# Função para upload S3
upload_to_s3() {
    local file_path=$1
    local s3_bucket=$(read_config "['storage']['s3_bucket']")
    local s3_region=$(read_config "['storage']['s3_region']")
    
    if [[ -z "$s3_bucket" ]]; then
        log_warning "Bucket S3 não configurado"
        return
    fi
    
    log_info "Enviando backup para S3..."
    
    # Verificar se AWS CLI está instalado
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI não encontrado"
        return 1
    fi
    
    # Upload
    local s3_key="business-integrations-graph/$(basename "$file_path")"
    aws s3 cp "$file_path" "s3://$s3_bucket/$s3_key" --region "$s3_region"
    
    log_success "Backup enviado para S3: s3://$s3_bucket/$s3_key"
}

# Função para limpeza de backups antigos
cleanup_old_backups() {
    local retention_days=$(read_config "['backup_policy']['retention_days']" || echo "$DEFAULT_RETENTION_DAYS")
    
    log_info "Limpando backups com mais de $retention_days dias..."
    
    if [[ -d "$BACKUP_DIR" ]]; then
        find "$BACKUP_DIR" -type f -name "business_graph_backup_*" -mtime +$retention_days -delete
        find "$BACKUP_DIR" -type d -name "business_graph_backup_*" -mtime +$retention_days -exec rm -rf {} +
        
        # Limpeza no S3
        if [[ "$(read_config "['storage']['s3_enabled']")" == "True" ]]; then
            cleanup_s3_backups "$retention_days"
        fi
    fi
    
    log_success "Limpeza de backups concluída"
}

# Função para limpeza S3
cleanup_s3_backups() {
    local retention_days=$1
    local s3_bucket=$(read_config "['storage']['s3_bucket']")
    
    if [[ -z "$s3_bucket" ]]; then
        return
    fi
    
    log_info "Limpando backups antigos no S3..."
    
    # Listar e deletar objetos antigos
    aws s3api list-objects-v2 \
        --bucket "$s3_bucket" \
        --prefix "business-integrations-graph/" \
        --query "Contents[?LastModified<='$(date -d "$retention_days days ago" --iso-8601)'].Key" \
        --output text | \
    while read -r key; do
        if [[ -n "$key" ]]; then
            aws s3 rm "s3://$s3_bucket/$key"
            log_info "S3: Removido $key"
        fi
    done
}

# Função para restaurar backup
restore_backup() {
    local backup_path=$1
    
    if [[ -z "$backup_path" || ! -f "$backup_path" ]]; then
        log_error "Backup não encontrado: $backup_path"
        return 1
    fi
    
    log_warning "Restaurando backup: $backup_path"
    log_warning "ATENÇÃO: Isso irá sobrescrever os dados atuais!"
    
    read -p "Continuar? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Restauração cancelada"
        return 0
    fi
    
    # Parar o container
    log_info "Parando container Neo4j..."
    docker stop business-integrations-graph || true
    
    # Extrair backup se comprimido
    local temp_dir="/tmp/neo4j_restore_$$"
    mkdir -p "$temp_dir"
    
    if [[ "$backup_path" =~ \.tar\.gz$ ]]; then
        tar -xzf "$backup_path" -C "$temp_dir"
        backup_path="$temp_dir/$(ls "$temp_dir")"
    fi
    
    # Restaurar dados
    if [[ -f "$backup_path/neo4j.dump" ]]; then
        # Criar novo container temporário para restauração
        docker run -d --name "neo4j-restore-tmp" \
            -v business-integrations-graph_business_graph_data:/data \
            neo4j:5.15-community
        
        # Copiar dump para o container
        docker cp "$backup_path/neo4j.dump" neo4j-restore-tmp:/var/lib/neo4j/
        
        # Restaurar database
        docker exec neo4j-restore-tmp neo4j-admin database load neo4j \
            --from-path=/var/lib/neo4j/ \
            --overwrite-destination=true
        
        # Remover container temporário
        docker rm -f neo4j-restore-tmp
        
        log_success "Database restaurado"
    fi
    
    # Restaurar configurações se disponíveis
    if [[ -d "$backup_path/data" ]]; then
        docker run --rm \
            -v business-integrations-graph_business_graph_data:/target \
            -v "$backup_path/data":/source \
            alpine sh -c "cp -r /source/* /target/"
        
        log_success "Configurações restauradas"
    fi
    
    # Reiniciar container
    log_info "Reiniciando container..."
    docker start business-integrations-graph
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_success "Restauração concluída!"
}

# Função para listar backups
list_backups() {
    log_info "Backups disponíveis:"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "📁 Local:"
        ls -lah "$BACKUP_DIR"/business_graph_backup_* 2>/dev/null | \
        while read -r line; do
            echo "  $line"
        done
    fi
    
    # Listar backups S3
    if [[ "$(read_config "['storage']['s3_enabled']")" == "True" ]]; then
        local s3_bucket=$(read_config "['storage']['s3_bucket']")
        if [[ -n "$s3_bucket" ]]; then
            echo "☁️  S3:"
            aws s3 ls "s3://$s3_bucket/business-integrations-graph/" 2>/dev/null | \
            while read -r line; do
                echo "  $line"
            done
        fi
    fi
}

# Função para enviar notificações
send_notification() {
    local message=$1
    local details=$2
    
    if [[ "$(read_config "['notifications']['enabled']")" != "True" ]]; then
        return
    fi
    
    local webhook_url=$(read_config "['notifications']['webhook_url']")
    local email=$(read_config "['notifications']['email']")
    
    # Webhook (Slack/Discord)
    if [[ -n "$webhook_url" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🕸️ Business Integrations Graph: $message\n📁 $details\"}" \
            "$webhook_url" 2>/dev/null || true
    fi
    
    # Email (usando sendmail se disponível)
    if [[ -n "$email" ]] && command -v sendmail &> /dev/null; then
        echo -e "Subject: Business Integrations Graph Backup\n\n$message\n\nDetails: $details" | \
        sendmail "$email" 2>/dev/null || true
    fi
}

# Função para configurar cron jobs
setup_schedule() {
    log_info "Configurando agendamentos automáticos..."
    
    local backup_schedule=$(read_config "['backup_policy']['schedule']")
    local cleanup_schedule=$(read_config "['version_policy']['cleanup_schedule']")
    
    # Adicionar jobs ao crontab
    (crontab -l 2>/dev/null; echo "$backup_schedule $SCRIPT_DIR/backup-policy.sh backup") | \
    sort -u | crontab -
    
    (crontab -l 2>/dev/null; echo "$cleanup_schedule $SCRIPT_DIR/backup-policy.sh cleanup") | \
    sort -u | crontab -
    
    log_success "Agendamentos configurados:"
    log_info "  Backup: $backup_schedule"
    log_info "  Cleanup: $cleanup_schedule"
}

# Função de help
show_help() {
    cat << EOF
Business Integrations Graph - Backup & Version Policy Manager

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    backup              - Criar backup manual do Neo4j
    restore [PATH]      - Restaurar backup especificado
    cleanup             - Limpar backups antigos
    list                - Listar backups disponíveis
    schedule            - Configurar agendamentos automáticos
    config              - Mostrar configuração atual
    init                - Inicializar configuração padrão

EXAMPLES:
    $0 backup                                    # Criar backup manual
    $0 restore /path/to/backup.tar.gz           # Restaurar backup
    $0 cleanup                                   # Limpar backups antigos
    $0 list                                      # Listar backups
    $0 schedule                                  # Configurar cron jobs

CONFIGURAÇÃO:
    Edite o arquivo .backup-policy.json para personalizar:
    - Retenção de backups (dias)
    - Máximo de versões Docker
    - Configurações S3
    - Notificações (Slack, email)

EOF
}

# Função principal
main() {
    create_default_config
    
    case "${1:-help}" in
        "backup")
            backup_neo4j
            cleanup_old_backups
            ;;
        "restore")
            local backup_path=$2
            if [[ -z "$backup_path" ]]; then
                log_error "Especifique o caminho do backup"
                exit 1
            fi
            restore_backup "$backup_path"
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "list")
            list_backups
            ;;
        "schedule")
            setup_schedule
            ;;
        "config")
            if [[ -f "$CONFIG_FILE" ]]; then
                cat "$CONFIG_FILE" | python3 -m json.tool
            else
                log_error "Arquivo de configuração não encontrado"
            fi
            ;;
        "init")
            create_default_config
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Execute main function
main "$@"