# =============================================================================
# Dockerfile - Wazuh Agent (DMZ)
# =============================================================================
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg iproute2 ca-certificates && \
    curl -sL -A "Mozilla/5.0" "https://packages.wazuh.com/key/GPG-KEY-WAZUH" | apt-key add - && \
    echo "deb [trusted=yes] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && apt-get install -y --no-install-recommends wazuh-agent && \
    apt-get clean
COPY ossec.conf /var/ossec/etc/ossec.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
