#!/bin/bash
set -e
echo "[ENTRYPOINT] WebServer starting at $(date -u)"
for i in $(seq 1 30); do
    if ip link show eth0 >/dev/null 2>&1; then echo "[ENTRYPOINT] eth0 ready"; break; fi
    sleep 0.5
done
ip route replace default via 10.0.1.254 dev eth0 2>/dev/null || true

# Fix SSH privilege separation directory
mkdir -p /run/sshd

rsyslogd 2>/dev/null || true

echo "[ENTRYPOINT] Starting Apache..."
apache2ctl start
echo "[ENTRYPOINT] Apache started"

echo "[ENTRYPOINT] Starting SSH..."
/usr/sbin/sshd -D -e &
echo "[ENTRYPOINT] SSH started"

echo "[ENTRYPOINT] WebServer ready on 10.0.1.10"

# Keep container alive - wait on Apache PID
while true; do sleep 3600; done
