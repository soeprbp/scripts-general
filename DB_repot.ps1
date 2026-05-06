# ============================================================
# Welch Packaging – DPA Hourly Performance Report (DPA REST Only)
# DPA Server  : svwpapl03
# Target DB   : SVWPDBS04
# Output      : C:\Scripts\DPA\Reports\
# ============================================================

Import-Module CredentialManager

# ---- Configuration ----
$baseURL    = "https://svwpapl03:8124/iwc/api/"
$credTarget = "DPA-API-svwpapl03"
$targetDB   = "SVWPDBS04"
$hoursBack  = 24
$reportDir  = "C:\Scripts\DPA\Reports"
$reportPath = "$reportDir\SVWPDBS04_Hourly_$(Get-Date -Format 'yyyyMMdd_HHmm').html"

if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }

# ---- Load Token from Credential Manager ----
$cred = Get-StoredCredential -Target $credTarget
if (-not $cred) {
    Write-Host "❌ Credential '$credTarget' not found in Credential Manager." -ForegroundColor Red
    exit 1
}
$refreshToken = $cred.GetNetworkCredential().Password
Write-Host "✅ Token loaded from Credential Manager." -ForegroundColor Green

# ---- Self-Signed Cert Handler (PS 5.1) ----
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) { return true; }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol  = [System.Net.SecurityProtocolType]::Tls12
}

# ---- Helper Function ----
function Invoke-DPARequest {
    param([string]$Uri, [string]$Method = "GET", [hashtable]$Headers, [object]$Body = $null)
    $params = @{ Uri = $Uri; Method = $Method; Headers = $Headers }
    if ($Body) { $params.Body = $Body }
    if ($PSVersionTable.PSVersion.Major -ge 7) { $params.SkipCertificateCheck = $true }
    return Invoke-RestMethod @params
}

# ---- Step 1: Get Access Token ----
$authBody = @{ grant_type = "refresh_token"; refresh_token = $refreshToken }
$authResp  = Invoke-DPARequest -Uri ($baseURL + "security/oauth/token") -Method POST -Headers @{} -Body $authBody
$accessToken = $authResp.access_token
Write-Host "✅ Access token acquired." -ForegroundColor Green

$headers = @{ Authorization = "bearer $accessToken"; "Content-Type" = "application/json" }

# ---- Step 2: Get Database ID for SVWPDBS04 ----
Write-Host "🔍 Looking up database ID for $targetDB..." -ForegroundColor Cyan
$monitors = Invoke-DPARequest -Uri ($baseURL + "databases/monitor-information") -Headers $headers
$dbEntry  = $monitors | Where-Object { $_.databaseName -like "*$targetDB*" }

if (-not $dbEntry) {
    Write-Host "❌ '$targetDB' not found. Available instances:" -ForegroundColor Red
    $monitors | Select-Object databaseId, databaseName | Format-Table -AutoSize
    exit 1
}
$databaseId = $dbEntry.databaseId
Write-Host "✅ Found: $($dbEntry.databaseName) | ID: $databaseId" -ForegroundColor Green

# ---- Step 3: Build Hourly Time Buckets & Pull Wait Data ----
Write-Host "📊 Pulling hourly wait data..." -ForegroundColor Cyan

$endTime   = Get-Date
$startTime = $endTime.AddHours(-$hoursBack)
$hourlyData = @()

# Loop each hour and call DPA wait-time endpoint
for ($h = 0; $h -lt $hoursBack; $h++) {
    $slotStart = $startTime.AddHours($h)
    $slotEnd   = $slotStart.AddHours(1)

    $startStr = $slotStart.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
    $endStr   = $slotEnd.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")

    $url = $baseURL + "databases/$databaseId/wait-time/history" +
           "?startTime=$startStr&endTime=$endStr&intervalUnit=HOUR"

    try {
        $result    = Invoke-DPARequest -Uri $url -Headers $headers
        $waitTotal = ($result | Measure-Object -Property waitTime -Sum).Sum
        if (-not $waitTotal) { $waitTotal = 0 }
    } catch {
        $waitTotal = 0
    }

    $hourlyData += [PSCustomObject]@{
        Hour      = $slotStart.ToString("HH:mm")
        DateTime  = $slotStart.ToString("yyyy-MM-dd HH:mm")
        WaitSecs  = [Math]::Round($waitTotal, 2)
    }

    Write-Progress -Activity "Pulling DPA hourly data" `
                   -Status "Hour $($h+1) of $hoursBack — $($slotStart.ToString('HH:mm'))" `
                   -PercentComplete (($h / $hoursBack) * 100)
}

Write-Host "✅ Data collection complete." -ForegroundColor Green

# ---- Step 4: Calculate Summary Stats ----
$peakRow   = $hourlyData | Sort-Object WaitSecs | Select-Object -Last 1
$totalWait = [Math]::Round(($hourlyData | Measure-Object WaitSecs -Sum).Sum, 2)
$avgWait   = [Math]::Round(($hourlyData | Measure-Object WaitSecs -Average).Average, 2)
$peakWait  = $peakRow.WaitSecs
$peakHour  = $peakRow.Hour
$reportDate = Get-Date -Format "dddd, MMMM dd yyyy  HH:mm"

