#!/bin/bash

# =============================================================================
# BUSINESS INTEGRATIONS GRAPH - SCRIPT DE SETUP AUTOMÁTICO
# =============================================================================
# Este script configura tudo automaticamente para não-desenvolvedores
# Uso: ./scripts/setup.sh

set -e  # Parar se houver erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logs coloridos
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

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        🕸️  BUSINESS INTEGRATIONS GRAPH SETUP              ║
║                                                              ║
║        Setup automático para Neo4j Graph Database           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar se está no diretório correto
if [ ! -f "docker-compose.yml" ]; then
    log_error "Erro: Execute este script na raiz do projeto!"
    log_info "Use: cd business-integrations-graph && ./scripts/setup.sh"
    exit 1
fi

log_info "Iniciando setup do Business Integrations Graph..."

# Passo 1: Verificar Docker
log_info "🐳 Verificando instalação do Docker..."
if ! command -v docker &> /dev/null; then
    log_error "Docker não está instalado!"
    log_info "Instale o Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose não está instalado!"
    log_info "Instale o Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
fi

log_success "Docker e Docker Compose encontrados!"

# Passo 2: Verificar recursos do sistema
log_info "📊 Verificando recursos do sistema..."

# Verificar memória RAM disponível
AVAILABLE_RAM=$(free -m | awk 'NR==2{printf "%d", $7}')
if [ "$AVAILABLE_RAM" -lt 3072 ]; then  # 3GB mínimo
    log_warning "RAM disponível: ${AVAILABLE_RAM}MB (recomendado: 4GB+)"
    log_warning "O sistema pode ficar lento. Continue? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        log_info "Setup cancelado."
        exit 0
    fi
else
    log_success "RAM disponível: ${AVAILABLE_RAM}MB ✓"
fi

# Verificar espaço em disco
AVAILABLE_DISK=$(df -m . | awk 'NR==2{printf "%d", $4}')
if [ "$AVAILABLE_DISK" -lt 5120 ]; then  # 5GB mínimo
    log_warning "Espaço em disco: ${AVAILABLE_DISK}MB (recomendado: 10GB+)"
else
    log_success "Espaço em disco: ${AVAILABLE_DISK}MB ✓"
fi

# Passo 3: Configurar arquivo de ambiente
log_info "⚙️  Configurando variáveis de ambiente..."

if [ ! -f ".env" ]; then
    cp .env.example .env
    log_success "Arquivo .env criado com configurações padrão"
    
    # Gerar senha aleatória mais segura
    NEW_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
    sed -i.bak "s/NEO4J_PASSWORD=businessgraph123/NEO4J_PASSWORD=${NEW_PASSWORD}/" .env
    log_info "🔒 Senha gerada automaticamente: ${NEW_PASSWORD}"
    log_warning "⚠️  ANOTE ESTA SENHA! Você precisará dela para acessar o sistema."
    
    # Ajustar memória baseado no sistema
    if [ "$AVAILABLE_RAM" -gt 8192 ]; then  # 8GB+
        sed -i.bak "s/NEO4J_HEAP_SIZE=2G/NEO4J_HEAP_SIZE=4G/" .env
        sed -i.bak "s/NEO4J_PAGECACHE_SIZE=1G/NEO4J_PAGECACHE_SIZE=2G/" .env
        log_info "📈 Configurações de performance otimizadas para 8GB+ RAM"
    elif [ "$AVAILABLE_RAM" -lt 4096 ]; then  # <4GB
        sed -i.bak "s/NEO4J_HEAP_SIZE=2G/NEO4J_HEAP_SIZE=1G/" .env
        sed -i.bak "s/NEO4J_PAGECACHE_SIZE=1G/NEO4J_PAGECACHE_SIZE=512M/" .env
        log_warning "📉 Configurações ajustadas para sistema com pouca RAM"
    fi
else
    log_info "Arquivo .env já existe, mantendo configurações atuais"
fi

# Passo 4: Criar diretórios necessários
log_info "📁 Criando estrutura de diretórios..."

mkdir -p data/import
mkdir -p data/integrations
mkdir -p data/relationships
mkdir -p backups
mkdir -p logs
mkdir -p monitoring

