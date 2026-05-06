# UpKeep Analytics - Single Script Version
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = "." }

Write-Host "UpKeep Analytics - Starting..." -ForegroundColor Cyan

$configPath = Join-Path $ScriptDir "config.json"
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: config.json not found" -ForegroundColor Red
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

if ($config.email -eq "your-email@example.com" -or $config.password -eq "your-password") {
    Write-Host "ERROR: Please edit config.json and add your UpKeep email and password" -ForegroundColor Red
    exit 1
}

Write-Host "Authenticating with UpKeep API..." -ForegroundColor Yellow

try {
    $authBody = @{
        email = $config.email
        password = $config.password
    } | ConvertTo-Json

    $authResponse = Invoke-RestMethod -Uri "$($config.baseUrl)/auth" -Method Post -ContentType "application/json" -Body $authBody -ErrorAction Stop

    if (-not $authResponse.success) {
        Write-Host "ERROR: Authentication failed - $($authResponse | ConvertTo-Json)" -ForegroundColor Red
        exit 1
    }

    $sessionToken = $authResponse.result.sessionToken

    if (-not $sessionToken) {
        Write-Host "ERROR: No session token received from authentication" -ForegroundColor Red
        exit 1
    }

    Write-Host "Authentication successful!" -ForegroundColor Green

    $headers = @{
        "Session-Token" = $sessionToken
    }
} catch {
    Write-Host "ERROR: Failed to authenticate - $_" -ForegroundColor Red
    exit 1
}

$dataDir = Join-Path $ScriptDir "data"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$outputDir = Join-Path $ScriptDir $config.outputDir
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$lastRunFile = Join-Path $dataDir "lastrun.json"
$existingDataFile = Join-Path $dataDir "workorders.json"

$existingWorkOrders = @()
if (Test-Path $existingDataFile) {
    $existingContent = Get-Content -Path $existingDataFile -Raw -ErrorAction SilentlyContinue
    if ($existingContent) {
        $existingWorkOrders = $existingContent | ConvertFrom-Json
        if ($existingWorkOrders -and $existingWorkOrders.Count -gt 0) {
            Write-Host "Loaded $($existingWorkOrders.Count) existing work orders from cache" -ForegroundColor Gray
        }
    }
}

$lastRunDate = $null
if (Test-Path $lastRunFile) {
    $lastRunContent = Get-Content -Path $lastRunFile -Raw -ErrorAction SilentlyContinue
    if ($lastRunContent) {
        $lastRunInfo = $lastRunContent | ConvertFrom-Json
        $lastRunDate = [datetime]::Parse($lastRunInfo.lastRun)
        Write-Host "Last run: $($lastRunDate.ToString('yyyy-MM-dd HH:mm')) - fetching only new records" -ForegroundColor Gray
    }
}

$lookbackDate = (Get-Date).AddDays(-$config.lookbackDays)
if ($lastRunDate -and $lastRunDate -gt $lookbackDate) {
    $lookbackDate = $lastRunDate
}
Write-Host "Fetching work orders since $($lookbackDate.ToString('yyyy-MM-dd'))..." -ForegroundColor Yellow

$allWorkOrders = @()
$offset = 0
$limit = 200
$keepFetching = $true

while ($keepFetching) {
    $url = "$($config.baseUrl)/work-orders?limit=$limit&offset=$offset"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop

        if ($response.success -and $response.results -and $response.results.Count -gt 0) {
            $pageWorkOrders = @()
            $hitOldData = $false

            foreach ($wo in $response.results) {
                $createdDate = [datetime]::Parse($wo.createdAt)

                if ($createdDate -lt $lookbackDate) {
                    $hitOldData = $true
                    break
                }

                $pageWorkOrders += $wo
            }

            $allWorkOrders += $pageWorkOrders
            Write-Host "Offset $offset : fetched $($pageWorkOrders.Count) (total: $($allWorkOrders.Count))" -ForegroundColor Gray

            if ($hitOldData -or $response.results.Count -lt $limit) {
                $keepFetching = $false
            } else {
                $offset += $limit
                Start-Sleep -Milliseconds 200
            }
        } else {
            $keepFetching = $false
        }
    } catch {
        Write-Host "Error fetching offset $offset : $_" -ForegroundColor Red
        $keepFetching = $false
    }
}

