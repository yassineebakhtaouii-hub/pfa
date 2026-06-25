#!/bin/bash
set -e
echo "[ENTRYPOINT] Kali PFA starting at $(date -u)"
for i in $(seq 1 30); do
    if ip link show eth0 >/dev/null 2>&1; then echo "[ENTRYPOINT] eth0 ready"; break; fi
    sleep 0.5
done
ip route replace default via 10.0.2.254 dev eth0 2>/dev/null || true
chmod +x /opt/pfa/attacks/*.sh 2>/dev/null || true
echo "[ENTRYPOINT] Kali ready. Attacks in /opt/pfa/attacks/"
exec "$@"
