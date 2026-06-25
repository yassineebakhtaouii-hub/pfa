#!/bin/bash
# =============================================================================
# recon.sh - Network Reconnaissance Suite (PFA)
# =============================================================================
# Maps to Suricata rule: sid:1000001 (SYN scan), sid:1000002 (port scan)
# =============================================================================
TARGET="${1:-10.0.1.10}"
LOG_DIR="/opt/pfa/attacks/logs"
mkdir -p "$LOG_DIR"
REPORT="$LOG_DIR/recon_$(date +%Y%m%d_%H%M%S).log"

echo "[*] PFA Reconnaissance Scan" | tee "$REPORT"
echo "[*] Target: $TARGET" | tee -a "$REPORT"
echo "[*] Time: $(date -u)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# Phase 1: Ping sweep
echo "[*] Phase 1: Ping Sweep" | tee -a "$REPORT"
for ip in 10.0.1.10 10.0.1.100 10.0.1.101 10.0.1.254; do
    ping -c 1 -W 1 "$ip" >/dev/null 2>&1 && echo "  [+] $ip alive" || echo "  [-] $ip unreachable"
done | tee -a "$REPORT"

# Phase 2: Nmap SYN scan (triggers sid:1000001)
echo "" | tee -a "$REPORT"
echo "[*] Phase 2: Nmap SYN Scan" | tee -a "$REPORT"
nmap -sS -p 22,80,443,8080,5432 --open -T4 "$TARGET" 2>&1 | tee -a "$REPORT"

# Phase 3: Service version detection
echo "" | tee -a "$REPORT"
echo "[*] Phase 3: Service Version Detection" | tee -a "$REPORT"
nmap -sV -p 22,80 "$TARGET" 2>&1 | tee -a "$REPORT"

# Phase 4: OS fingerprinting
echo "" | tee -a "$REPORT"
echo "[*] Phase 4: OS Fingerprinting" | tee -a "$REPORT"
nmap -O -p 22,80 "$TARGET" --osscan-guess 2>&1 | tee -a "$REPORT"

echo "" | tee -a "$REPORT"
echo "[*] Recon complete. Report: $REPORT" | tee -a "$REPORT"
