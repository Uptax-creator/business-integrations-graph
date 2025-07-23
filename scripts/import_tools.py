#!/usr/bin/env python3
"""
Script para importar ferramentas existentes para o Business Integrations Graph
"""

import json
import sys
from neo4j import GraphDatabase
from datetime import datetime

# Configurações de conexão
NEO4J_URI = "bolt://localhost:7687"
NEO4J_USER = "neo4j"
NEO4J_PASSWORD = "109RHSL6r81F"

def create_driver():
    """Criar conexão com Neo4j"""
    try:
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        return driver
    except Exception as e:
        print(f"❌ Erro ao conectar com Neo4j: {e}")
        return None

def import_omie_tools(session):
    """Importar ferramentas do Omie"""
    omie_tools = [
        {
            "name": "consultar_categorias",
            "description": "Consultar categorias de receitas e despesas",
            "provider": "omie",
            "category": "financial_services",
            "version": "1.0",
            "status": "active",
            "endpoints": ["general.categorias"],
            "complexity": "simple",
            "story_points": 2
        },
        {
            "name": "listar_clientes",
            "description": "Listar clientes cadastrados",
            "provider": "omie", 
            "category": "management_systems",
            "version": "1.0",
            "status": "active",
            "endpoints": ["geral.clientes"],
            "complexity": "simple",
            "story_points": 2
        },
        {
            "name": "consultar_contas_pagar",
            "description": "Consultar contas a pagar com filtros",
            "provider": "omie",
            "category": "financial_services", 
            "version": "1.0",
            "status": "active",
            "endpoints": ["financas.contapagar"],
            "complexity": "moderate",
            "story_points": 3
        },
        {
            "name": "incluir_projeto",
            "description": "Incluir novo projeto no sistema",
            "provider": "omie",
            "category": "management_systems",
            "version": "1.0", 
            "status": "active",
            "endpoints": ["geral.projetos"],
            "complexity": "moderate",
            "story_points": 3
        },
        {
            "name": "listar_projetos",
            "description": "Listar projetos cadastrados",
            "provider": "omie",
            "category": "management_systems",
            "version": "1.0",
            "status": "active", 
            "endpoints": ["geral.projetos"],
            "complexity": "simple",
            "story_points": 2
        }
    ]
    
    for tool in omie_tools:
        query = """
        MERGE (i:Integration {name: $name, provider: $provider})
        SET i.description = $description,
            i.category = $category,
            i.version = $version,
            i.status = $status,
            i.endpoints = $endpoints,
            i.complexity = $complexity,
            i.story_points = $story_points,
            i.created_at = datetime(),
            i.updated_at = datetime()
        RETURN i
        """
        result = session.run(query, **tool)
        print(f"✅ Importado: {tool['name']} (Omie)")

def import_nibo_tools(session):
    """Importar ferramentas do Nibo"""
    nibo_tools = [
        {
            "name": "incluir_cliente_nibo",
            "description": "Incluir cliente no sistema Nibo",
            "provider": "nibo",
            "category": "management_systems",
            "version": "1.0",
            "status": "active",
            "endpoints": ["clients"],
            "complexity": "moderate",
            "story_points": 3
        },
        {
            "name": "listar_agendamentos_nibo",
            "description": "Listar agendamentos do Nibo",
            "provider": "nibo",
            "category": "management_systems", 
            "version": "1.0",
            "status": "active",
            "endpoints": ["schedules"],
            "complexity": "simple",
            "story_points": 2
        },
        {
            "name": "consultar_dados_empresa_nibo",
            "description": "Consultar dados da empresa no Nibo",
            "provider": "nibo",
            "category": "management_systems",
            "version": "1.0",
            "status": "active",
            "endpoints": ["company"],
            "complexity": "simple", 
            "story_points": 2
        },
        {
            "name": "incluir_socio_nibo",
            "description": "Incluir sócio no sistema Nibo",
            "provider": "nibo",
            "category": "management_systems",
            "version": "1.0",
            "status": "active",
            "endpoints": ["partners"],
            "complexity": "moderate",
            "story_points": 3
        },
        {
            "name": "consultar_financeiro_nibo",
            "description": "Consultar informações financeiras no Nibo",
            "provider": "nibo",
            "category": "financial_services",
            "version": "1.0",
            "status": "active",
            "endpoints": ["financial"],
            "complexity": "complex",
            "story_points": 5
        }
    ]
    
    for tool in nibo_tools:
        query = """
        MERGE (i:Integration {name: $name, provider: $provider})
        SET i.description = $description,
            i.category = $category,
            i.version = $version,
            i.status = $status,
            i.endpoints = $endpoints,
            i.complexity = $complexity,
            i.story_points = $story_points,
            i.created_at = datetime(),
            i.updated_at = datetime()
        RETURN i
        """
        result = session.run(query, **tool)
        print(f"✅ Importado: {tool['name']} (Nibo)")

