# UpKeep Analytics - Main Entry Point
# Generates static HTML dashboard with PDF export capability

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = "." }

Import-Module "$ScriptDir\ApiClient.psm1" -Force
Import-Module "$ScriptDir\DataStore.psm1" -Force
Import-Module "$ScriptDir\DashboardGenerator.psm1" -Force

function Main {
    Write-Host "UpKeep Analytics - Starting..." -ForegroundColor Cyan

    $config = Get-Content "$ScriptDir\config.json" | ConvertFrom-Json

    if ($config.apiKey -eq "YOUR_API_KEY_HERE") {
        Write-Host "ERROR: Please edit config.json and add your UpKeep API key" -ForegroundColor Red
        exit 1
    }

    $outputDir = Join-Path $ScriptDir $config.outputDir
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    Write-Host "Authenticating with UpKeep API..." -ForegroundColor Yellow
    $session = Initialize-UpKeepSession -BaseUrl $config.baseUrl -ApiKey $config.apiKey

    if (-not $session) {
        Write-Host "ERROR: Failed to authenticate with UpKeep API" -ForegroundColor Red
        exit 1
    }
    Write-Host "Authentication successful!" -ForegroundColor Green

    $dataStorePath = Join-Path $ScriptDir "data"
    Initialize-DataStore -DataPath $dataStorePath

    $lookbackDate = (Get-Date).AddDays(-$config.lookbackDays)
    Write-Host "Fetching work orders since $($lookbackDate.ToString('yyyy-MM-dd'))..." -ForegroundColor Yellow

    $workOrders = Get-WorkOrders -Session $session -SinceDate $lookbackDate

    if ($workOrders.Count -eq 0) {
        Write-Host "No work orders found in the specified date range" -ForegroundColor Yellow
    } else {
        Write-Host "Retrieved $($workOrders.Count) work orders" -ForegroundColor Green
        Save-WorkOrders -DataPath $dataStorePath -WorkOrders $workOrders
    }

    Write-Host "Computing analytics..." -ForegroundColor Yellow
    $stats = Compute-Statistics -WorkOrders $workOrders -LookbackDays $config.lookbackDays

    Write-Host "Generating dashboard..." -ForegroundColor Yellow
    $htmlPath = Join-Path $outputDir "index.html"
    Generate-Dashboard -Stats $stats -OutputPath $htmlPath -LookbackDays $config.lookbackDays

    Write-Host ""
    Write-Host "Dashboard generated: $htmlPath" -ForegroundColor Green
    Write-Host "Open this file in your browser to view the analytics" -ForegroundColor Cyan
    Write-Host "Click 'Generate PDF Report' button to export to PDF" -ForegroundColor Cyan

    Export-Module -Force
}

Main