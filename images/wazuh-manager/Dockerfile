# =============================================================================
# Dockerfile - Wazuh Manager (SIEM)
# =============================================================================
FROM wazuh/wazuh-manager:4.7.3
COPY config/ossec.conf /var/ossec/etc/ossec.conf
COPY config/filebeat.yml /etc/filebeat/filebeat.yml
COPY config/custom_rules.xml /var/ossec/rules/custom_rules.xml
COPY config/custom_decoders.xml /var/ossec/etc/decoders/custom_decoders.xml
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.py 2>/dev/null || true
