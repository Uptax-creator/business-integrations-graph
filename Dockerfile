# Business Integrations Graph - Multi-stage Docker Build
FROM neo4j:5.15-community as base

# Metadata
LABEL org.opencontainers.image.title="Business Integrations Graph"
LABEL org.opencontainers.image.description="Neo4j-based graph database for business integrations discovery and management"
LABEL org.opencontainers.image.vendor="Uptax Creator"
LABEL org.opencontainers.image.url="https://github.com/Uptax-creator/business-integrations-graph"
LABEL org.opencontainers.image.source="https://github.com/Uptax-creator/business-integrations-graph"
LABEL org.opencontainers.image.licenses="MIT"

# Build arguments
ARG VERSION=latest
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.version=$VERSION
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.revision=$VCS_REF

# Environment variables for production
ENV NEO4J_AUTH=neo4j/businessgraph2025
ENV NEO4J_dbms_memory_heap_max__size=2G
ENV NEO4J_dbms_memory_pagecache_size=1G
ENV NEO4J_dbms_default__listen__address=0.0.0.0
ENV NEO4J_dbms_connector_bolt_listen__address=0.0.0.0:7687
ENV NEO4J_dbms_connector_http_listen__address=0.0.0.0:7474
ENV NEO4J_dbms_logs_debug_level=INFO
ENV NEO4J_dbms_security_procedures_unrestricted=apoc.*
ENV NEO4J_dbms_security_procedures_allowlist=apoc.*
ENV NEO4J_PLUGINS=["apoc"]

# Copy custom configurations
COPY --chown=neo4j:neo4j ./data/import/ /var/lib/neo4j/import/
COPY --chown=neo4j:neo4j ./scripts/ /var/lib/neo4j/scripts/

# Make scripts executable
USER root
RUN chmod +x /var/lib/neo4j/scripts/*.py /var/lib/neo4j/scripts/*.sh || true
USER neo4j

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD cypher-shell -u neo4j -p businessgraph2025 "RETURN 1" || exit 1

# Expose ports
EXPOSE 7474 7687

# Volume for persistent data
VOLUME ["/data", "/logs", "/var/lib/neo4j/import"]

# Startup command with custom initialization
ENTRYPOINT ["/sbin/tini", "-g", "--", "/docker-entrypoint.sh"]
CMD ["neo4j"]

# Production stage - optimized for size
FROM base as production

# Remove development files
RUN rm -rf /var/lib/neo4j/import/examples/ \
    && rm -rf /tmp/* \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set production environment
ENV NEO4J_ENV=production
ENV NEO4J_dbms_logs_debug_level=WARN

# Development stage - with additional tools
FROM base as development

USER root

# Install Python and development tools
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    wget \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for import scripts
RUN pip3 install neo4j==5.28.1 pyyaml requests

USER neo4j

# Set development environment
ENV NEO4J_ENV=development
ENV NEO4J_dbms_logs_debug_level=DEBUG

# Default to production stage
FROM production