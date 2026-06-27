#!/bin/bash

cd /opt/pfa_v3

# Create apache from webserver
mkdir -p /opt/pfa_v3/apache
cp -r /opt/pfa_v3/webserver/* /opt/pfa_v3/apache/
echo "APACHE_DIR_CREATED"

# Pull function with retry
pull_with_retry() {
    local img="$1"
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "--- Pulling $img (attempt $attempt/$max_attempts) ---"
        if docker pull "$img"; then
            echo "--- Pulled $img successfully ---"
            return 0
        fi
        echo "--- Pull failed for $img, retrying in 10s ---"
        sleep 10
        attempt=$((attempt+1))
    done
    echo "--- FAILED to pull $img after $max_attempts attempts ---"
    return 1
}

echo "=== Pulling base images ==="
pull_with_retry kalilinux/kali-rolling
pull_with_retry ubuntu:22.04
pull_with_retry postgres:15
pull_with_retry jasonish/suricata:7.0.3
pull_with_retry wazuh/wazuh-manager:4.7.3
pull_with_retry wazuh/wazuh-indexer:4.7.3
pull_with_retry wazuh/wazuh-dashboard:4.7.3
pull_with_retry prom/prometheus:latest
pull_with_retry grafana/grafana:latest
echo "=== Base image pulls completed ==="

# Build each service
SERVICES="kali apache postgresql suricata zeek wazuh-agent wazuh-manager wazuh-indexer wazuh-dashboard prometheus grafana"
PASS=""
FAIL=""

for svc in $SERVICES; do
    echo ""
    echo "========================================="
    echo " Building pfa/$svc:latest"
    echo "========================================="
    if docker build -t "pfa/$svc:latest" "./$svc/"; then
        echo ">>> SUCCESS: pfa/$svc:latest"
        PASS="$PASS  pfa/$svc:latest"$'\n'
    else
        echo ">>> FAILED: pfa/$svc:latest"
        FAIL="$FAIL  pfa/$svc:latest"$'\n'
    fi
done

echo ""
echo "========================================="
echo " BUILD RESULTS"
echo "========================================="
echo ""
echo "SUCCESSFUL:"
echo "$PASS"
if [ -n "$FAIL" ]; then
    echo "FAILED:"
    echo "$FAIL"
fi
echo "========================================="

docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
