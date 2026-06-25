#!/bin/bash
set -e
echo "[ENTRYPOINT] Zeek starting at $(date -u)"
for i in $(seq 1 30); do
    if ip link show eth0 >/dev/null 2>&1; then echo "[ENTRYPOINT] eth0 ready"; break; fi
    sleep 0.5
done
ip route replace default via 10.0.1.254 dev eth0 2>/dev/null || true

# Find zeek binary
ZEEK_BIN=$(which zeek 2>/dev/null || find /opt/zeek -name zeek -type f 2>/dev/null | head -1)
echo "[ENTRYPOINT] Zeek binary: $ZEEK_BIN"

# Find config path
ZEEK_CFG=$(find /opt/zeek -name "config.zeek" -o -name "zeekctl.cfg" 2>/dev/null | head -1)
echo "[ENTRYPOINT] Config: $ZEEK_CFG"

if [ -n "$ZEEK_BIN" ]; then
    echo "[ENTRYPOINT] Starting Zeek on eth0..."
    mkdir -p /var/log/zeek
    cd /var/log/zeek
    exec $ZEEK_BIN -i eth0 local
else
    echo "[ENTRYPOINT] Zeek binary not found!"
    exit 1
fi
