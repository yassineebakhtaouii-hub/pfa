# Guide d'Import GNS3 - PFA v2.0

## Prerequisites

- GNS3 2.2.x installe (local server)
- Docker Desktop pour Windows installe
- Powershell (administrateur non requis)

## Etape 1: Builder les images Docker

`powershell
cd C:\PFA\gns3-pfa
.\build-all.ps1
`

Verifier:
`powershell
.\verify.ps1
`

## Etape 2: Creer les templates Docker dans GNS3

1. Ouvrir GNS3 > **Edit** > **Preferences** > **Docker**
2. Cliquer **New** et configurer chaque template:

### Template: pfa-kali
- **Image**: pfa-kali:latest
- **Start command**: /entrypoint.sh bash
- **Console**: enable
- **Adapters**: 1
- **Ports**: aucun

### Template: pfa-webserver
- **Image**: pfa-webserver:latest
- **Adapters**: 1
- **Ports**: Publier 80->8080, 22->2222 (optionnel)

### Template: pfa-postgresql
- **Image**: pfa-postgresql:latest
- **Adapters**: 1

### Template: pfa-suricata
- **Image**: pfa-suricata:latest
- **Start command**: /entrypoint.sh
- **Adapters**: 1
- **Capabilities**: NET_ADMIN, NET_RAW

### Template: pfa-zeek
- **Image**: pfa-zeek:latest
- **Adapters**: 1

### Template: pfa-wazuh-agent
- **Image**: pfa-wazuh-agent:latest
- **Adapters**: 1

### Template: wazuh-manager
- **Image**: wazuh/wazuh-manager:4.7.3
- **Adapters**: 1
- **Ports**: 1514, 1515, 55000

### Template: wazuh-indexer
- **Image**: wazuh/wazuh-indexer:4.7.3
- **Adapters**: 1
- **Ports**: 9200

### Template: wazuh-dashboard
- **Image**: wazuh/wazuh-dashboard:4.7.3
- **Adapters**: 1
- **Ports**: 5601->5601

### Template: prometheus
- **Image**: prom/prometheus:latest
- **Adapters**: 1
- **Ports**: 9090->9090

### Template: grafana
- **Image**: grafana/grafana:latest
- **Adapters**: 1
- **Ports**: 3000->3000

## Etape 3: Creer la topologie GNS3

### Ajouter les noeuds
1. Glisser Cisco 3725 depuis **Router templates**
2. Glisser 3 switches Ethernet depuis **Switch templates**
3. Glisser chaque template Docker depuis **Docker templates**
4. Nommer les noeuds: PFA-ROUTER, SW-LAN, SW-DMZ, SW-MON, KALI, WEB, DB, SURICATA, ZEEK, WAZUH-AGT, WAZUH-MGR, WAZUH-IDX, WAZUH-DASH, PROMETHEUS, GRAFANA

### Connecter les cables

**Switch LAN (SW-LAN)**:
- Port 1 -> PFA-ROUTER Fa0/0
- Port 2 -> KALI eth0
- Port 3 -> DB eth0

**Switch DMZ (SW-DMZ)**:
- Port 1 -> PFA-ROUTER Fa0/1
- Port 2 -> WEB eth0
- Port 3 -> SURICATA eth0
- Port 4 -> ZEEK eth0
- Port 5 -> WAZUH-AGT eth0

**Switch Monitoring (SW-MON)**:
- Port 1 -> PFA-ROUTER Fa1/0
- Port 2 -> WAZUH-MGR eth0
- Port 3 -> WAZUH-IDX eth0
- Port 4 -> WAZUH-DASH eth0
- Port 5 -> PROMETHEUS eth0
- Port 6 -> GRAFANA eth0

## Etape 4: Configurer les IPs statiques

Importer la config Cisco:
1. Double-cliquer PFA-ROUTER > **Console**
2. Enable mode: nable (mot de passe: PFA_Router_Enable_2026)
3. Configurer terminal: configure terminal
4. Copier le contenu de cisco\\router-config.cfg
5. Sauvegarder: write memory

Configurer les IPs des conteneurs:
- Chaque conteneur doit etre configure avec l'IP statique correspondante
- Les entrypoints tentent de configurer la route par defaut automatiquement
- Si le reseau GNS3 n'attribue pas les IPs, les configurer manuellement:

`ash
# Exemple pour WEB (depuis la console GNS3 du conteneur)
ip addr add 10.0.1.10/24 dev eth0
ip link set eth0 up
ip route add default via 10.0.1.254
`

## Etape 5: Demarrer et verifier

1. Demarrer PFA-ROUTER
2. Demarrer les switches
3. Demarrer les conteneurs dans l'ordre: DB -> WEB -> SURICATA -> ZEEK -> WAZUH-IDX -> WAZUH-MGR -> WAZUH-DASH -> WAZUH-AGT -> PROMETHEUS -> GRAFANA -> KALI
4. Verifier depuis KALI:
`ash
ping 10.0.1.10
ping 10.0.1.254
ping 10.0.3.10
`

## Etape 6: Lancer les attaques

`ash
# Reconnaissance
/opt/pfa/attacks/recon.sh

# Brute force
/opt/pfa/attacks/bruteforce.sh

# Web scan
/opt/pfa/attacks/web_scan.sh

# Tableau de bord (Grafana)
# http://localhost:3000  (admin:PFA_Admin_2026)

# Wazuh Dashboard
# http://localhost:5601  (admin:PFA_Admin_2026)
`

## Depannage

| Probleme | Cause | Solution |
|----------|-------|----------|
| Conteneur ne demarre pas | Image non trouvee | ./build-all.ps1 |
| Pas de ping entre segments | ACL Cisco | Verifier ACL 100-102, log sur le routeur |
| Suricata ne detecte pas | Mauvaise interface | Verifier suricata -i eth0 |
| Wazuh pas d'alertes | Agent non connecte | Verifier wazuh-agent -d sur WAZUH-AGT |
| Grafana dashboard vide | Pas de donnees | Lancer une attaque depuis KALI |
