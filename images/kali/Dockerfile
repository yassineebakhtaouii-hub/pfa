# =============================================================================
# Dockerfile - Kali Linux Attack Machine
# =============================================================================
FROM kalilinux/kali-rolling
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iputils-ping net-tools curl wget nmap hydra nikto \
    hping3 metasploit-framework arp-scan dsniff netcat-openbsd \
    openssh-client whois dnsutils procps ca-certificates \
    && apt-get clean
COPY scripts/ /opt/pfa/attacks/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/pfa/attacks/*.sh 2>/dev/null || true
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