log_success "Diretórios criados com sucesso!"

# Passo 5: Verificar portas
log_info "🔌 Verificando disponibilidade das portas..."

check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null; then
        return 1  # Porta ocupada
    else
        return 0  # Porta livre
    fi
}

if ! check_port 7474; then
    log_error "Porta 7474 já está em uso!"
    log_info "Pare o serviço que está usando esta porta ou altere no .env"
    exit 1
fi

if ! check_port 7687; then
    log_error "Porta 7687 já está em uso!"
    log_info "Pare o serviço que está usando esta porta ou altere no .env"
    exit 1
fi

log_success "Portas 7474 e 7687 disponíveis!"

# Passo 6: Download das imagens Docker
log_info "📥 Baixando imagens Docker (pode demorar alguns minutos)..."

docker-compose pull neo4j
log_success "Imagem Neo4j baixada com sucesso!"

# Passo 7: Iniciar os serviços
log_info "🚀 Iniciando o Neo4j..."

docker-compose up -d neo4j

# Aguardar Neo4j ficar pronto
log_info "⏳ Aguardando Neo4j inicializar (pode demorar até 2 minutos)..."

TIMEOUT=120  # 2 minutos
COUNTER=0

while [ $COUNTER -lt $TIMEOUT ]; do
    if docker-compose exec -T neo4j cypher-shell -u admin -p "$(grep NEO4J_PASSWORD .env | cut -d'=' -f2)" "RETURN 1" &>/dev/null; then
        break
    fi
    sleep 5
    COUNTER=$((COUNTER + 5))
    echo -n "."
done

echo ""

if [ $COUNTER -ge $TIMEOUT ]; then
    log_error "Timeout: Neo4j não iniciou corretamente"
    log_info "Verifique os logs: docker-compose logs neo4j"
    exit 1
fi

log_success "Neo4j está funcionando!"

# Passo 8: Importar dados iniciais
log_info "📊 Importando dados iniciais..."

# Criar script de importação básica
cat > data/import/initial_data.cypher << EOF
// Criar constraints
CREATE CONSTRAINT integration_id FOR (i:Integration) REQUIRE i.id IS UNIQUE;
CREATE CONSTRAINT provider_id FOR (p:Provider) REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT category_id FOR (c:Category) REQUIRE c.id IS UNIQUE;

// Criar índices para performance
CREATE INDEX integration_category FOR (i:Integration) ON (i.category);
CREATE INDEX integration_complexity FOR (i:Integration) ON (i.complexity);
CREATE INDEX provider_name FOR (p:Provider) ON (p.name);

// Dados iniciais - Categorias
CREATE (c1:Category {id: 'management_systems', name: 'Sistemas de Gestão', description: 'ERPs, CRMs, HR systems'});
CREATE (c2:Category {id: 'financial_services', name: 'Serviços Financeiros', description: 'Bancos, PIX, pagamentos'});
CREATE (c3:Category {id: 'tax_services', name: 'Serviços Tributários', description: 'Receita Federal, SEFAZ'});
CREATE (c4:Category {id: 'fiscal_documents', name: 'Documentos Fiscais', description: 'NFe, NFSe, CTe'});
CREATE (c5:Category {id: 'government_services', name: 'Serviços Governamentais', description: 'INSS, FGTS, BACEN'});
CREATE (c6:Category {id: 'data_services', name: 'Serviços de Dados', description: 'Serasa, SPC, B3'});

// Dados iniciais - Providers
CREATE (p1:Provider {id: 'omie', name: 'Omie ERP', category: 'management_systems', reliability: 9.2});
CREATE (p2:Provider {id: 'nibo', name: 'Nibo', category: 'management_systems', reliability: 8.5});

// Dados iniciais - Integrações básicas do Omie
CREATE (i1:Integration {
    id: 'omie_consultar_clientes',
    name: 'Consultar Clientes Omie',
    category: 'management_systems',
    provider: 'omie',
    complexity: 'simple',
    endpoint: '/geral/clientes/',
    method: 'GET',
    auth_type: 'app_key_secret',
    created_at: datetime()
});

