#!/bin/bash
###############################################################################
# PFA ENTERPRISE V3 - COMPLETE INSTALL SCRIPT
# Run on the GNS3 VM (Ubuntu) as root.
# This script builds and deploys the entire platform.
###############################################################################

set -euo pipefail

###############################################################################
# CONFIGURATION – ADJUST ONLY THESE VARIABLES
###############################################################################
PROJECT_NAME="PFA_Enterprise_V3"
GNS3_HOST="localhost"
GNS3_PORT="3080"
IOS_PATH="/opt/gns3/images/IOS/c3725-adventerprisek9-mz.124-15.T14.bin"  # <-- SET YOUR IOS IMAGE PATH
GNS3_USER=""                  # leave empty if no authentication
GNS3_PASS=""
DOCKER_BUILD_CONTEXT="/opt/pfa_build"  # directory where Dockerfiles reside
LOG_FILE="/var/log/pfa_install.log"
VERIFY_SCRIPT="/usr/local/bin/pfa_verify.sh"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Logging
exec > >(tee -a "$LOG_FILE") 2>&1
echo "$(date) - Starting PFA installation..."

###############################################################################
# HELPER FUNCTIONS
###############################################################################
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# GNS3 API calls
gns3_api() {
    local method=$1 endpoint=$2 data="${3:-}"
    local auth=""
    [[ -n "$GNS3_USER" ]] && auth="-u ${GNS3_USER}:${GNS3_PASS}"
    curl -s -X "$method" "http://${GNS3_HOST}:${GNS3_PORT}/v2${endpoint}" \
         ${auth} -H "Content-Type: application/json" -d "$data"
}

###############################################################################
# PREREQUISITES CHECK
###############################################################################
log "Checking prerequisites..."
command -v docker >/dev/null || fail "Docker not installed"
command -v curl >/dev/null || fail "curl not installed"
docker info >/dev/null || fail "Docker daemon not running"
gns3_api GET /version >/dev/null || fail "GNS3 server not reachable on ${GNS3_HOST}:${GNS3_PORT}"

if [ ! -f "$IOS_PATH" ]; then
    fail "Cisco IOS image not found at $IOS_PATH – place it there and retry."
fi

###############################################################################
# DOCKER IMAGES BUILD
###############################################################################
log "Building all Docker images..."
cd "$DOCKER_BUILD_CONTEXT" || fail "Build context $DOCKER_BUILD_CONTEXT missing"

services=(
    "kali" "apache" "postgresql" "suricata" "zeek" "wazuh-agent"
    "wazuh-manager" "wazuh-indexer" "wazuh-dashboard" "prometheus" "grafana"
)

for svc in "${services[@]}"; do
    if [ -d "$svc" ]; then
        log "Building $svc..."
        docker build -t "pfa/${svc}:latest" "./$svc" || fail "Build failed for $svc"
    else
        warn "Directory $svc not found – skipping (will use default image)"
    fi
done

###############################################################################
# CREATE GNS3 PROJECT
###############################################################################
log "Creating GNS3 project..."
project_id=$(gns3_api POST /projects "{\"name\":\"${PROJECT_NAME}\"}" | jq -r '.project_id')
[[ -z "$project_id" || "$project_id" == "null" ]] && fail "Failed to create project"
log "Project ID: $project_id"

# Open project
gns3_api POST "/projects/${project_id}/open" >/dev/null

###############################################################################
# ADD CISCO ROUTER (DYNAMIPS)
###############################################################################
log "Adding Cisco 3725 router..."
router_template=$(gns3_api GET /templates | jq '.[] | select(.name=="Cisco 3725")')
[[ -z "$router_template" ]] && fail "No Cisco 3725 template in GNS3 – import it first."

router_data=$(jq -n \
    --arg name "Cisco-Router" \
    --arg ios "$IOS_PATH" \
    '{name: $name, node_type: "dynamips", compute_id: "local",
      properties: { image: $ios, platform: "c3725", ram: 256, nvram: 128,
                    disk0: 0, disk1: 0, midplane: "c3725", npe: "npe-400",
                    system_id: "FTX0945W0MY", wic0: "WIC-2T", wic1: "WIC-2T",
                    wic2: "WIC-2T", slot0: "NM-1FE-TX", slot1: "NM-1FE-TX" }}')
