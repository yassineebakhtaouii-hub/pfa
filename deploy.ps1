# =============================================================================
# deploy.ps1 — PFA Full Deployment Script
# =============================================================================
param([switch]$GNS3Server, [switch]$DockerOnly)

$ErrorActionPreference = "Continue"
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host @"
============================================
  PFA - Plateforme de Securite Virtualisee
  Deployment Script
============================================
"@ -ForegroundColor Cyan

# =============================================
# STEP 1: Verify environment
# =============================================
Write-Host "[1/5] Verifying environment..." -ForegroundColor Yellow

# Check Docker
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Host "  [+] Docker running" -ForegroundColor Green }
else { Write-Host "  [!] Docker not running" -ForegroundColor Red }

# Check images
$required = @("pfa-kali","pfa-webserver","pfa-postgresql","pfa-suricata","pfa-zeek",
              "pfa-wazuh-agent","pfa-wazuh-manager","pfa-wazuh-indexer",
              "pfa-wazuh-dashboard","pfa-prometheus","pfa-grafana")
$images = docker images --format "{{.Repository}}" 2>&1
foreach ($img in $required) {
    if ($images -contains $img) { Write-Host "  [+] $img" -ForegroundColor Green }
    else { Write-Host "  [!] $img missing - run build-all.ps1" -ForegroundColor Red }
}

# =============================================
# STEP 2: Start Docker containers
# =============================================
Write-Host "[2/5] Starting Docker containers..." -ForegroundColor Yellow
docker compose -f "$ROOT\docker-compose.test.yml" up -d 2>&1
if ($LASTEXITCODE -eq 0) { Write-Host "  [+] Containers started" -ForegroundColor Green }
else { Write-Host "  [!] Container start failed" -ForegroundColor Red }

Start-Sleep 10

# Verify services
Write-Host "[3/5] Checking services..." -ForegroundColor Yellow
$checks = @(
    @{name="WebServer"; url="http://localhost:8080/"; expected=200},
    @{name="Grafana"; url="http://localhost:3000/api/health"; expected=200},
    @{name="Prometheus"; url="http://localhost:9090/-/ready"; expected=200}
)
foreach ($check in $checks) {
    try {
        $r = curl -s -o /dev/null -w "%{http_code}" $check.url 2>&1
        if ($r -eq $check.expected) {
            Write-Host "  [+] $($check.name) - OK" -ForegroundColor Green
        } else {
            Write-Host "  [!] $($check.name) - Status $r" -ForegroundColor Yellow
        }
    } catch { Write-Host "  [!] $($check.name) - Failed" -ForegroundColor Red }
}

# =============================================
# STEP 4: GNS3
# =============================================
if (-not $DockerOnly) {
    Write-Host "[4/5] GNS3..." -ForegroundColor Yellow
    $gns3Server = "C:\Program Files\GNS3\gns3server.exe"
    $gns3Gui = "C:\Program Files\GNS3\GNS3.exe"
    
    if (Test-Path $gns3Server) {
        $proc = Get-Process gns3server -ErrorAction SilentlyContinue
        if (-not $proc) {
            Start-Process -FilePath $gns3Server -NoNewWindow -PassThru
            Write-Host "  [+] GNS3 server started" -ForegroundColor Green
        } else { Write-Host "  [+] GNS3 server already running" -ForegroundColor Green }
        
        Write-Host "  Open GNS3 GUI: $gns3Gui" -ForegroundColor Yellow
        Write-Host "  Project: pfa (auto-created at ~\GNS3\projects\pfa)" -ForegroundColor Yellow
    }
}

# =============================================
# STEP 5: Summary
# =============================================
Write-Host "[5/5] Deployment Complete!" -ForegroundColor Cyan
Write-Host @"
============================================
  PFA - ACCESS INFORMATION
============================================

Web UI:
  Grafana:        http://localhost:3000  (admin:PFA_Admin_2026)
  Prometheus:     http://localhost:9090
  Wazuh Dashboard: http://localhost:5601 (admin:PFA_Admin_2026)
  WebServer:      http://localhost:8080

From Kali (inside GNS3):
  kubectl exec -it pfa-kali -- /opt/pfa/attacks/recon.sh

From GNS3 VM SSH:
  ssh gns3@192.168.56.101 (password: gns3)

GNS3:
  Project: pfa (Open in GNS3 GUI)
  Cisco Router: PFA-ROUTER (config in cisco/router-config.cfg)
  Switches: SW-LAN, SW-DMZ, SW-MON

To stop:
  docker compose -f $ROOT\docker-compose.test.yml down -v
  taskkill /f /im gns3server.exe
"@ -ForegroundColor Green