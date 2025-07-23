// =============================================================================
// BUSINESS INTEGRATIONS GRAPH - CONSULTAS PARA VISUALIZAÇÃO
// =============================================================================

// 1. VISUALIZAR TODAS AS INTEGRAÇÕES E RELACIONAMENTOS
MATCH (i:Integration)-[r]->(j)
RETURN i, r, j

// 2. VISUALIZAR APENAS INTEGRAÇÕES OMIE COM RELACIONAMENTOS
MATCH (i:Integration {provider: "omie"})-[r]->(j)
RETURN i, r, j

// 3. VISUALIZAR PROVEDORES E SUAS INTEGRAÇÕES
MATCH (p:Provider)<-[r:PROVIDED_BY]-(i:Integration)
RETURN p, r, i

// 4. VISUALIZAR INTEGRAÇÕES POR COMPLEXIDADE (COM CORES)
MATCH (i:Integration)
RETURN i.name AS name, 
       i.complexity AS complexity,
       i.story_points AS points,
       CASE i.complexity 
         WHEN 'simple' THEN '#4CAF50'
         WHEN 'moderate' THEN '#FF9800' 
         WHEN 'complex' THEN '#F44336'
       END AS color

// 5. DESCOBRIR CAMINHOS DE DEPENDÊNCIA
MATCH path = (start:Integration)-[:REQUIRES_CLIENT|:USES_CATEGORIES*1..3]->(end:Integration)
WHERE start.name = "consultar_contas_pagar"
RETURN path

// 6. VISUALIZAR CLUSTER POR CATEGORIA
MATCH (i:Integration)
RETURN i.name AS integration,
       i.category AS category,
       i.provider AS provider,
       i.complexity AS complexity

// 7. ANÁLISE DE IMPACTO - QUEM DEPENDE DE QUEM
MATCH (central:Integration)<-[r]-(dependent:Integration)
RETURN central.name AS integration,
       COUNT(r) AS dependencies,
       COLLECT(dependent.name) AS dependent_integrations
ORDER BY dependencies DESC

// 8. VISUALIZAÇÃO COMPLETA DO GRAFO
MATCH (n)
OPTIONAL MATCH (n)-[r]->(m)
RETURN n, r, m

// 9. MAPA DE STORY POINTS (ESFORÇO)
MATCH (i:Integration)
RETURN i.name AS integration,
       i.story_points AS points,
       i.complexity AS complexity,
       CASE 
         WHEN i.story_points <= 2 THEN 'Baixo Esforço'
         WHEN i.story_points <= 4 THEN 'Médio Esforço'
         ELSE 'Alto Esforço'
       END AS effort_level

// 10. ANÁLISE DE COBERTURA POR PROVEDOR
MATCH (i:Integration)
WITH i.provider AS provider, COUNT(i) AS total_integrations
RETURN provider, total_integrations,
       total_integrations * 100.0 / 10 AS coverage_percent
ORDER BY total_integrations DESC