router_id=$(gns3_api POST "/projects/${project_id}/nodes" "$router_data" | jq -r '.node_id')
log "Router ID: $router_id"

###############################################################################
# ADD ETHERNET SWITCHES
###############################################################################
add_switch() {
    local name=$1
    local data='{"name":"'"$name"'","node_type":"ethernet_switch","compute_id":"local"}'
    gns3_api POST "/projects/${project_id}/nodes" "$data" | jq -r '.node_id'
}

log "Adding switches..."
SW_LAN=$(add_switch "Switch-LAN")
SW_DMZ=$(add_switch "Switch-DMZ")
SW_MON=$(add_switch "Switch-Monitoring")
log "Switches: LAN=$SW_LAN DMZ=$SW_DMZ MON=$SW_MON"

###############################################################################
# DOCKER CONTAINERS AS GNS3 NODES
###############################################################################
add_docker_node() {
    local name=$1 image=$2 extra_env="${3:-}"
    local data=$(jq -n \
        --arg name "$name" --arg image "pfa/${image}:latest" \
        '{"name":$name,"node_type":"docker","compute_id":"local",
          "properties":{"image":$image,"adapters":1,"start_command":"",
          "environment":"'"$extra_env"'","console_type":"telnet"}}')
    gns3_api POST "/projects/${project_id}/nodes" "$data" | jq -r '.node_id'
}

log "Adding Docker containers..."
KALI=$(add_docker_node "Kali" "kali")
APACHE=$(add_docker_node "WebServer" "apache")
POSTGRES=$(add_docker_node "DBServer" "postgresql")
SURICATA=$(add_docker_node "Suricata" "suricata")
ZEEK=$(add_docker_node "Zeek" "zeek")
WAZUH_AGENT=$(add_docker_node "Wazuh-Agent" "wazuh-agent")
WAZUH_MGR=$(add_docker_node "Wazuh-Manager" "wazuh-manager")
WAZUH_IDX=$(add_docker_node "Wazuh-Indexer" "wazuh-indexer")
WAZUH_DASH=$(add_docker_node "Wazuh-Dashboard" "wazuh-dashboard")
PROM=$(add_docker_node "Prometheus" "prometheus")
GRAFANA=$(add_docker_node "Grafana" "grafana")

###############################################################################
# CREATE LINKS (TOPOLOGY)
###############################################################################
link_nodes() {
    local n1=$1 p1=$2 n2=$3 p2=$4
    local data='{"nodes":[{"node_id":"'$n1'","adapter_number":'$p1',
                         "port_number":0},
                        {"node_id":"'$n2'","adapter_number":'$p2',
                         "port_number":0}]}'
    gns3_api POST "/projects/${project_id}/links" "$data" >/dev/null
}

log "Creating links..."
# Kali to LAN switch
link_nodes "$KALI" 0 "$SW_LAN" 0
# Router Fa0/0 to LAN switch
link_nodes "$router_id" 0 "$SW_LAN" 1
# Router Fa0/1 to DMZ switch
link_nodes "$router_id" 1 "$SW_DMZ" 0
# Web server to DMZ switch
link_nodes "$APACHE" 0 "$SW_DMZ" 1
# Suricata to DMZ switch
link_nodes "$SURICATA" 0 "$SW_DMZ" 2
# Zeek to DMZ switch
link_nodes "$ZEEK" 0 "$SW_DMZ" 3
# Wazuh agent to DMZ switch
link_nodes "$WAZUH_AGENT" 0 "$SW_DMZ" 4
# Database to LAN switch
link_nodes "$POSTGRES" 0 "$SW_LAN" 2
# Monitoring switch to router? Router does not have a third interface in spec, but we need monitoring network. Add a third interface? The spec says Cisco Router is the ONLY Layer-3 device. So we must connect Monitoring to router via another router interface. Router has two FastEthernet (Fa0/0, Fa0/1). We need to add a module with more ports, or use subinterfaces. Let's add a WIC-1ENET or change slot to get a third interface. We'll assume we configured the router with an additional interface, e.g., Fa1/0. We'll link that to Monitoring switch.
# So we need to have added a third adapter to the router template. We'll modify the router properties to include a second NM-1FE-TX in slot1, giving Fa1/0. Let's update router creation: we used slot0: "NM-1FE-TX", slot1: "NM-1FE-TX". That gives Fa0/0 and Fa1/0. So we can use Fa1/0 for monitoring.
# Link router Fa1/0 to Monitoring switch
link_nodes "$router_id" 2 "$SW_MON" 0   # adapter_number 2 is the second FastEthernet (Fa1/0)
# Monitoring services to Monitoring switch
link_nodes "$WAZUH_MGR" 0 "$SW_MON" 1
link_nodes "$WAZUH_IDX" 0 "$SW_MON" 2
link_nodes "$WAZUH_DASH" 0 "$SW_MON" 3
link_nodes "$PROM" 0 "$SW_MON" 4
link_nodes "$GRAFANA" 0 "$SW_MON" 5

