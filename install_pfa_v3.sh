#!/bin/bash
set -euo pipefail

PROJECT_NAME="PFA_Enterprise_V3"
GNS3_HOST="localhost"
GNS3_PORT=3080
IOS_PATH="/opt/gns3/images/IOS/c3725-adventerprisek9-mz.124-15.T14.bin"
DOCKER_BUILD_CONTEXT="/opt/pfa_build"
LOG_FILE="/var/log/pfa_install.log"
VERIFY_SCRIPT="/usr/local/bin/pfa_verify.sh"
RESTORE_SCRIPT="/usr/local/bin/pfa_restore.sh"

declare -r LAN_SUBNET="10.0.2.0/24"  LAN_GW="10.0.2.254"
declare -r DMZ_SUBNET="10.0.1.0/24"  DMZ_GW="10.0.1.254"
declare -r MON_SUBNET="10.0.3.0/24"  MON_GW="10.0.3.254"

declare -rA CONTAINER_IPS=(
    [Kali]="10.0.2.100/24:10.0.2.254:LAN"
    [WebServer]="10.0.1.10/24:10.0.1.254:DMZ"
    [DBServer]="10.0.2.10/24:10.0.2.254:LAN"
    [Suricata]="10.0.1.100/24:10.0.1.254:DMZ"
    [Zeek]="10.0.1.101/24:10.0.1.254:DMZ"
    [Wazuh-Agent]="10.0.1.102/24:10.0.1.254:DMZ"
    [Wazuh-Mgr]="10.0.3.10/24:10.0.3.254:MON"
    [Wazuh-Idx]="10.0.3.11/24:10.0.3.254:MON"
    [Wazuh-Dash]="10.0.3.12/24:10.0.3.254:MON"
    [Prometheus]="10.0.3.20/24:10.0.3.254:MON"
    [Grafana]="10.0.3.30/24:10.0.3.254:MON"
)

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

LOCKFILE="/tmp/pfa_install.lock"
exec 200>"$LOCKFILE"
flock -n 200 || { echo -e "${RED}[FAIL]${NC} Another install is running."; exit 1; }

exec > >(tee -a "$LOG_FILE") 2>&1
echo -e "\\n${BOLD}$(date) - PFA v3 Installation Start${NC}"
echo "------------------------------------------------"

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
info() { echo -e "  ${CYAN}[..]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[!!]${NC} $1"; }
step_header() { echo ""; echo -e "${BOLD}--- $1 ---${NC}"; }

PROJECT_ID=""; CLEANUP=false
register_state() { echo "$1" >> "/tmp/pfa_install_state"; }

cleanup() {
    $CLEANUP && return 0; CLEANUP=true
    echo ""; warn "Installation FAILED. Rolling back..."
    [[ -n "$PROJECT_ID" ]] && curl -s -X DELETE http://${GNS3_HOST}:${GNS3_PORT}/v2/projects/${PROJECT_ID} >/dev/null 2>&1 || true
    rm -f /tmp/pfa_*.exp /tmp/pfa_*.json /tmp/pfa_install_state 2>/dev/null || true
    exit 1
}
trap cleanup EXIT INT TERM HUP

gns3_api() {
    curl -s -X "$1" http://${GNS3_HOST}:${GNS3_PORT}/v2$2 -H "Content-Type: application/json" -d "${3:-}"
}

check_prereqs() {
    step_header "Prerequisites"
    for cmd in docker curl jq expect; do
        command -v "$cmd" >/dev/null || { echo "Missing: $cmd"; exit 1; }
    done
    ok "Tools present"
    docker info &>/dev/null || { echo "Docker not running"; exit 1; }
    ok "Docker running"
    gns3_api GET /version | jq -e '.version' >/dev/null 2>&1 && ok "GNS3 reachable" || warn "GNS3 not reachable"
    [[ -f "$IOS_PATH" ]] && ok "IOS found" || warn "IOS not found"
}

