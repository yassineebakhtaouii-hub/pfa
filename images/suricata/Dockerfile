# =============================================================================
# Dockerfile - Suricata IDS/IPS
# =============================================================================
FROM jasonish/suricata:7.0.3
# Base image is AlmaLinux 9 (RHEL-based) - use yum
RUN yum install -y iproute iputils diffutils && yum clean all && rm -rf /var/cache/yum
COPY suricata.yaml /etc/suricata/suricata.yaml
COPY rules/ /etc/suricata/rules/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
