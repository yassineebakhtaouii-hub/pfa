#!/bin/bash
###############################################################################
# PFA ENTERPRISE V3 – FULL AUTOMATED INSTALL (GNS3 VM)
# Run as root on the GNS3 VM (Ubuntu)
###############################################################################
set -euo pipefail

# ── Config (change only if needed) ────────────────────────────────────────
PROJECT_NAME="PFA_Enterprise_V3"
GNS3_HOST="192.168.56.101"
GNS3_PORT=""
IOS_PATH="/opt/gns3/images/IOS/c3725-adventerprisek9-mz.124-15.T14.bin"
DOCKER_BUILD_CONTEXT="/opt/pfa_build"
LOG_FILE="/var/log/pfa_install.log"
VERIFY_SCRIPT="/usr/local/bin/pfa_verify.sh"

# IP Plan (match master spec)
LAN_SUBNET="10.0.2.0/24"          ; LAN_GW="10.0.2.254"
DMZ_SUBNET="10.0.1.0/24"          ; DMZ_GW="10.0.1.254"
MON_SUBNET="10.0.3.0/24"          ; MON_GW="10.0.3.254"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

exec > >(tee -a "$LOG_FILE") 2>&1
echo "$(date) - Starting PFA installation..."

log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# ── GNS3 API helper ────────────────────────────────────────────────────────
gns3_api() {
    curl -s -X "$1" "http://${GNS3_HOST}:${GNS3_PORT}/v2$2" \
         -H "Content-Type: application/json" -d "${3:-}"
}

# ── Pre‑requisites ─────────────────────────────────────────────────────────
log "Checking prerequisites..."
command -v docker  >/dev/null || fail "Docker not installed"
command -v curl    >/dev/null || fail "curl not installed"
command -v jq      >/dev/null || fail "jq not installed (run: sudo apt install jq)"
command -v expect  >/dev/null || fail "expect not installed (run: sudo apt install expect)"

docker info &>/dev/null            || fail "Docker daemon not running"
gns3_api GET /version | jq -e '.version' &>/dev/null || \
    fail "GNS3 server not reachable at ${GNS3_HOST}:${GNS3_PORT}"
[ -f "$IOS_PATH" ]                || fail "IOS image missing at $IOS_PATH"

# ── Build all Docker images ────────────────────────────────────────────────
log "Building Docker images..."
cd "$DOCKER_BUILD_CONTEXT" || fail "Build context $DOCKER_BUILD_CONTEXT missing"

SERVICES=( kali apache postgresql suricata zeek wazuh-agent
           wazuh-manager wazuh-indexer wazuh-dashboard prometheus grafana )

for svc in "${SERVICES[@]}"; do
    if [ -d "$svc" ]; then
        log "   Building pfa/${svc}..."
        docker build -t "pfa/${svc}:latest" "./$svc" || fail "Build failed for $svc"
    else
        warn "   Skipping $svc (folder not found)"
    fi
done

# ── Create GNS3 project ────────────────────────────────────────────────────
log "Creating GNS3 project '$PROJECT_NAME'..."
project_json=$(gns3_api POST /projects "{\"name\":\"${PROJECT_NAME}\"}")
project_id=$(echo "$project_json" | jq -r '.project_id')
[[ -z "$project_id" || "$project_id" == "null" ]] && fail "Project creation failed"
log "   Project ID: $project_id"

gns3_api POST "/projects/${project_id}/open" > /dev/null

# ── Router (3725, 3 FastEthernet interfaces) ──────────────────────────────
log "Adding Cisco 3725 router..."
TEMPLATE=$(gns3_api GET /templates | jq '.[] | select(.name=="Cisco 3725")')
[[ -z "$TEMPLATE" ]] && fail "Cisco 3725 template not found – import it in GNS3 first"

# Slot0: NM-1FE-TX  -> Fa0/0
# Slot1: NM-2FE-TX  -> Fa1/0, Fa1/1
router_data=$(jq -n \
  --arg name "PFA-Router" \
  --arg ios "$IOS_PATH" \
  '{
    "name": $name,
    "node_type": "dynamips",
    "compute_id": "local",
    "properties": {
      "image": $ios,
      "platform": "c3725",
      "ram": 256,
      "nvram": 128,
      "disk0": 0, "disk1": 0,
      "midplane": "c3725",
      "npe": "npe-400",
      "system_id": "FTX0945W0MY",
      "slot0": "NM-1FE-TX",
      "slot1": "NM-2FE-TX",
      "wic0": "WIC-1T",
      "wic1": "WIC-1T"
    }
  }')
router_id=$(gns3_api POST "/projects/${project_id}/nodes" "$router_data" | jq -r '.node_id')
log "   Router ID: $router_id"

