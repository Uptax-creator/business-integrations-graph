#!/bin/bash

# Business Integrations Graph - Version Manager
# Automatiza versionamento, build e deploy do Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$PROJECT_DIR/VERSION"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações
REGISTRY="ghcr.io/uptax-creator"
IMAGE_NAME="business-integrations-graph"
DOCKERFILE="$PROJECT_DIR/Dockerfile"

# Funções de utilidade
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Função para obter versão atual
get_current_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "0.0.0"
    fi
}

# Função para incrementar versão
increment_version() {
    local version=$1
    local type=$2
    
    IFS='.' read -r major minor patch <<< "$version"
    
    case $type in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch")
            patch=$((patch + 1))
            ;;
        *)
            log_error "Tipo de versão inválido: $type"
            exit 1
            ;;
    esac
    
    echo "$major.$minor.$patch"
}

# Função para validar dependências
check_dependencies() {
    log_info "Verificando dependências..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker não encontrado. Instale o Docker primeiro."
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        log_error "Git não encontrado. Instale o Git primeiro."
        exit 1
    fi
    
    # Verificar se está em um repositório Git
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Não é um repositório Git válido."
        exit 1
    fi
    
    log_success "Todas as dependências encontradas!"
}

# Função para limpar versões antigas
cleanup_old_versions() {
    local keep_versions=${1:-10}
    
    log_info "Limpando versões antigas (mantendo $keep_versions mais recentes)..."
    
    # Listar e remover imagens antigas
    docker images "$REGISTRY/$IMAGE_NAME" --format "table {{.Tag}}\t{{.CreatedAt}}" | \
    tail -n +2 | \
    sort -k2 -r | \
    tail -n +$((keep_versions + 1)) | \
    while read -r tag created; do
        if [[ "$tag" != "latest" ]]; then
            log_warning "Removendo versão antiga: $tag"
            docker rmi "$REGISTRY/$IMAGE_NAME:$tag" 2>/dev/null || true
        fi
    done
    
    # Limpeza geral do Docker
    docker system prune -f
    log_success "Limpeza concluída!"
}

# Função para build da imagem
build_image() {
    local version=$1
    local build_args=$2
    
    log_info "Construindo imagem Docker..."
    
    # Build arguments
    local build_date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local vcs_ref=$(git rev-parse --short HEAD)
    
    # Multi-platform build
    docker buildx create --use --name multiarch || docker buildx use multiarch
    
    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --tag "$REGISTRY/$IMAGE_NAME:$version" \
        --tag "$REGISTRY/$IMAGE_NAME:latest" \
        --build-arg VERSION="$version" \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg VCS_REF="$vcs_ref" \
        $build_args \
        --push \
        "$PROJECT_DIR"
    
    log_success "Imagem construída e enviada: $REGISTRY/$IMAGE_NAME:$version"
}

# Função para criar release
create_release() {
    local version=$1
    
    log_info "Criando release Git..."
    
    # Verificar se há mudanças para commit
    if ! git diff --quiet; then
        log_warning "Existem mudanças não commitadas. Commitando automaticamente..."
        git add .
        git commit -m "chore: prepare release v$version"
    fi
    
    # Criar tag
    git tag -a "v$version" -m "Release version $version"
    
    # Push da tag
    git push origin "v$version"
    git push origin main
    
    log_success "Release v$version criada!"
}