build_images() {
    step_header "Building Images"
    cd "$DOCKER_BUILD_CONTEXT" || exit 1
    for svc in kali apache postgresql suricata zeek wazuh-agent \
               wazuh-manager wazuh-indexer wazuh-dashboard prometheus grafana; do
        [[ ! -d "$svc" ]] && { warn "Skipping $svc"; continue; }
        docker build -q -t "pfa/${svc}:latest" "./$svc" >/dev/null 2>&1 \
            && ok "pfa/${svc}" || { echo "Build failed"; exit 1; }
    done
}

create_topology() {
    step_header "GNS3 Topology"
    PROJECT_ID=$(gns3_api POST /projects '{"name":"${PROJECT_NAME}"}' | jq -r '.project_id' 2>/dev/null || echo "")
    [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]] && { echo "Project creation failed"; exit 1; }
    ok "Project $PROJECT_ID"
    gns3_api POST "/projects/${PROJECT_ID}/open" >/dev/null 2>&1 || true

    gns3_api GET /templates | jq -e '.[] | select(.name=="Cisco 3725")' >/dev/null 2>&1 || { echo "Cisco 3725 template not found"; exit 1; }

    rdata=$(jq -n --arg n "PFA-Router" --arg i "$IOS_PATH" '{"name":$n,"node_type":"dynamips","compute_id":"local","properties":{"image":$i,"platform":"c3725","ram":256,"slot0":"NM-1FE-TX","slot1":"NM-2FE-TX","system_id":"FTX0945W0MY"}}')
    ROUTER_ID=$(gns3_api POST "/projects/${PROJECT_ID}/nodes" "$rdata" | jq -r '.node_id')
    ok "Router $ROUTER_ID"

    as() { gns3_api POST "/projects/${PROJECT_ID}/nodes" '{"name":"$1","node_type":"ethernet_switch","compute_id":"local"}' | jq -r '.node_id'; }
    SW_LAN=$(as "Switch-LAN"); SW_DMZ=$(as "Switch-DMZ"); SW_MON=$(as "Switch-Monitoring")
    ok "Switches created"

    ad() { gns3_api POST "/projects/${PROJECT_ID}/nodes" 
        "$(jq -n --arg n "$1" --arg img "pfa/${2}:latest" --argjson ad $3 '{"name":$n,"node_type":"docker","compute_id":"local","properties":{"image":$img,"adapters":$ad,"start_command":"","environment":"","console_type":"telnet"}}')" | jq -r '.node_id'; }
    declare -A N
    N[K]=$(ad "Kali" "kali" 1)
    N[W]=$(ad "WebServer" "apache" 2)
    N[D]=$(ad "DBServer" "postgresql" 1)
    N[S]=$(ad "Suricata" "suricata" 2)
    N[Z]=$(ad "Zeek" "zeek" 1)
    N[A]=$(ad "Wazuh-Agent" "wazuh-agent" 1)
    N[M]=$(ad "Wazuh-Mgr" "wazuh-manager" 1)
    N[I]=$(ad "Wazuh-Idx" "wazuh-indexer" 1)
    N[H]=$(ad "Wazuh-Dash" "wazuh-dashboard" 1)
    N[P]=$(ad "Prometheus" "prometheus" 1)
    N[G]=$(ad "Grafana" "grafana" 1)
    ok "Containers added"

    lk() { gns3_api POST "/projects/${PROJECT_ID}/links" 
        "$(jq -n --arg n1 "$1" --arg n2 "$2" '{"nodes":[{"node_id":$n1,"adapter_number":$3,"port_number":$4},{"node_id":$n2,"adapter_number":$5,"port_number":$6}]}')" >/dev/null 2>&1 || true; }
    lk "$ROUTER_ID" 0 0 "$SW_LAN" 0 0
    lk "$ROUTER_ID" 1 0 "$SW_DMZ" 0 0
    lk "$ROUTER_ID" 1 1 "$SW_MON" 0 0
    lk ${N[K]} 0 0 "$SW_LAN" 1 0
    lk ${N[D]} 0 0 "$SW_LAN" 2 0
    lk ${N[W]} 1 0 "$SW_LAN" 3 0
    lk ${N[W]} 0 0 "$SW_DMZ" 1 0
    lk ${N[S]} 0 0 "$SW_DMZ" 2 0
    lk ${N[Z]} 0 0 "$SW_DMZ" 3 0
    lk ${N[A]} 0 0 "$SW_DMZ" 4 0
    lk ${N[S]} 1 0 "$SW_MON" 1 0
    lk ${N[M]} 0 0 "$SW_MON" 2 0
    lk ${N[I]} 0 0 "$SW_MON" 3 0
    lk ${N[H]} 0 0 "$SW_MON" 4 0
    lk ${N[P]} 0 0 "$SW_MON" 5 0
    lk ${N[G]} 0 0 "$SW_MON" 6 0
    ok "Links created"
}