Write-Host "Retrieved $($allWorkOrders.Count) new work orders" -ForegroundColor Green

$existingIds = @{}
foreach ($wo in $existingWorkOrders) {
    if ($wo.id) { $existingIds[$wo.id] = $true }
}

$mergedWorkOrders = @($existingWorkOrders)
foreach ($wo in $allWorkOrders) {
    if (-not $existingIds.ContainsKey($wo.id)) {
        $mergedWorkOrders += $wo
    }
}

$totalWorkOrders = $mergedWorkOrders.Count
Write-Host "Total work orders (cached + new): $totalWorkOrders" -ForegroundColor Green

Write-Host "Fetching location details..." -ForegroundColor Yellow
$locationMap = @{}
$locOffset = 0
$locLimit = 200

while ($true) {
    $locUrl = "$($config.baseUrl)/locations?limit=$locLimit&offset=$locOffset"

    try {
        $locResponse = Invoke-RestMethod -Uri $locUrl -Method Get -Headers $headers -ErrorAction Stop

        if ($locResponse.success -and $locResponse.results -and $locResponse.results.Count -gt 0) {
            foreach ($loc in $locResponse.results) {
                $locationMap[$loc.id] = $loc.name
            }

            if ($locResponse.results.Count -lt $locLimit) {
                break
            }

            $locOffset += $locLimit
        } else {
            break
        }
    } catch {
        Write-Host "Error fetching locations: $_" -ForegroundColor Red
        break
    }
}

Write-Host "Found $($locationMap.Count) locations" -ForegroundColor Gray

$workOrdersFile = Join-Path $dataDir "workorders.json"
$mergedWorkOrders | ConvertTo-Json -Depth 10 | Set-Content -Path $workOrdersFile -Encoding UTF8
Write-Host "Saved to $workOrdersFile" -ForegroundColor Gray

$now = Get-Date
@{ lastRun = $now.ToString("o") } | ConvertTo-Json | Set-Content -Path $lastRunFile -Encoding UTF8
Write-Host "Updated last run timestamp" -ForegroundColor Gray

Write-Host "Computing analytics..." -ForegroundColor Yellow

$now = Get-Date
$oneYearAgo = $now.AddYears(-1)
$startOfThisMonth = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0
$startOfLastMonth = $startOfThisMonth.AddMonths(-1)

$dailyStats = @{}
$monthlyStats = @{}
$locationStats = @{}

foreach ($wo in $mergedWorkOrders) {
    $created = [datetime]::Parse($wo.createdAt)
    $dateKey = $created.ToString("yyyy-MM-dd")
    $monthKey = $created.ToString("yyyy-MM")
    $locationId = if ($wo.location) { $wo.location } else { "unknown" }
    $locationName = if ($locationMap.ContainsKey($locationId)) { $locationMap[$locationId] } else { $locationId }
    $userId = $wo.updatedBy
    if (-not $userId -and $wo.assignedToUser) { $userId = $wo.assignedToUser }

    if (-not $dailyStats.ContainsKey($dateKey)) {
        $dailyStats[$dateKey] = @{ Date = $dateKey; WorkOrders = 0; Users = @{} }
    }
    $dailyStats[$dateKey].WorkOrders++
    if ($userId) {
        $dailyStats[$dateKey].Users[$userId] = $true
    }

    if (-not $monthlyStats.ContainsKey($monthKey)) {
        $monthlyStats[$monthKey] = @{ Month = $monthKey; WorkOrders = 0; Users = @{} }
    }
    $monthlyStats[$monthKey].WorkOrders++
    if ($userId) {
        $monthlyStats[$monthKey].Users[$userId] = $true
    }

    if ($locationId -and -not $locationStats.ContainsKey($locationId)) {
        $locationStats[$locationId] = @{ LocationId = $locationId; LocationName = $locationName; WorkOrders = 0; Users = @{} }
    }
    if ($locationId) {
        $locationStats[$locationId].WorkOrders++
        $userId = $wo.updatedBy
        if (-not $userId -and $wo.assignedToUser) { $userId = $wo.assignedToUser }
        if ($userId) {
            $locationStats[$locationId].Users[$userId] = $true
        }
    }
}