# ── Ethernet switches ─────────────────────────────────────────────────────
add_switch() {
    gns3_api POST "/projects/${project_id}/nodes" \
        "{\"name\":\"$1\",\"node_type\":\"ethernet_switch\",\"compute_id\":\"local\"}" \
        | jq -r '.node_id'
}
SW_LAN=$(add_switch "Switch-LAN")
SW_DMZ=$(add_switch "Switch-DMZ")
SW_MON=$(add_switch "Switch-Monitoring")
log "   Switches: LAN=$SW_LAN  DMZ=$SW_DMZ  MON=$SW_MON"

# ── Docker containers ─────────────────────────────────────────────────────
add_docker() {
    local name=$1 image=$2 adapters=${3:-1}
    gns3_api POST "/projects/${project_id}/nodes" \
        "$(jq -n --arg name "$name" --arg img "pfa/${image}:latest" --argjson ad "$adapters" \
           '{"name":$name,"node_type":"docker","compute_id":"local",
             "properties":{"image":$img,"adapters":$ad,"start_command":"",
             "environment":"","console_type":"telnet"}}')" \
        | jq -r '.node_id'
}

log "Adding Docker containers..."
KALI=$(add_docker "Kali"             "kali"            1)
WEB=$(add_docker  "WebServer"        "apache"          2)  # 2 adapters: DMZ + LAN
DB=$(add_docker   "DBServer"         "postgresql"      1)
SURICATA=$(add_docker "Suricata"     "suricata"        2)  # DMZ + Monitoring
ZEEK=$(add_docker  "Zeek"            "zeek"            1)
WAZ_AGENT=$(add_docker "Wazuh-Agent" "wazuh-agent"     1)
WAZ_MGR=$(add_docker  "Wazuh-Mgr"    "wazuh-manager"   1)
WAZ_IDX=$(add_docker  "Wazuh-Idx"    "wazuh-indexer"   1)
WAZ_DASH=$(add_docker "Wazuh-Dash"   "wazuh-dashboard" 1)
PROM=$(add_docker  "Prometheus"      "prometheus"      1)
GRAFANA=$(add_docker "Grafana"       "grafana"         1)

# ── Create all links ──────────────────────────────────────────────────────
link() {
    local data='{"nodes":[{"node_id":"'$1'","adapter_number":'$2',"port_number":'$3'},
                         {"node_id":"'$4'","adapter_number":'$5',"port_number":'$6'}]}'
    gns3_api POST "/projects/${project_id}/links" "$data" > /dev/null
}

log "Wiring topology..."
# Router <-> switches
link "$router_id" 0 0 "$SW_LAN" 0 0   # Fa0/0 -> LAN
link "$router_id" 1 0 "$SW_DMZ" 0 0   # Fa1/0 -> DMZ
link "$router_id" 1 1 "$SW_MON" 0 0   # Fa1/1 -> Monitoring

# LAN switch clients
link "$KALI"   0 0 "$SW_LAN" 1 0      # Kali (10.0.2.100)
link "$DB"     0 0 "$SW_LAN" 2 0      # PostgreSQL (10.0.2.10)
link "$WEB"    1 0 "$SW_LAN" 3 0      # WebServer second NIC (for DB access)

# DMZ switch clients
link "$WEB"      0 0 "$SW_DMZ" 1 0    # WebServer eth0 (10.0.1.10)
link "$SURICATA" 0 0 "$SW_DMZ" 2 0    # Suricata eth0 (10.0.1.100)
link "$ZEEK"     0 0 "$SW_DMZ" 3 0    # Zeek (10.0.1.101)
link "$WAZ_AGENT" 0 0 "$SW_DMZ" 4 0   # Wazuh agent (10.0.1.102)

# Monitoring switch clients
link "$WAZ_MGR"  0 0 "$SW_MON" 1 0    # Wazuh Manager (10.0.3.10)
link "$WAZ_IDX"  0 0 "$SW_MON" 2 0    # Indexer (10.0.3.11)
link "$WAZ_DASH" 0 0 "$SW_MON" 3 0    # Dashboard (10.0.3.12)
link "$PROM"     0 0 "$SW_MON" 4 0    # Prometheus (10.0.3.20)
link "$GRAFANA"  0 0 "$SW_MON" 5 0    # Grafana (10.0.3.30)
link "$SURICATA" 1 0 "$SW_MON" 6 0    # Suricata eth1 (management)

# ── Start everything ──────────────────────────────────────────────────────
log "Starting all nodes..."
for node in $(gns3_api GET "/projects/${project_id}/nodes" | jq -r '.[].node_id'); do
    gns3_api POST "/projects/${project_id}/nodes/${node}/start" > /dev/null
    sleep 2
done

# ── Push Cisco configuration via telnet expect ────────────────────────────
log "Waiting for router to boot (60 sec)..."
sleep 60
ROUTER_PORT=$(gns3_api GET "/projects/${project_id}/nodes/${router_id}" | jq -r '.console')

cat > /tmp/cisco_push.exp << 'EXPECTEOF'
#!/usr/bin/expect -f
set timeout 120
spawn telnet localhost [lindex $argv 0]
expect {
    "Would you like to enter the initial configuration dialog?" { send "no\r"; exp_continue }
    "Press RETURN to get started" { send "\r"; exp_continue }
    "Router>" { }
    timeout { puts "FAIL: No router prompt"; exit 1 }
}
send "enable\r"
expect "Router#"
send "configure terminal\r"
expect "(config)#"

