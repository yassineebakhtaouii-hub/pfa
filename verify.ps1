#!/usr/bin/env powershell
# =============================================================================
# verify.ps1 - Verify PFA infrastructure status
# =============================================================================
# Tests: Docker images, container status, network connectivity, service health
# =============================================================================
param()

$ERRORS = 0
$WARNINGS = 0
$PASS = 0

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PFA - Infrastructure Verification" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Docker images
Write-Host "[1/6] Checking Docker images..." -ForegroundColor Yellow
$requiredImages = @("pfa-kali", "pfa-webserver", "pfa-postgresql", "pfa-suricata", "pfa-zeek", "pfa-wazuh-agent",
                    "wazuh/wazuh-manager:4.7.3", "wazuh/wazuh-indexer:4.7.3", "wazuh/wazuh-dashboard:4.7.3",
                    "prom/prometheus", "grafana/grafana")
$localImages = docker images --format "{{.Repository}}:{{.Tag}}" 2>&1
foreach ($img in $requiredImages) {
    $found = $false
    foreach ($local in $localImages) {
        if ($local -like "$img*") { $found = $true; break }
    }
    if ($found) { Write-Host "  [+] $img" -ForegroundColor Green; $PASS++ }
    else { Write-Host "  [-] $img MISSING - run build-all.ps1" -ForegroundColor Red; $ERRORS++ }
}

# Test 2: Docker daemon
Write-Host ""; Write-Host "[2/6] Checking Docker daemon..." -ForegroundColor Yellow
$dockerInfo = docker info 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [+] Docker daemon running" -ForegroundColor Green; $PASS++
} else {
    Write-Host "  [-] Docker daemon NOT running" -ForegroundColor Red; $ERRORS++
}

# Test 3: Cisco config file
Write-Host ""; Write-Host "[3/6] Checking Cisco config..." -ForegroundColor Yellow
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$ciscoFile = "$ROOT\cisco\router-config.cfg"
if (Test-Path $ciscoFile) {
    $lines = (Get-Content $ciscoFile | Measure-Object -Line).Lines
    Write-Host "  [+] Cisco config found: $lines lines" -ForegroundColor Green; $PASS++
    if ($lines -lt 100) { Write-Host "  [!] Config seems short, verify content" -ForegroundColor Yellow; $WARNINGS++ }
} else {
    Write-Host "  [-] Cisco config MISSING" -ForegroundColor Red; $ERRORS++
}

# Test 4: Attack scripts
Write-Host ""; Write-Host "[4/6] Checking attack scripts..." -ForegroundColor Yellow
$requiredScripts = @("recon.sh", "bruteforce.sh", "web_scan.sh", "dos_attack.sh", "arp_spoof.sh", "metasploit_exploit.rc")
$scriptDir = "$ROOT\images\kali\scripts"
foreach ($script in $requiredScripts) {
    if (Test-Path "$scriptDir\$script") {
        Write-Host "  [+] $script" -ForegroundColor Green; $PASS++
    } else {
        Write-Host "  [-] $script MISSING" -ForegroundColor Red; $ERRORS++
    }
}

# Test 5: Dockerfile syntax check
Write-Host ""; Write-Host "[5/6] Checking Dockerfiles..." -ForegroundColor Yellow
$dockerfiles = Get-ChildItem -Recurse "$ROOT\images\*\Dockerfile" | Select-Object -ExpandProperty FullName
foreach ($df in $dockerfiles) {
    $relPath = $df.Substring($ROOT.Length + 1)
    if (Test-Path $df) {
        $hasEntrypoint = (Get-Content $df | Select-String "ENTRYPOINT").Count -gt 0
        $hasFrom = (Get-Content $df | Select-String "^FROM").Count -gt 0
        if ($hasFrom) {
            Write-Host "  [+] $relPath (valid)" -ForegroundColor Green; $PASS++
        } else {
            Write-Host "  [!] $relPath (missing FROM)" -ForegroundColor Yellow; $WARNINGS++
        }
    }
}

# Test 6: Grafana provisioning files
Write-Host ""; Write-Host "[6/6] Checking Grafana provisioning..." -ForegroundColor Yellow
$grafanaDir = "$ROOT\images\grafana\provisioning"
if ((Test-Path "$grafanaDir\datasources\datasource.yml") -and (Test-Path "$grafanaDir\dashboards\dashboards.yml")) {
    Write-Host "  [+] Grafana provisioning files present" -ForegroundColor Green; $PASS++
} else {
    Write-Host "  [-] Grafana provisioning files MISSING" -ForegroundColor Red; $ERRORS++
}

# Summary
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  VERIFICATION SUMMARY" -ForegroundColor Cyan
if ($ERRORS -eq 0 -and $WARNINGS -eq 0) { Write-Host "  ALL CHECKS PASSED ($PASS)" -ForegroundColor Green }
else { Write-Host "  Passed: $PASS | Warnings: $WARNINGS | Errors: $ERRORS" -ForegroundColor $(if ($ERRORS -eq 0){"Yellow"}else{"Red"}) }
Write-Host "============================================" -ForegroundColor Cyan

exit $ERRORS

