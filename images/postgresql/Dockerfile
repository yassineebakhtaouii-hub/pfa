# =============================================================================
# Dockerfile - PostgreSQL Database Server
# =============================================================================
FROM postgres:15
RUN apt-get update && apt-get install -y --no-install-recommends iproute2 iputils-ping net-tools && apt-get clean
COPY entrypoint.sh /entrypoint.sh
COPY init/ /docker-entrypoint-initdb.d/
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