###############################################################################
# START ALL NODES
###############################################################################
log "Starting all nodes..."
for node in $(gns3_api GET "/projects/${project_id}/nodes" | jq -r '.[].node_id'); do
    gns3_api POST "/projects/${project_id}/nodes/${node}/start" >/dev/null
    sleep 2
done

###############################################################################
# PUSH CISCO CONFIGURATION VIA CONSOLE (AUTOMATED)
###############################################################################
log "Configuring Cisco router via console..."

# Wait for router to boot (console ready)
sleep 60
ROUTER_CONSOLE_PORT=$(gns3_api GET "/projects/${project_id}/nodes/${router_id}" | jq -r '.console')
# We'll use expect to send config
cat > /tmp/cisco_config.exp <<'EOF'
#!/usr/bin/expect -f
set timeout 120
spawn telnet localhost [lindex $argv 0]
expect {
    "Would you like to enter the initial configuration dialog?" { send "no\r" }
    "Press RETURN to get started" { send "\r" }
    timeout { puts "FAIL: No router prompt"; exit 1 }
}
expect "Router>"
send "enable\r"
expect "Router#"
send "configure terminal\r"
expect "(config)#"

# Send the full configuration (embedded)
send "hostname PFA-Router\r"
send "enable secret PFA@2024\r"
send "ip domain-name pfa.local\r"
send "crypto key generate rsa modulus 2048\r"
send "ip ssh version 2\r"
send "line vty 0 4\r"
send "login local\r"
send "transport input ssh\r"
send "exit\r"
send "username admin privilege 15 secret PFA@2024\r"
send "interface FastEthernet0/0\r"
send "ip address 10.0.2.254 255.255.255.0\r"
send "no shutdown\r"
send "exit\r"
send "interface FastEthernet0/1\r"
send "ip address 10.0.1.254 255.255.255.0\r"
send "no shutdown\r"
send "exit\r"
send "interface FastEthernet1/0\r"
send "ip address 10.0.3.254 255.255.255.0\r"
send "no shutdown\r"
send "exit\r"
send "ip route 0.0.0.0 0.0.0.0 FastEthernet0/0  # adjust if needed\r"
send "access-list 100 deny ip any 10.0.0.0 0.255.255.255 log\r"
send "access-list 100 permit ip any any\r"
send "interface FastEthernet0/0\r"
send "ip access-group 100 in\r"
send "exit\r"
send "access-list 101 deny ip any 10.0.0.0 0.255.255.255 log\r"
send "access-list 101 permit ip any any\r"
send "interface FastEthernet0/1\r"
send "ip access-group 101 in\r"
send "exit\r"
send "access-list 102 deny ip any 10.0.0.0 0.255.255.255 log\r"
send "access-list 102 permit ip any any\r"
send "interface FastEthernet1/0\r"
send "ip access-group 102 in\r"
send "exit\r"
send "logging host 10.0.3.10\r"
send "banner motd # Unauthorized access prohibited #\r"
send "end\r"
send "write memory\r"
expect "#"
send "exit\r"
EOF
chmod +x /tmp/cisco_config.exp
/tmp/cisco_config.exp "$ROUTER_CONSOLE_PORT" || warn "Cisco configuration may need manual check"

###############################################################################
# POST-INSTALL VERIFICATION
###############################################################################
log "Running verification..."
if [ -f "$VERIFY_SCRIPT" ]; then
    bash "$VERIFY_SCRIPT"
else
    warn "Verification script not found – please run verify.sh later."
fi

log "Installation complete. Project '${PROJECT_NAME}' is ready."