CREATE (i2:Integration {
    id: 'omie_listar_categorias',
    name: 'Listar Categorias Omie',
    category: 'management_systems', 
    provider: 'omie',
    complexity: 'simple',
    endpoint: '/geral/categorias/',
    method: 'GET',
    auth_type: 'app_key_secret',
    created_at: datetime()
});

// Relacionamentos
MATCH (i:Integration {provider: 'omie'}), (p:Provider {id: 'omie'})
CREATE (i)-[:PROVIDED_BY]->(p);

MATCH (i:Integration), (c:Category)
WHERE i.category = c.id
CREATE (i)-[:BELONGS_TO]->(c);

// Mensagem de sucesso
RETURN 'Dados iniciais importados com sucesso!' as status;
EOF

# Executar importação
docker-compose exec -T neo4j cypher-shell -u admin -p "$(grep NEO4J_PASSWORD .env | cut -d'=' -f2)" -f /import/initial_data.cypher

log_success "Dados iniciais importados!"

# Passo 9: Verificar instalação
log_info "🔍 Verificando instalação..."

# Testar consulta básica
RESULT=$(docker-compose exec -T neo4j cypher-shell -u admin -p "$(grep NEO4J_PASSWORD .env | cut -d'=' -f2)" "MATCH (n) RETURN count(n) as total" --format plain)

if [[ $RESULT =~ [0-9]+ ]]; then
    log_success "✅ Sistema funcionando corretamente!"
else
    log_error "❌ Erro na verificação do sistema"
    exit 1
fi

# Passo 10: Informações finais
echo ""
echo -e "${GREEN}🎉 SETUP CONCLUÍDO COM SUCESSO! 🎉${NC}"
echo ""
echo -e "${BLUE}📋 INFORMAÇÕES DE ACESSO:${NC}"
echo -e "   🌐 Interface Web: ${YELLOW}http://localhost:7474${NC}"
echo -e "   👤 Usuário: ${YELLOW}admin${NC}"
echo -e "   🔒 Senha: ${YELLOW}$(grep NEO4J_PASSWORD .env | cut -d'=' -f2)${NC}"
echo ""
echo -e "${BLUE}🔧 COMANDOS ÚTEIS:${NC}"
echo -e "   📊 Ver status: ${YELLOW}docker-compose ps${NC}"
echo -e "   📝 Ver logs: ${YELLOW}docker-compose logs -f neo4j${NC}"
echo -e "   ⏹️  Parar: ${YELLOW}docker-compose down${NC}"
echo -e "   🔄 Reiniciar: ${YELLOW}docker-compose restart neo4j${NC}"
echo ""
echo -e "${BLUE}📚 PRÓXIMOS PASSOS:${NC}"
echo -e "   1. Acesse a interface web no navegador"
echo -e "   2. Faça login com as credenciais acima"
echo -e "   3. Execute consultas de exemplo na documentação"
echo -e "   4. Importe suas próprias integrações"
echo ""
echo -e "${GREEN}✨ Seu Business Integrations Graph está pronto para uso! ✨${NC}"

# Salvar informações de acesso
cat > access_info.txt << EOF
=============================================================================
BUSINESS INTEGRATIONS GRAPH - INFORMAÇÕES DE ACESSO
=============================================================================

Data da instalação: $(date)
Versão: Neo4j 5.15 Community

ACESSO WEB:
- URL: http://localhost:7474
- Usuário: admin  
- Senha: $(grep NEO4J_PASSWORD .env | cut -d'=' -f2)

COMANDOS DOCKER:
- Status: docker-compose ps
- Logs: docker-compose logs -f neo4j
- Parar: docker-compose down
- Iniciar: docker-compose up -d

BACKUP:
- Backup manual: ./scripts/backup.sh
- Localização: ./backups/

CONFIGURAÇÕES:
- Arquivo: .env
- Memória heap: $(grep NEO4J_HEAP_SIZE .env | cut -d'=' -f2)
- Cache: $(grep NEO4J_PAGECACHE_SIZE .env | cut -d'=' -f2)

=============================================================================
EOF

log_info "📄 Informações salvas em: access_info.txt"

exit 0