wait_console() {
    local nid=$1 to=$2 el=0
    while [[ $el -lt $to ]]; do
        local cp=$(gns3_api GET "/projects/${PROJECT_ID}/nodes/${nid}" | jq -r '.console' 2>/dev/null || echo 0)
        [[ "$cp" != "0" && "$cp" != "null" && -n "$cp" ]] && return 0
        sleep 5; el=$(($el + 5))
    done; return 1
}

start_nodes() {
    step_header "Starting Nodes"
    for nid in $(gns3_api GET "/projects/${PROJECT_ID}/nodes" | jq -r '.[].node_id'); do
        gns3_api POST "/projects/${PROJECT_ID}/nodes/${nid}/start" >/dev/null 2>&1 || true
        sleep 1
    done
    info "Waiting for router (120s)..."
    wait_console "$ROUTER_ID" 120 && ok "Router ready" || warn "Router not ready"
}

configure_router() {
    step_header "Router Config"
    local rp=$(gns3_api GET "/projects/${PROJECT_ID}/nodes/${ROUTER_ID}" | jq -r '.console' 2>/dev/null || echo 0)
    [[ "$rp" == "0" || "$rp" == "null" ]] && { echo "No console"; exit 1; }

    cat > /tmp/pfa_cisco_push.exp << 'EXPECTEOF'
#!/usr/bin/expect -f
set timeout 180; set rp [lindex $argv 0]
spawn telnet localhost $rp
expect {
    "initial configuration" { send "no\r"; exp_continue }
    "Press RETURN" { send "\r"; exp_continue }
    "Router>" { } timeout { puts "FAIL"; exit 1 }
}
send "enable\r"; expect "Router#"
send "configure terminal\r"; expect "(config)#"
send "hostname PFA-Router\r"; expect "(config)#"
send "no ip domain-lookup\r"; expect "(config)#"
send "ip domain-name pfa.local\r"; expect "(config)#"
send "crypto key generate rsa general-keys modulus 2048\r"
expect { "How many bits" { send "2048\r"; exp_continue } "(config)#" { } timeout { } }
send "ip ssh version 2\r"; expect "(config)#"
send "username admin privilege 15 secret PFA@2024\r"; expect "(config)#"
send "line vty 0 4\r"; expect "(config-line)#"
send "login local\r"; send "transport input ssh\r"; expect "(config-line)#"
send "exit\r"; expect "(config)#"

send "interface FastEthernet0/0\r"; expect "(config-if)#"
send "description LAN\r"
send "ip address 10.0.2.254 255.255.255.0\r"
send "no shutdown\r"
expect "(config-if)#"; send "exit\r"; expect "(config)#"

send "interface FastEthernet1/0\r"; expect "(config-if)#"
send "description DMZ\r"
send "ip address 10.0.1.254 255.255.255.0\r"
send "no shutdown\r"
expect "(config-if)#"; send "exit\r"; expect "(config)#"

send "interface FastEthernet1/1\r"; expect "(config-if)#"
send "description Monitoring\r"
send "ip address 10.0.3.254 255.255.255.0\r"
send "no shutdown\r"
expect "(config-if)#"; send "exit\r"; expect "(config)#"

send "access-list 100 permit ip 10.0.2.0 0.0.0.255 10.0.1.0 0.0.0.255\r"
send "access-list 100 permit ip 10.0.2.0 0.0.0.255 10.0.3.0 0.0.0.255\r"
send "access-list 100 deny ip any any log\r"
send "interface FastEthernet0/0\r"; send "ip access-group 100 in\r"
expect "(config-if)#"; send "exit\r"; expect "(config)#"

send "access-list 101 permit tcp 10.0.1.0 0.0.0.255 10.0.2.0 0.0.0.255 eq 5432\r"
send "access-list 101 permit tcp 10.0.1.0 0.0.0.255 10.0.2.0 0.0.0.255 eq 22\r"
send "access-list 101 permit ip 10.0.1.0 0.0.0.255 10.0.3.0 0.0.0.255\r"
send "access-list 101 deny ip any 10.0.2.0 0.0.0.255 log\r"
send "access-list 101 permit ip any any\r"
send "interface FastEthernet1/0\r"; send "ip access-group 101 in\r"
expect "(config-if)#"; send "exit\r"; expect "(config)#"

send "access-list 102 permit ip 10.0.3.0 0.0.0.255 any\r"
send "access-list 102 deny ip any 10.0.3.0 0.0.0.255 log\r"
send "access-list 102 permit ip any any\r"
send "interface FastEthernet1/1\r"; send "ip access-group 102 in\r"
expect "(config-if)#"; send "exit\r"; expect "(config)#"

send "logging host 10.0.3.10\r"; expect "(config)#"
send "logging trap informational\r"; expect "(config)#"
send "banner motd # Unauthorized access prohibited - PFA Enterprise V3 #\r"; expect "(config)#"
send "end\r"; expect "#"; send "write memory\r"; expect "#"
send "exit\r"
'EXPECTEOF'

    chmod +x /tmp/pfa_cisco_push.exp
    /tmp/pfa_cisco_push.exp "$rp" && ok "Router configured" || warn "Router may need manual config"
}