$currentMonthKey = $now.ToString("yyyy-MM")
$lastMonthDate = $now.AddMonths(-1)
$lastMonthKey = $lastMonthDate.ToString("yyyy-MM")
$thisYearKey = $now.Year.ToString()
$lastYearKey = ($now.Year - 1).ToString()

$thisMonthCount = 0
$lastMonthCount = 0
$thisMonthUsers = 0
$lastMonthUsers = 0
$thisYearCount = 0
$lastYearCount = 0

foreach ($key in $monthlyStats.Keys) {
    $month = $monthlyStats[$key]

    if ($key -eq $currentMonthKey) {
        $thisMonthCount += $month.WorkOrders
        $thisMonthUsers = [Math]::Max($thisMonthUsers, $month.Users.Count)
    } elseif ($key -eq $lastMonthKey) {
        $lastMonthCount += $month.WorkOrders
        $lastMonthUsers = [Math]::Max($lastMonthUsers, $month.Users.Count)
    }

    if ($key.StartsWith("$thisYearKey-")) {
        $thisYearCount += $month.WorkOrders
    } elseif ($key.StartsWith("$lastYearKey-")) {
        $lastYearCount += $month.WorkOrders
    }
}

$monthlyYoy = @()
for ($i = 0; $i -lt 12; $i++) {
    $currentMonthDate = $now.AddMonths(-$i)
    $currentMonthKey = $currentMonthDate.ToString("yyyy-MM")
    $lastYearMonthDate = $currentMonthDate.AddYears(-1)
    $lastYearMonthKey = $lastYearMonthDate.ToString("yyyy-MM")

    $currentCount = if ($monthlyStats.ContainsKey($currentMonthKey)) { $monthlyStats[$currentMonthKey].WorkOrders } else { 0 }
    $lastYearCountVal = if ($monthlyStats.ContainsKey($lastYearMonthKey)) { $monthlyStats[$lastYearMonthKey].WorkOrders } else { 0 }
    $change = if ($lastYearCountVal -gt 0) { [Math]::Round((($currentCount - $lastYearCountVal) / $lastYearCountVal) * 100, 1) } else { 0 }

    $monthlyYoy += @{
        Month = $currentMonthKey
        MonthName = $currentMonthDate.ToString("MMM yyyy")
        CurrentYear = $currentCount
        LastYear = $lastYearCountVal
        ChangePercent = $change
    }
}
[array]::Reverse($monthlyYoy)

$dailyTrend = @()
foreach ($day in ($dailyStats.Keys | Sort-Object)) {
    $d = $dailyStats[$day]
    $dailyTrend += @{
        Date = $d.Date
        WorkOrders = $d.WorkOrders
        ActiveUsers = $d.Users.Count
    }
}

$locationTrend = @()
foreach ($loc in ($locationStats.Values | Sort-Object { $_.WorkOrders } -Descending)) {
    $locationTrend += @{
        LocationId = $loc.LocationId
        LocationName = $loc.LocationName
        WorkOrders = $loc.WorkOrders
        ActiveUsers = $loc.Users.Count
    }
}

$stats = @{
    TotalWorkOrders = $mergedWorkOrders.Count
    ThisMonthCount = $thisMonthCount
    LastMonthCount = $lastMonthCount
    ThisMonthUsers = $thisMonthUsers
    LastMonthUsers = $lastMonthUsers
    ThisYearCount = $thisYearCount
    LastYearCount = $lastYearCount
    MonthlyYoy = $monthlyYoy
    DailyTrend = $dailyTrend
    LocationBreakdown = $locationTrend
}

Write-Host "Generating dashboard..." -ForegroundColor Yellow

$dailyTrendJson = $stats.DailyTrend | ConvertTo-Json -Compress
$locationJson = $stats.LocationBreakdown | ConvertTo-Json -Compress
$monthlyYoyJson = $stats.MonthlyYoy | ConvertTo-Json -Compress