# ── Basic settings ──
send "hostname PFA-Router\r"
send "enable secret PFA@2024\r"
send "ip domain-name pfa.local\r"
send "crypto key generate rsa general-keys modulus 2048\r"
expect {
    "How many bits in the modulus" { send "2048\r"; exp_continue }
    "% Do you really want to replace them?" { send "yes\r"; exp_continue }
    "(config)#" { }
}
send "ip ssh version 2\r"
send "username admin privilege 15 secret PFA@2024\r"
send "line vty 0 4\r"
send "login local\r"
send "transport input ssh\r"
send "exit\r"

# ── Interfaces ──
send "interface FastEthernet0/0\r"
send "description LAN\r"
send "ip address 10.0.2.254 255.255.255.0\r"
send "no shutdown\r"
send "exit\r"

send "interface FastEthernet1/0\r"
send "description DMZ\r"
send "ip address 10.0.1.254 255.255.255.0\r"
send "no shutdown\r"
send "exit\r"

send "interface FastEthernet1/1\r"
send "description Monitoring\r"
send "ip address 10.0.3.254 255.255.255.0\r"
send "no shutdown\r"
send "exit\r"

# ── ACLs (simplified, effective) ──
# LAN: allow to DMZ and Monitoring, deny spoofed external
send "access-list 100 permit ip 10.0.2.0 0.0.0.255 10.0.1.0 0.0.0.255\r"
send "access-list 100 permit ip 10.0.2.0 0.0.0.255 10.0.3.0 0.0.0.255\r"
send "access-list 100 deny ip any any log\r"
send "interface FastEthernet0/0\r"
send "ip access-group 100 in\r"
send "exit\r"

# DMZ: allow to LAN (DB, SSH), allow to Monitoring, block inbound to LAN
send "access-list 101 permit tcp 10.0.1.0 0.0.0.255 10.0.2.0 0.0.0.255 eq 5432\r"
send "access-list 101 permit tcp 10.0.1.0 0.0.0.255 10.0.2.0 0.0.0.255 eq 22\r"
send "access-list 101 permit ip 10.0.1.0 0.0.0.255 10.0.3.0 0.0.0.255\r"
send "access-list 101 deny ip any 10.0.2.0 0.0.0.255 log\r"
send "access-list 101 permit ip any any\r"
send "interface FastEthernet1/0\r"
send "ip access-group 101 in\r"
send "exit\r"

# Monitoring: allow to all, block inbound from outside
send "access-list 102 permit ip 10.0.3.0 0.0.0.255 any\r"
send "access-list 102 deny ip any 10.0.3.0 0.0.0.255 log\r"
send "access-list 102 permit ip any any\r"
send "interface FastEthernet1/1\r"
send "ip access-group 102 in\r"
send "exit\r"

# ── Logging ──
send "logging host 10.0.3.10\r"
send "logging trap informational\r"
send "banner motd # Unauthorized access prohibited - PFA Enterprise #\r"

send "end\r"
expect "PFA-Router#"
send "write memory\r"
expect "PFA-Router#"
send "exit\r"
EXPECTEOF

chmod +x /tmp/cisco_push.exp
/tmp/cisco_push.exp "$ROUTER_PORT" || warn "Cisco configuration may need a manual check"

# ── Verification ──────────────────────────────────────────────────────────
log "Installation complete."
if [ -x "$VERIFY_SCRIPT" ]; then
    log "Running verification..."
    "$VERIFY_SCRIPT"
else
    log "Verification script not found – you can run verify.sh later."
    echo ""
    echo "╔════════════════════════════════════════════════╗"
    echo "║   PFA Enterprise V3 – Topology Summary        ║"
    echo "╠════════════════════════════════════════════════╣"
    echo "║ LAN:   10.0.2.0/24  (Fa0/0)                   ║"
    echo "║   Kali           10.0.2.100                   ║"
    echo "║   DBServer       10.0.2.10                    ║"
    echo "║   WebServer-LAN  2nd NIC                      ║"
    echo "║ DMZ:   10.0.1.0/24  (Fa1/0)                   ║"
    echo "║   WebServer      10.0.1.10                    ║"
    echo "║   Suricata       10.0.1.100                   ║"
    echo "║   Zeek           10.0.1.101                   ║"
    echo "║   Wazuh Agent    10.0.1.102                   ║"
    echo "║ Monitoring: 10.0.3.0/24  (Fa1/1)              ║"
    echo "║   Wazuh Manager  10.0.3.10                    ║"
    echo "║   Indexer        10.0.3.11                    ║"
    echo "║   Dashboard      10.0.3.12                    ║"
    echo "║   Prometheus     10.0.3.20                    ║"
    echo "║   Grafana        10.0.3.30                    ║"
    echo "╚════════════════════════════════════════════════╝"
fi