# Função para gerar changelog
generate_changelog() {
    local version=$1
    local previous_version=$2
    
    log_info "Gerando changelog..."
    
    # Obter commits desde a última versão
    local commits=$(git log --oneline "v$previous_version..HEAD" 2>/dev/null || git log --oneline -10)
    
    cat > "$PROJECT_DIR/CHANGELOG.md" << EOF
# Changelog

## [v$version] - $(date +%Y-%m-%d)

### Added
- Business Integrations Graph v$version
- Docker multi-platform support (linux/amd64, linux/arm64)
- Automated version management
- Neo4j 5.15 Community Edition

### Changed
- Updated Docker configuration for production use
- Improved health checks and monitoring

### Commits
$commits

### Docker Images
- \`$REGISTRY/$IMAGE_NAME:$version\`
- \`$REGISTRY/$IMAGE_NAME:latest\`

### Quick Start
\`\`\`bash
docker run -d \\
  -p 7474:7474 -p 7687:7687 \\
  --name business-integrations-graph \\
  $REGISTRY/$IMAGE_NAME:$version
\`\`\`

EOF
    
    log_success "Changelog gerado!"
}

# Função para validar build
validate_build() {
    local version=$1
    
    log_info "Validando build..."
    
    # Testar se a imagem pode ser executada
    local container_id=$(docker run -d --name "test-$version" -p 17474:7474 -p 17687:7687 "$REGISTRY/$IMAGE_NAME:$version")
    
    sleep 30
    
    # Verificar se o container está healthy
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_id")
    
    if [[ "$health_status" == "healthy" ]]; then
        log_success "Build validado com sucesso!"
    else
        log_error "Build falhou na validação. Status: $health_status"
        docker logs "$container_id"
        docker rm -f "$container_id"
        exit 1
    fi
    
    # Cleanup
    docker rm -f "$container_id"
}

# Função para mostrar estatísticas
show_stats() {
    local version=$1
    
    log_info "📊 Estatísticas da Release:"
    echo "================================"
    echo "Versão: v$version"
    echo "Data: $(date)"
    echo "Git SHA: $(git rev-parse --short HEAD)"
    echo "Branch: $(git branch --show-current)"
    echo "Registry: $REGISTRY/$IMAGE_NAME:$version"
    
    # Tamanho da imagem
    local image_size=$(docker images "$REGISTRY/$IMAGE_NAME:$version" --format "{{.Size}}" | head -1)
    echo "Tamanho: $image_size"
    
    # Verificar camadas
    local layers=$(docker history "$REGISTRY/$IMAGE_NAME:$version" --quiet | wc -l)
    echo "Camadas: $layers"
    
    echo "================================"
}

# Função principal de help
show_help() {
    cat << EOF
Business Integrations Graph - Version Manager

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    build [VERSION]     - Build Docker image with specified version
    release [TYPE]      - Create new release (patch|minor|major)
    cleanup [KEEP]      - Remove old Docker images (default: keep 10)
    validate [VERSION]  - Validate Docker build
    stats [VERSION]     - Show release statistics
    current             - Show current version
    
EXAMPLES:
    $0 current                    # Show current version
    $0 build 1.2.3               # Build specific version
    $0 release patch              # Create patch release (1.0.0 -> 1.0.1)
    $0 release minor              # Create minor release (1.0.0 -> 1.1.0)
    $0 release major              # Create major release (1.0.0 -> 2.0.0)
    $0 cleanup 5                  # Keep only 5 most recent versions
    $0 validate 1.2.3             # Validate specific version

ENVIRONMENT VARIABLES:
    REGISTRY    - Docker registry (default: ghcr.io/uptax-creator)
    IMAGE_NAME  - Docker image name (default: business-integrations-graph)

EOF
}

# Main function
main() {
    case "${1:-help}" in
        "current")
            echo "Current version: $(get_current_version)"
            ;;
        "build")
            check_dependencies
            local version=${2:-$(get_current_version)}
            build_image "$version"
            validate_build "$version"
            show_stats "$version"
            ;;
        "release")
            check_dependencies
            local release_type=${2:-patch}
            local current_version=$(get_current_version)
            local new_version=$(increment_version "$current_version" "$release_type")
            
            log_info "Criando release $release_type: $current_version -> $new_version"
            
            # Atualizar VERSION file
            echo "$new_version" > "$VERSION_FILE"
            
            # Gerar changelog
            generate_changelog "$new_version" "$current_version"
            
            # Build e push
            build_image "$new_version"
            
            # Validar
            validate_build "$new_version"
            
            # Criar release Git
            create_release "$new_version"
            
            # Estatísticas
            show_stats "$new_version"
            
            log_success "Release v$new_version criada com sucesso!"
            ;;
        "cleanup")
            local keep_versions=${2:-10}
            cleanup_old_versions "$keep_versions"
            ;;
        "validate")
            local version=${2:-$(get_current_version)}
            validate_build "$version"
            ;;
        "stats")
            local version=${2:-$(get_current_version)}
            show_stats "$version"
            ;;
        "help"|*)
            show_help
            ;;
    esac
}

# Execute main function
main "$@"