# PFA - Architecture Technique

## Vue d'ensemble

Plateforme de securite modulaire virtualisee. Cisco 3725 est le **seul routeur**.
Docker ne fait **aucun routage**. Docker fournit uniquement les conteneurs.

## Topologie Reseau

`
                    Kali (.100)
                        |
                  PFA-ROUTER (Cisco 3725)
              Fa0/0    |    Fa0/1     Fa1/0
               LAN     |     DMZ     Monitoring
                        |
    ---------+---------+---------+----------
    |        |         |         |         |
PostgreSQL  Kali    Web     Suricata   Wazuh Mgr
(.10)     (.100)  (.10)    (.100)     (.10)
                           Zeek       Indexer
                           (.101)     (.11)
                           Wazuh-Agt  Dashboard
                           (.102)     (.12)
                                      Prometheus
                                      (.20)
                                      Grafana
                                      (.30)
`

## Segments Reseau

| Segment | Sous-reseau | Passerelle Cisco | Equipements |
|---------|-------------|-----------------|-------------|
| LAN     | 10.0.2.0/24 | 10.0.2.254     | Kali, PostgreSQL |
| DMZ     | 10.0.1.0/24 | 10.0.1.254     | Web, Suricata, Zeek |
| Monitor | 10.0.3.0/24 | 10.0.3.254     | Wazuh, Prometheus, Grafana |

## Regles ACL

| ACL | Interface | Politique |
|-----|-----------|-----------|
| 100 | Fa0/0 IN  | LAN->DMZ: seulement Kali->Web HTTP/SSH. DMZ->LAN: etabli seulement |
| 101 | Fa0/1 IN  | DMZ->LAN: INTERDIT (pivot prevention). DMZ->MON: autorise |
| 102 | Fa1/0 IN  | MON->DMZ: seulement agent enrollment, metrics. Sinon INTERDIT |
| 110 | Tous OUT  | Anti-spoofing: verifie source IP correspond au segment |

## Pipeline de Detection

`
Attaque (Kali 10.0.2.100)
  -> Cisco Fa0/0 (ACL 100 verifie)
  -> Cisco route via Fa0/1
  -> DMZ switch
  -> WebServer 10.0.1.10:80 (cible)
  -> Suricata 10.0.1.100 (promisc, capture tout trafic DMZ)
  -> eve.json ecrit dans volume Docker
  -> Wazuh-Agent 10.0.1.102 lit eve.json
  -> Cisco route vers Monitoring (ACL 101 autorise)
  -> Wazuh-Manager 10.0.3.10:1514 (alerte)
  -> Filebeat -> Wazuh-Indexer 10.0.3.11:9200
  -> Wazuh-Dashboard 10.0.3.12:5601 (visualisation)
  -> Prometheus 10.0.3.20 (scrape Suricata metrics)
  -> Grafana 10.0.3.30 (dashboards)
`

## Images Docker

### Images custom (build avec build-all.ps1)
- **pfa-kali**: Kali Linux avec nmap, hydra, nikto, hping3, metasploit
- **pfa-webserver**: Apache+PHP vulnerable (SQLi dans login.php)
- **pfa-postgresql**: PostgreSQL 15 avec base initialisee
- **pfa-suricata**: IDS avec regles custom (30 regles PFA)
- **pfa-zeek**: Analyseur de protocole reseau
- **pfa-wazuh-agent**: Agent Wazuh pour collecte logs Suricata

### Images standard (pull depuis Docker Hub)
- wazuh/wazuh-manager:4.7.3
- wazuh/wazuh-indexer:4.7.3
- wazuh/wazuh-dashboard:4.7.3
- prom/prometheus:latest
- grafana/grafana:latest

## Scripts d'attaque

| Script | Outil | Cible | Regle Suricata |
|--------|-------|-------|----------------|
| recon.sh | nmap | Web 10.0.1.10 | sid:1000001-2 |
| bruteforce.sh | hydra | Web:22,80 | sid:1000010-11 |
| web_scan.sh | curl+nikto | Web:80 | sid:1000020-41 |
| dos_attack.sh | hping3 | Web:80 | sid:1000060-61 |
| arp_spoof.sh | arpspoof | LAN | sid:1000030 |
| metasploit_exploit.rc | msfconsole | Web:80 | sid:1000050-52 |

## Ports exposes vers Windows

| Service | Port | URL |
|---------|------|-----|
| Wazuh Dashboard | 5601 | http://localhost:5601 |
| Prometheus | 9090 | http://localhost:9090 |
| Grafana | 3000 | http://localhost:3000 |
