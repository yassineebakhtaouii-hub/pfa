#!/usr/bin/env powershell
# =============================================================================
# build-all.ps1 - Build all PFA Docker images
# =============================================================================
# Usage: .\build-all.ps1 [-Clean]
# =============================================================================
param([switch]$Clean)

$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$IMAGES = "$ROOT\images"
$ERRORS = 0

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PFA - Build All Docker Images" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Optional clean build
if ($Clean) {
    Write-Host "[*] Clean build requested - pulling base images..." -ForegroundColor Yellow
}

# Define images to build
$imageList = @(
    @{Name="pfa-kali";         Path="$IMAGES\kali";         Description="Kali Linux Attack Machine"}
    @{Name="pfa-webserver";    Path="$IMAGES\webserver";    Description="Vulnerable Apache WebServer"}
    @{Name="pfa-postgresql";   Path="$IMAGES\postgresql";   Description="PostgreSQL Database Server"}
    @{Name="pfa-suricata";     Path="$IMAGES\suricata";     Description="Suricata IDS/IPS"}
    @{Name="pfa-zeek";         Path="$IMAGES\zeek";         Description="Zeek Network Monitor"}
    @{Name="pfa-wazuh-agent";  Path="$IMAGES\wazuh-agent";  Description="Wazuh SIEM Agent"}
)

# Build standard images (no custom build needed, use directly in GNS3)
$standardImages = @(
    @{Name="wazuh/wazuh-manager:4.7.3";     Description="Wazuh Manager (SIEM)"}
    @{Name="wazuh/wazuh-indexer:4.7.3";     Description="Wazuh Indexer (OpenSearch)"}
    @{Name="wazuh/wazuh-dashboard:4.7.3";   Description="Wazuh Dashboard (UI)"}
    @{Name="prom/prometheus:latest";        Description="Prometheus (Metrics)"}
    @{Name="grafana/grafana:latest";        Description="Grafana (Dashboards)"}
)

Write-Host "[*] Pulling standard images..." -ForegroundColor Green
foreach ($img in $standardImages) {
    Write-Host "  Pulling $($img.Name)..." -NoNewline
    $result = docker pull $img.Name 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Red
        $ERRORS++
    }
}

Write-Host ""; Write-Host "[*] Building custom images..." -ForegroundColor Green
foreach ($img in $imageList) {
    Write-Host "  Building $($img.Name)..." -NoNewline
    $buildArgs = @("build", "-t", $img.Name, "-f", "$($img.Path)\Dockerfile", $img.Path)
    if ($Clean) { $buildArgs += "--no-cache" }
    $result = docker $buildArgs 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " FAILED" -ForegroundColor Red
        Write-Host "  $result" -ForegroundColor Red
        $ERRORS++
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($ERRORS -eq 0) {
    Write-Host "  ALL IMAGES BUILD SUCCESSFUL" -ForegroundColor Green
} else {
    Write-Host "  $ERRORS image(s) failed to build" -ForegroundColor Red
}
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[*] Next step: Import images into GNS3"
Write-Host "  1. Open GNS3 > Edit > Preferences > Docker"
Write-Host "  2. Add Docker template for each image above"
Write-Host "  3. Configure interface: 1 adapter, start command: /entrypoint.sh"
Write-Host "  4. See docs\gns3-import-guide.md for detailed instructions"