def create_relationships(session):
    """Criar relacionamentos entre as integrações"""
    relationships = [
        # Omie - relacionamentos financeiros
        ("consultar_contas_pagar", "consultar_categorias", "USES_CATEGORIES"),
        ("consultar_contas_pagar", "listar_clientes", "FILTERS_BY_CLIENT"),
        
        # Projetos dependem de clientes
        ("incluir_projeto", "listar_clientes", "REQUIRES_CLIENT"),
        
        # Nibo - relacionamentos
        ("consultar_financeiro_nibo", "incluir_cliente_nibo", "REQUIRES_CLIENT"),
        ("incluir_socio_nibo", "consultar_dados_empresa_nibo", "BELONGS_TO_COMPANY"),
    ]
    
    for source, target, relationship in relationships:
        query = """
        MATCH (source:Integration {name: $source})
        MATCH (target:Integration {name: $target})
        MERGE (source)-[r:%s]->(target)
        SET r.created_at = datetime()
        RETURN source.name, target.name, type(r)
        """ % relationship
        
        result = session.run(query, source=source, target=target)
        print(f"🔗 Relacionamento: {source} -> {target} ({relationship})")

def create_provider_nodes(session):
    """Criar nós dos provedores"""
    providers = [
        {
            "name": "omie",
            "full_name": "Omie ERP",
            "type": "erp_system",
            "website": "https://www.omie.com.br",
            "api_version": "v1",
            "status": "active"
        },
        {
            "name": "nibo",
            "full_name": "Nibo Plus",
            "type": "accounting_system", 
            "website": "https://www.nibo.com.br",
            "api_version": "v1",
            "status": "active"
        }
    ]
    
    for provider in providers:
        query = """
        MERGE (p:Provider {name: $name})
        SET p.full_name = $full_name,
            p.type = $type,
            p.website = $website,
            p.api_version = $api_version,
            p.status = $status,
            p.created_at = datetime()
        RETURN p
        """
        result = session.run(query, **provider)
        print(f"🏢 Provedor criado: {provider['full_name']}")
    
    # Conectar integrações aos provedores
    query = """
    MATCH (i:Integration), (p:Provider)
    WHERE i.provider = p.name
    MERGE (i)-[r:PROVIDED_BY]->(p)
    SET r.created_at = datetime()
    RETURN count(r) as relationships_created
    """
    result = session.run(query)
    count = result.single()["relationships_created"]
    print(f"🔗 {count} relacionamentos Integration->Provider criados")

def validate_import(session):
    """Validar a importação"""
    queries = [
        ("Total de integrações", "MATCH (i:Integration) RETURN count(i) as total"),
        ("Total de provedores", "MATCH (p:Provider) RETURN count(p) as total"),
        ("Total de relacionamentos", "MATCH ()-[r]->() RETURN count(r) as total"),
        ("Integrações por provedor", """
            MATCH (i:Integration) 
            RETURN i.provider as provider, count(i) as count 
            ORDER BY count DESC
        """),
        ("Complexidades", """
            MATCH (i:Integration) 
            RETURN i.complexity as complexity, count(i) as count 
            ORDER BY count DESC
        """)
    ]
    
    print("\n📊 VALIDAÇÃO DA IMPORTAÇÃO:")
    print("=" * 50)
    
    for description, query in queries:
        result = session.run(query)
        print(f"\n{description}:")
        for record in result:
            if len(record.keys()) == 1:
                print(f"  {record[record.keys()[0]]}")
            else:
                print(f"  {dict(record)}")

def main():
    """Função principal"""
    print("🕸️ BUSINESS INTEGRATIONS GRAPH - IMPORTAÇÃO DE DADOS")
    print("=" * 60)
    
    driver = create_driver()
    if not driver:
        sys.exit(1)
    
    try:
        with driver.session() as session:
            print("\n1️⃣ Criando provedores...")
            create_provider_nodes(session)
            
            print("\n2️⃣ Importando ferramentas Omie...")
            import_omie_tools(session)
            
            print("\n3️⃣ Importando ferramentas Nibo...")
            import_nibo_tools(session)
            
            print("\n4️⃣ Criando relacionamentos...")
            create_relationships(session)
            
            print("\n5️⃣ Validando importação...")
            validate_import(session)
            
            print("\n✅ IMPORTAÇÃO CONCLUÍDA COM SUCESSO!")
            print("\n🌐 Acesse: http://localhost:7474")
            print(f"👤 Usuário: {NEO4J_USER}")
            print(f"🔑 Senha: {NEO4J_PASSWORD}")
            
    except Exception as e:
        print(f"❌ Erro durante importação: {e}")
        sys.exit(1)
    finally:
        driver.close()

if __name__ == "__main__":
    main()