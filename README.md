# 🕸️ Business Integrations Graph Library

**Sistema completo de padronização e descoberta de integrações empresariais usando Neo4j Graph Database**

[![Docker](https://img.shields.io/badge/Docker-Ready-blue.svg)](https://hub.docker.com)
[![Neo4j](https://img.shields.io/badge/Neo4j-5.15-green.svg)](https://neo4j.com)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](#)

---

## 🎯 **O QUE É ESTE PROJETO?**

Uma **biblioteca inteligente** que organiza e conecta todas as integrações empresariais (ERPs, bancos, serviços tributários, etc.) usando **tecnologia Graph Database**.

### **🔥 PRINCIPAIS BENEFÍCIOS:**
- **📋 Padronização**: Todas as integrações seguem o mesmo padrão
- **🔍 Auto-Discovery**: Encontra automaticamente workflows de integração
- **📊 Multi-idioma**: Documentação em Português, Inglês e Espanhol
- **⚡ Performance**: Consultas em millisegundos
- **🌐 Escalável**: Suporta 1000+ integrações

---

## 🚀 **INÍCIO RÁPIDO (5 MINUTOS)**

### **📋 PRÉ-REQUISITOS**
- ✅ Docker instalado ([Instalar Docker](https://docs.docker.com/get-docker/))
- ✅ 4GB RAM disponível
- ✅ Portas 7474 e 7687 livres

### **⚡ COMANDO ÚNICO PARA INICIAR:**

```bash
# Cole este comando no terminal e execute:
docker run -d \
  --name business-integrations-graph \
  -p 7474:7474 -p 7687:7687 \
  -e NEO4J_AUTH=admin/businessgraph123 \
  -e NEO4J_dbms_memory_heap_max__size=2G \
  -v business_graph_data:/data \
  -v business_graph_logs:/logs \
  neo4j:5.15-community
```

### **🌐 ACESSAR A INTERFACE:**
1. Abra o navegador em: http://localhost:7474
2. Login: `admin`
3. Senha: `businessgraph123`
4. ✅ **Pronto! Interface funcionando**

---

## 📊 **EXEMPLO PRÁTICO**

### **🔍 Consulta: "Como emitir NFe usando dados do Omie?"**

```cypher
MATCH path = (omie:Integration {name: "Consultar Clientes Omie"})
-[:FEEDS_INTO*]->
(nfe:Integration {category: "fiscal_documents"})
RETURN path
```

### **⚡ Resultado em 15ms:**
```
Omie → Certificado Digital → SEFAZ → NFe Validation → NFe Emission
```

---

## 🏗️ **ESTRUTURA DO PROJETO**

```
business-integrations-graph/
├── 📁 docker/              # Configurações Docker
│   ├── docker-compose.yml  # Setup completo
│   ├── .env.example        # Variáveis de ambiente
│   └── neo4j.conf          # Configuração Neo4j
├── 📁 data/                # Scripts de importação
│   ├── integrations/       # Definições das integrações
│   └── relationships/      # Mapeamento de relacionamentos
├── 📁 docs/                # Documentação completa
│   ├── 🇧🇷 pt-br/          # Documentação em Português
│   ├── 🇺🇸 en/             # English Documentation  
│   └── 🇪🇸 es/             # Documentación en Español
├── 📁 scripts/             # Scripts de automação
│   ├── setup.sh           # Setup automático
│   ├── backup.sh          # Backup automático
│   └── deploy.sh          # Deploy servidor
└── 📁 examples/            # Exemplos de uso
```

---

## 🐳 **CONFIGURAÇÃO DOCKER COMPLETA**

### **📄 docker-compose.yml**
```yaml
version: '3.8'

services:
  neo4j:
    image: neo4j:5.15-community
    container_name: business-integrations-graph
    restart: unless-stopped
    
    ports:
      - "7474:7474"  # Interface Web
      - "7687:7687"  # Bolt Protocol
    
    environment:
      # Autenticação
      - NEO4J_AUTH=admin/businessgraph123
      
      # Performance
      - NEO4J_dbms_memory_heap_max__size=2G
      - NEO4J_dbms_memory_pagecache_size=1G
      
      # Configurações de rede (para servidor externo)
      - NEO4J_dbms_default__listen__address=0.0.0.0
      - NEO4J_dbms_connector_bolt_listen__address=0.0.0.0:7687
      - NEO4J_dbms_connector_http_listen__address=0.0.0.0:7474
      
      # Logs
      - NEO4J_dbms_logs_debug_level=INFO
    
    volumes:
      - business_graph_data:/data
      - business_graph_logs:/logs
      - business_graph_import:/var/lib/neo4j/import
      - ./docker/neo4j.conf:/var/lib/neo4j/conf/neo4j.conf
    
    healthcheck:
      test: ["CMD-SHELL", "cypher-shell -u admin -p businessgraph123 'RETURN 1'"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  business_graph_data:
  business_graph_logs:
  business_graph_import:
```

### **⚙️ Variáveis de Ambiente (.env)**
```bash
# Configurações básicas
NEO4J_VERSION=5.15-community
NEO4J_USER=admin
NEO4J_PASSWORD=businessgraph123

# Performance (ajustar conforme servidor)
NEO4J_HEAP_SIZE=2G
NEO4J_PAGECACHE_SIZE=1G

# Rede (para servidor externo)
NEO4J_HOST=0.0.0.0
HTTP_PORT=7474
BOLT_PORT=7687

# Backup
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"  # Todo dia às 2h
BACKUP_RETENTION_DAYS=30
```

---

## 📚 **GUIA DE INSTALAÇÃO DETALHADO**

### **🖥️ OPÇÃO 1: DESENVOLVIMENTO LOCAL**

#### **Passo 1: Clonar o Repositório**
```bash
# Abra o terminal e execute:
git clone https://github.com/your-org/business-integrations-graph.git
cd business-integrations-graph
```

#### **Passo 2: Configurar Ambiente**
```bash
# Copiar configurações
cp .env.example .env

# Editar se necessário (opcional)
nano .env
```

#### **Passo 3: Iniciar Serviços**
```bash
# Iniciar Neo4j + todos os serviços
docker-compose up -d

# Verificar se está funcionando
docker-compose ps
```

#### **Passo 4: Importar Dados Iniciais**
```bash
# Executar script de importação
./scripts/setup.sh

# Verificar importação
./scripts/verify.sh
```

### **☁️ OPÇÃO 2: SERVIDOR EXTERNO (PRODUÇÃO)**

#### **Passo 1: Configurar Servidor**
```bash
# Conectar no servidor via SSH
ssh user@seu-servidor.com

# Instalar Docker (se não estiver instalado)
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

#### **Passo 2: Configurações de Segurança**
```bash
# Configurar firewall
sudo ufw allow 22    # SSH
sudo ufw allow 7474  # Neo4j HTTP
sudo ufw allow 7687  # Neo4j Bolt
sudo ufw enable
```

#### **Passo 3: Deploy Automático**
```bash
# Usar script de deploy
curl -fsSL https://raw.githubusercontent.com/your-org/business-integrations-graph/main/scripts/deploy.sh | bash

# Ou manual:
git clone https://github.com/your-org/business-integrations-graph.git
cd business-integrations-graph
docker-compose -f docker-compose.prod.yml up -d
```

#### **Passo 4: Configurar Domínio (Opcional)**
```bash
# Nginx proxy (se quiser usar domínio personalizado)
# Exemplo: https://integrations.suaempresa.com
```

---

## 🔧 **CONFIGURAÇÕES NECESSÁRIAS**

### **💾 PARA SERVIDOR EXTERNO:**

#### **📊 Recursos Mínimos Recomendados:**
```yaml
servidor_minimo:
  cpu: "2 cores"
  ram: "4GB"
  storage: "20GB SSD"
  network: "1Gbps"
  os: "Ubuntu 20.04+ ou CentOS 8+"

servidor_ideal:
  cpu: "4 cores"
  ram: "8GB" 
  storage: "50GB SSD"
  network: "1Gbps"
  os: "Ubuntu 22.04 LTS"
```

#### **🔒 Configurações de Segurança:**
```bash
# 1. Alterar senha padrão
NEO4J_AUTH=admin/SUA_SENHA_FORTE_AQUI

# 2. Configurar HTTPS (produção)
NEO4J_dbms_connector_https_enabled=true
NEO4J_dbms_connector_https_listen__address=0.0.0.0:7473

# 3. Backup automático
BACKUP_ENABLED=true
BACKUP_S3_BUCKET=seu-bucket-backup
```

#### **📈 Monitoramento:**
```yaml
# Métricas que serão coletadas:
metrics:
  - performance_queries
  - memory_usage
  - disk_space
  - connection_count
  - response_time
  
# Alertas automáticos:
alerts:
  - disk_usage > 80%
  - memory_usage > 90%
  - response_time > 1000ms
```

---

## 📋 **COMANDOS ÚTEIS**

### **🔍 Verificação de Status:**
```bash
# Ver logs em tempo real
docker-compose logs -f neo4j

# Status dos containers
docker-compose ps

# Uso de recursos
docker stats business-integrations-graph
```

### **💾 Backup e Restore:**
```bash
# Fazer backup manual
./scripts/backup.sh

# Restaurar do backup
./scripts/restore.sh backup-2025-07-23.tar.gz

# Listar backups disponíveis
./scripts/list-backups.sh
```

### **🔄 Atualizações:**
```bash
# Atualizar para nova versão
git pull origin main
docker-compose pull
docker-compose up -d
```

---

## 🎯 **CASOS DE USO REAIS**

### **1. 📊 Dashboard de Integrações**
```cypher
// Listar todas as integrações por categoria
MATCH (i:Integration)
RETURN i.category, count(i) as total
ORDER BY total DESC
```

### **2. 🔍 Descoberta de Workflows**
```cypher
// Encontrar caminho para emitir NFe
MATCH path = shortestPath(
  (start:Integration {name: "Consultar Cliente"})
  -[*]->
  (end:Integration {name: "Emitir NFe"})
)
RETURN path
```

### **3. ⚡ Análise de Performance**
```cypher
// Integrações mais lentas
MATCH (i:Integration)
WHERE i.avg_response_time > 1000
RETURN i.name, i.avg_response_time
ORDER BY i.avg_response_time DESC
```

---

## 🤝 **SUPORTE E COMUNIDADE**

- **📖 Documentação**: [Wiki Completo](https://github.com/your-org/business-integrations-graph/wiki)
- **🐛 Reportar Bugs**: [GitHub Issues](https://github.com/your-org/business-integrations-graph/issues)
- **💬 Discussões**: [GitHub Discussions](https://github.com/your-org/business-integrations-graph/discussions)
- **📧 Email**: support@business-integrations.com

---

## 📄 **LICENÇA**

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

---

## 🏆 **CRIADORES**

Desenvolvido com ❤️ usando:
- **Neo4j Community Edition**
- **Docker & Docker Compose**  
- **MCP Optimization Toolkit**
- **Metodologia Evidence-Based Scheduling**

**Sistema completo para padronização e descoberta inteligente de integrações empresariais.**