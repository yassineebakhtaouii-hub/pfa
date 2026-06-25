# PFA - Plateforme de Securite Modulaire Virtualisee

Cisco 3725 est le SEUL routeur. Docker ne fait AUCUN routage.
Tout le trafic entre segments (LAN/DMZ/Monitoring) passe par le routeur Cisco.

## Quick Start

```powershell
cd C:\PFA\gns3-pfa
.\build-all.ps1
```

Voir docs/gns3-import-guide.md pour l''import GNS3.

## Segments Reseau

| Segment | Sous-reseau | Passerelle | Equipements |
|---------|-------------|------------|-------------|
| LAN | 10.0.2.0/24 | 10.0.2.254 (Cisco) | Kali (.100), PostgreSQL (.10) |
| DMZ | 10.0.1.0/24 | 10.0.1.254 (Cisco) | Web (.10), Suricata (.100), Zeek (.101) |
| Monitoring | 10.0.3.0/24 | 10.0.3.254 (Cisco) | Wazuh (.10-.12), Prom (.20), Graf (.30) |

## Pipeline

Kali -> Cisco ACL 100 -> Web -> Suricata -> Wazuh-Agent -> Cisco ACL 101
-> Wazuh-Manager -> Wazuh-Indexer -> Wazuh-Dashboard | Grafana
