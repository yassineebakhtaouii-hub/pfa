#!/bin/bash
set -e
echo "[ENTRYPOINT] Suricata starting at $(date -u)"
for i in $(seq 1 30); do
    if ip link show eth0 >/dev/null 2>&1; then echo "[ENTRYPOINT] eth0 ready"; break; fi
    sleep 0.5
done
ip route replace default via 10.0.1.254 dev eth0 2>/dev/null || true
echo "[ENTRYPOINT] Suricata config check..."
suricata -T -c /etc/suricata/suricata.yaml 2>&1 && echo "[ENTRYPOINT] Config OK"
echo "[ENTRYPOINT] Starting Suricata..."
exec suricata -c /etc/suricata/suricata.yaml -i eth0 --set vars.address-groups.HOME_NET=[10.0.1.0/24]