# =============================================================================
# Dockerfile - Zeek Network Security Monitor
# =============================================================================
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iputils-ping net-tools curl gnupg wget ca-certificates && \
    echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/ /' > /etc/apt/sources.list.d/zeek.list && \
    wget -q -O- https://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/Release.key | apt-key add - && \
    apt-get update && apt-get install -y --no-install-recommends zeek-lts && \
    apt-get clean
COPY zeek_config/ /opt/zeek/etc/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && ln -s /opt/zeek/bin/zeek /usr/local/bin/zeek
ENTRYPOINT ["/entrypoint.sh"]