enhance_suricata() {
    step_header "Suricata"
    local y="${DOCKER_BUILD_CONTEXT}/suricata/suricata.yaml"
    [[ ! -f "$y" ]] && { warn "No suricata.yaml"; return; }
    grep -q "af-packet" "$y" && ok "af-packet mode" || warn "Not af-packet"
    grep -q "10.0.3.0" "$y" && ok "HOME_NET OK" || warn "Check HOME_NET"
}

gen_ip_scripts() {
    step_header "IP Scripts"
    local d="${DOCKER_BUILD_CONTEXT}/scripts"; mkdir -p "$d"
    cat > "${d}/pfa_static_ip.sh" << 'FEOF'
#!/bin/bash
for entry in "$@"; do IFS=":" read -r i c g <<< "$entry"
    [[ -z "$i" || -z "$c" ]] && continue
    for t in $(seq 1 30); do ip link show "$i" >/dev/null 2>&1 && break; sleep 1; done
    ip link set "$i" up 2>/dev/null; ip addr flush dev "$i" 2>/dev/null
    ip addr add "$c" dev "$i" 2>/dev/null && echo "$i" -> "$c"
    [[ -n "$g" ]] && { ip route del default 2>/dev/null; ip route add default via "$g" dev "$i" 2>/dev/null; }
done
'FEOF'
    chmod +x "${d}/pfa_static_ip.sh"
    ok "Static IP script"
}