$monthlyYoyRows = ""
foreach ($m in $stats.MonthlyYoy) {
    $changeClass = if ($m.ChangePercent -ge 0) { "positive" } else { "negative" }
    $changeSign = if ($m.ChangePercent -ge 0) { "+" } else { "" }
    $monthlyYoyRows += @"
<tr>
    <td>$($m.MonthName)</td>
    <td>$($m.CurrentYear)</td>
    <td>$($m.LastYear)</td>
    <td class="$changeClass">$($changeSign)$($m.ChangePercent)%</td>
</tr>
"@
}

$locationRows = ""
foreach ($loc in $stats.LocationBreakdown | Select-Object -First 10) {
    $locationRows += @"
<tr>
    <td>$($loc.LocationName)</td>
    <td>$($loc.WorkOrders)</td>
    <td>$($loc.ActiveUsers)</td>
</tr>
"@
}

$thisMonthGrowth = if ($stats.LastMonthCount -gt 0) { [Math]::Round((($stats.ThisMonthCount - $stats.LastMonthCount) / $stats.LastMonthCount) * 100, 1) } else { 0 }
$yoyGrowth = if ($stats.LastYearCount -gt 0) { [Math]::Round((($stats.ThisYearCount - $stats.LastYearCount) / $stats.LastYearCount) * 100, 1) } else { 0 }

