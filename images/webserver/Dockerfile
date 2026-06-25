# =============================================================================
# Dockerfile - Apache WebServer (Vulnerable Target)
# =============================================================================
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 iputils-ping net-tools curl apache2 php8.1 php8.1-pgsql \
    php8.1-mysqli libapache2-mod-php8.1 openssh-server sudo \
    ca-certificates rsyslog && apt-get clean
RUN useradd -m -s /bin/bash vulnuser && echo "vulnuser:vulnpass123" | chpasswd
RUN useradd -m -s /bin/bash admin && echo "admin:admin123" | chpasswd
RUN echo "root:toor" | chpasswd
COPY sshd_config /etc/ssh/sshd_config
COPY html/ /var/www/html/
RUN chown -R www-data:www-data /var/www/html && chmod 644 /var/www/html/*.php
RUN echo "<?php phpinfo(); ?>" > /var/www/html/info.php
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 80 22
ENTRYPOINT ["/entrypoint.sh"]