deploy_scripts() {
    step_header "Deploy"
    cat > "$VERIFY_SCRIPT" << 'VEOF'
#!/bin/bash
set -euo pipefail; LOG="/var/log/pfa_verify.log"; exec > >(tee -a "$LOG") 2>&1
P=0; F=0; W=0
ok() { P=$(($P + 1)); echo "  [PASS] $1"; }
fl() { F=$(($F + 1)); echo "  [FAIL] $1"; }
wn() { W=$(($W + 1)); echo "  [WARN] $1"; }
echo "PFA V3 Verify"; echo "$(date)"
echo "[1] Docker"
for i in kali apache postgresql suricata zeek wazuh-agent wazuh-manager wazuh-indexer wazuh-dashboard prometheus grafana; do
    docker images --format {{.Repository}} 2>/dev/null | grep -q "pfa/${i}" && ok "pfa/${i}" || wn "pfa/${i} missing"
done
echo "[2] GNS3"
curl -sf http://localhost:3080/v2/version >/dev/null && ok "API" || fl "API"
echo "[3] Project"
ID=$(curl -sf http://localhost:3080/v2/projects 2>/dev/null | jq -r '.[] | select(.name=="PFA_Enterprise_V3") | .project_id' 2>/dev/null)
[[ -n "$ID" ]] && ok "Project" || fl "Project missing"
echo "[4] Nodes"
for n in PFA-Router Switch-LAN Switch-DMZ Switch-Monitoring Kali WebServer DBServer Suricata Zeek Wazuh-Agent Wazuh-Mgr Wazuh-Idx Wazuh-Dash Prometheus Grafana; do
    curl -sf http://localhost:3080/v2/projects/${ID}/nodes 2>/dev/null | jq -e --arg a "$n" '.[] | select(.name==$a)' >/dev/null 2>&1 && ok "$n" || fl "$n"
done
echo "[5] Connectivity"
for pair in "Kali:10.0.2.100" "Web:10.0.1.10" "DB:10.0.2.10" "Suricata:10.0.1.100" "Zeek:10.0.1.101" "Agent:10.0.1.102" "Mgr:10.0.3.10" "Idx:10.0.3.11" "Dash:10.0.3.12" "Prom:10.0.3.20" "Graf:10.0.3.30"; do
    ip=${pair##*:}
    ping -c 1 -W 2 "$ip" >/dev/null 2>&1 && ok ${pair%%:*} || wn ${pair%%:*} unreachable
done
echo "PASS=$P FAIL=$F WARN=$W"
'VEOF'
    chmod +x "$VERIFY_SCRIPT"

    cat > "$RESTORE_SCRIPT" << 'REOF'
#!/bin/bash
set -euo pipefail
PID=$(curl -sf http://localhost:3080/v2/projects 2>/dev/null | jq -r '.[] | select(.name=="PFA_Enterprise_V3") | .project_id' 2>/dev/null)
[[ -n "$PID" ]] && curl -s -X DELETE http://localhost:3080/v2/projects/${PID} >/dev/null 2>&1 && echo "Project removed" || echo "Project not found"
[[ ${1:-} != "--keep-images" ]] && docker images --format {{.Repository}} | grep "^pfa/" | xargs -r docker rmi >/dev/null 2>&1 || true
echo "Teardown done"
'REOF'
    chmod +x "$RESTORE_SCRIPT"
    ok "Scripts deployed"
}

summary() {
    echo ""
    echo "PFA Enterprise V3 - Install Complete"
    echo "Project: ${PROJECT_NAME}  Log: ${LOG_FILE}"
    echo "LAN: 10.0.2.0/24  DMZ: 10.0.1.0/24  MON: 10.0.3.0/24"
    echo "Kali:10.0.2.100 Web:10.0.1.10+10.0.2.11 DB:10.0.2.10"
    echo "Suricata:10.0.1.100+10.0.3.100 Zeek:10.0.1.101 Agent:10.0.1.102"
    echo "Mgr:10.0.3.10 Idx:10.0.3.11 Dash:10.0.3.12"
    echo "Prom:10.0.3.20 Graf:10.0.3.30"
    echo "Verify: ${VERIFY_SCRIPT}"
    echo "Teardown: ${RESTORE_SCRIPT}"
}

main() {
    trap "" EXIT INT TERM HUP
    check_prereqs; gen_ip_scripts; enhance_suricata
    build_images; create_topology; start_nodes; configure_router
    deploy_scripts; trap - EXIT INT TERM HUP
    summary
    [[ -x "$VERIFY_SCRIPT" ]] && bash "$VERIFY_SCRIPT" || true
    echo "Done."
}

main "$@"