$htmlPath = Join-Path $outputDir "index.html"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UpKeep Analytics Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f7fa; color: #333; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #2c3e50; margin-bottom: 5px; }
        .subtitle { color: #7f8c8d; margin-bottom: 20px; }
        .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 25px; }
        .kpi-card { background: white; border-radius: 8px; padding: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .kpi-label { font-size: 14px; color: #7f8c8d; margin-bottom: 5px; }
        .kpi-value { font-size: 28px; font-weight: bold; color: #2c3e50; }
        .kpi-sub { font-size: 12px; color: #95a5a6; }
        .positive { color: #27ae60; }
        .negative { color: #e74c3c; }
        .section { background: white; border-radius: 8px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section h2 { margin-bottom: 15px; color: #2c3e50; font-size: 18px; }
        .chart-container { height: 300px; position: relative; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ecf0f1; }
        th { background: #f8f9fa; font-weight: 600; color: #2c3e50; }
        tr:hover { background: #f8f9fa; }
        .btn { background: #3498db; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; font-size: 16px; margin-top: 20px; }
        .btn:hover { background: #2980b9; }
        .footer { text-align: center; color: #95a5a6; margin-top: 20px; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container" id="dashboard">
        <h1>UpKeep Analytics</h1>
        <p class="subtitle">Last $($config.lookbackDays) days of activity</p>

        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-label">Total Work Orders</div>
                <div class="kpi-value">$($stats.TotalWorkOrders)</div>
                <div class="kpi-sub">Last $($config.lookbackDays) days</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">This Month</div>
                <div class="kpi-value">$($stats.ThisMonthCount)</div>
                <div class="kpi-sub">$($stats.ThisMonthUsers) active users</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Month-over-Month</div>
                <div class="kpi-value $(if ($thisMonthGrowth -ge 0) { 'positive' } else { 'negative' })">$($thisMonthGrowth -ge 0 ? '+' : '')$thisMonthGrowth%</div>
                <div class="kpi-sub">vs last month ($($stats.LastMonthCount))</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Year-over-Year</div>
                <div class="kpi-value $(if ($yoyGrowth -ge 0) { 'positive' } else { 'negative' })">$($yoyGrowth -ge 0 ? '+' : '')$yoyGrowth%</div>
                <div class="kpi-sub">vs last year ($($stats.LastYearCount))</div>
            </div>
        </div>

        <div class="section">
            <h2>Daily Work Orders (Last 30 Days)</h2>
            <div class="chart-container">
                <canvas id="dailyChart"></canvas>
            </div>
        </div>

        <div class="section">
            <h2>Work Orders by Location</h2>
            <div class="chart-container">
                <canvas id="locationChart"></canvas>
            </div>
        </div>

        <div class="section">
            <h2>Monthly Year-over-Year Comparison</h2>
            <table>
                <thead>
                    <tr>
                        <th>Month</th>
                        <th>Current Year</th>
                        <th>Last Year</th>
                        <th>Change</th>
                    </tr>
                </thead>
                <tbody>
                    $monthlyYoyRows
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2>Top Locations</h2>
            <table>
                <thead>
                    <tr>
                        <th>Location</th>
                        <th>Work Orders</th>
                        <th>Active Users</th>
                    </tr>
                </thead>
                <tbody>
                    $locationRows
                </tbody>
            </table>
        </div>

        <button class="btn" onclick="generatePDF()">Generate PDF Report</button>

        <div class="footer">
            Generated by UpKeep Analytics PowerShell Script
        </div>
    </div>

    <script>
        var dailyData = $dailyTrendJson;
        var locationData = $locationJson;
        var monthlyYoyData = $monthlyYoyJson;

        var last30Days = dailyData.slice(-30);
        var dailyLabels = last30Days.map(function(d) { return d.Date; });
        var dailyWO = last30Days.map(function(d) { return d.WorkOrders; });
        var dailyUsers = last30Days.map(function(d) { return d.ActiveUsers; });

        new Chart(document.getElementById('dailyChart'), {
            type: 'line',
            data: {
                labels: dailyLabels,
                datasets: [
                    {
                        label: 'Work Orders',
                        data: dailyWO,
                        borderColor: '#3498db',
                        backgroundColor: 'rgba(52, 152, 219, 0.1)',
                        fill: true,
                        tension: 0.3
                    },
                    {
                        label: 'Active Users',
                        data: dailyUsers,
                        borderColor: '#27ae60',
                        backgroundColor: 'rgba(39, 174, 96, 0.1)',
                        fill: true,
                        tension: 0.3,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                interaction: { mode: 'index', intersect: false },
                scales: {
                    y: { position: 'left', title: { display: true, text: 'Work Orders' } },
                    y1: { position: 'right', title: { display: true, text: 'Users' }, grid: { drawOnChartArea: false } }
                }
            }
        });

        var locLabels = locationData.map(function(l) { return l.LocationName; });
        var locWO = locationData.map(function(l) { return l.WorkOrders; });

        new Chart(document.getElementById('locationChart'), {
            type: 'bar',
            data: {
                labels: locLabels.slice(0, 10),
                datasets: [{
                    label: 'Work Orders',
                    data: locWO.slice(0, 10),
                    backgroundColor: '#9b59b6'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                indexAxis: 'y'
            }
        });

        async function generatePDF() {
            var _a = window.jspdf;
            var jsPDF = _a.jsPDF;
            var dashboard = document.getElementById('dashboard');

            document.querySelector('.btn').textContent = 'Generating PDF...';
            document.querySelector('.btn').disabled = true;

            try {
                var canvas = await html2canvas(dashboard, { scale: 2 });
                var imgData = canvas.toDataURL('image/png');

                var pdf = new jsPDF('p', 'mm', 'a4');
                var pdfWidth = pdf.internal.pageSize.getWidth();
                var pdfHeight = pdf.internal.pageSize.getHeight();
                var imgWidth = pdfWidth - 20;
                var imgHeight = (canvas.height * imgWidth) / canvas.width;

                var heightLeft = imgHeight;
                var position = 10;

                pdf.addImage(imgData, 'PNG', 10, position, imgWidth, imgHeight);
                heightLeft -= (pdfHeight - 20);

                while (heightLeft > 0) {
                    position = heightLeft - imgHeight + 10;
                    pdf.addPage();
                    pdf.addImage(imgData, 'PNG', 10, position, imgWidth, imgHeight);
                    heightLeft -= (pdfHeight - 20);
                }

                pdf.save('UpKeep_Analytics_Report.pdf');
            } catch (e) {
                alert('Error generating PDF: ' + e.message);
            }

            document.querySelector('.btn').textContent = 'Generate PDF Report';
            document.querySelector('.btn').disabled = false;
        }
    </script>
</body>
</html>
"@

$html | Set-Content -Path $htmlPath -Encoding UTF8

Write-Host ""
Write-Host "Dashboard generated: $htmlPath" -ForegroundColor Green
Write-Host "Open this file in your browser to view the analytics" -ForegroundColor Cyan
Write-Host "Click 'Generate PDF Report' button to export to PDF" -ForegroundColor Cyan