# ---- Step 5: Build Chart.js Data ----
$labels     = ($hourlyData | ForEach-Object { "`"$($_.Hour)`"" }) -join ","
$dataPoints = ($hourlyData | ForEach-Object { $_.WaitSecs }) -join ","

# ---- Step 6: Build Table Rows ----
$tableRows = ($hourlyData | ForEach-Object {
    $bar = if ($peakWait -gt 0) { [Math]::Min([Math]::Round(($_.WaitSecs / $peakWait) * 100), 100) } else { 0 }
    $rowClass = if ($_.WaitSecs -ge $peakWait * 0.85) { "style='background:#fff5f5'" }
                elseif ($_.WaitSecs -ge $peakWait * 0.60) { "style='background:#fffbf0'" }
                else { "" }
    "<tr $rowClass><td>$($_.DateTime)</td><td>${$_.WaitSecs}s</td><td><div class='bar-wrap'><div class='bar' style='width:${bar}%'></div></div></td></tr>"
}) -join "`n"

# ---- Step 7: Generate HTML ----
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>DPA Hourly Performance – $targetDB</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; color: #1a1a2e; }
  header { background: linear-gradient(135deg, #1b2a4a, #2e5fa3); color: white; padding: 24px 32px; }
  header h1 { font-size: 1.5rem; font-weight: 600; }
  header p  { font-size: 0.88rem; opacity: 0.8; margin-top: 6px; }
  .container { max-width: 1200px; margin: 24px auto; padding: 0 20px; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px,1fr)); gap: 16px; margin-bottom: 24px; }
  .card { background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); border-left: 4px solid #2e5fa3; }
  .card.peak { border-left-color: #e74c3c; }
  .card .label { font-size: 0.75rem; text-transform: uppercase; color: #888; letter-spacing: 0.5px; }
  .card .value { font-size: 1.9rem; font-weight: 700; color: #1b2a4a; margin-top: 6px; }
  .card.peak .value { color: #e74c3c; }
  .card .sub { font-size: 0.78rem; color: #aaa; margin-top: 4px; }
  .panel { background: white; border-radius: 10px; padding: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); margin-bottom: 24px; }
  .panel h2 { font-size: 0.95rem; color: #555; margin-bottom: 16px; font-weight: 600; }
  .chart-wrap { position: relative; height: 340px; }
  table { width: 100%; border-collapse: collapse; }
  thead { background: #1b2a4a; color: white; }
  th { padding: 11px 16px; text-align: left; font-size: 0.82rem; font-weight: 500; }
  td { padding: 9px 16px; font-size: 0.83rem; border-bottom: 1px solid #f0f0f0; }
  tr:last-child td { border-bottom: none; }
  .bar-wrap { background: #eef1f7; border-radius: 4px; height: 10px; min-width: 100px; }
  .bar { background: linear-gradient(90deg, #2e5fa3, #5b9bd5); border-radius: 4px; height: 10px; }
  footer { text-align: center; padding: 20px; color: #bbb; font-size: 0.76rem; }
</style>
</head>
<body>

<header>
  <h1>📊 DPA Hourly Performance Report — $targetDB</h1>
  <p>Generated: $reportDate &nbsp;|&nbsp; DPA Server: svwpapl03 &nbsp;|&nbsp; Last $hoursBack Hours</p>
</header>

<div class="container">

  <div class="cards">
    <div class="card">
      <div class="label">Total Wait Time</div>
      <div class="value">${totalWait}s</div>
      <div class="sub">Sum across $hoursBack hours</div>
    </div>
    <div class="card">
      <div class="label">Avg Wait / Hour</div>
      <div class="value">${avgWait}s</div>
      <div class="sub">Mean hourly wait</div>
    </div>
    <div class="card peak">
      <div class="label">Peak Hour</div>
      <div class="value">$peakHour</div>
      <div class="sub">${peakWait}s — highest wait</div>
    </div>
    <div class="card">
      <div class="label">Hours Sampled</div>
      <div class="value">$($hourlyData.Count)</div>
      <div class="sub">Hourly buckets</div>
    </div>
  </div>

  <div class="panel">
    <h2>⏱ Wait Time by Hour (seconds) — Blue: Normal &nbsp;|&nbsp; 🟡 Elevated &nbsp;|&nbsp; 🔴 Peak</h2>
    <div class="chart-wrap">
      <canvas id="perfChart"></canvas>
    </div>
  </div>

  <div class="panel">
    <h2>📋 Hourly Breakdown</h2>
    <table>
      <thead><tr><th>Date / Hour</th><th>Total Wait</th><th>Relative Load</th></tr></thead>
      <tbody>$tableRows</tbody>
    </table>
  </div>

</div>

<footer>Welch Packaging IT &nbsp;|&nbsp; SolarWinds DPA &nbsp;|&nbsp; $reportDate</footer>

<script>
const labels = [$labels];
const data   = [$dataPoints];
const peak   = Math.max(...data);

const colors = data.map(v => {
  if (v >= peak * 0.85) return 'rgba(231,76,60,0.85)';
  if (v >= peak * 0.60) return 'rgba(243,156,18,0.85)';
  return 'rgba(46,95,163,0.80)';
});
const borders = data.map(v => {
  if (v >= peak * 0.85) return 'rgb(192,57,43)';
  if (v >= peak * 0.60) return 'rgb(211,84,0)';
  return 'rgb(27,42,74)';
});

new Chart(document.getElementById('perfChart'), {
  type: 'bar',
  data: {
    labels,
    datasets: [{
      label: 'Wait Time (s)',
      data,
      backgroundColor: colors,
      borderColor: borders,
      borderWidth: 1,
      borderRadius: 5
    }]
  },
  options: {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: c => ' Wait: ' + c.parsed.y + 's' } }
    },
    scales: {
      x: { grid: { display: false }, ticks: { font: { size: 11 } } },
      y: {
        beginAtZero: true,
        title: { display: true, text: 'Wait Time (seconds)', font: { size: 11 } },
        grid: { color: 'rgba(0,0,0,0.05)' }
      }
    }
  }
});
</script>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n✅ Report saved to: $reportPath" -ForegroundColor Green
Start-Process $reportPath