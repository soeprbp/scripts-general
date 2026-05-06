# Dashboard Generator Module

function Generate-Dashboard {
    param(
        [hashtable]$Stats,
        [string]$OutputPath,
        [int]$LookbackDays
    )

    $jsonStats = $Stats | ConvertTo-Json -Depth 10

    $dailyTrendJson = ($Stats.DailyTrend | ConvertTo-Json -Compress) -replace '"', '\"'
    $locationJson = ($Stats.LocationBreakdown | ConvertTo-Json -Compress) -replace '"', '\"'
    $monthlyYoyJson = ($Stats.MonthlyYoy | ConvertTo-Json -Compress) -replace '"', '\"'

    $monthlyYoyRows = ""
    foreach ($m in $Stats.MonthlyYoy) {
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
    foreach ($loc in $Stats.LocationBreakdown | Select-Object -First 10) {
        $locationRows += @"
            <tr>
                <td>$($loc.LocationName)</td>
                <td>$($loc.WorkOrders)</td>
                <td>$($loc.ActiveUsers)</td>
            </tr>
"@
    }

    $thisMonthGrowth = if ($Stats.LastMonthCount -gt 0) { [Math]::Round((($Stats.ThisMonthCount - $Stats.LastMonthCount) / $Stats.LastMonthCount) * 100, 1) } else { 0 }
    $yoyGrowth = if ($Stats.LastYearCount -gt 0) { [Math]::Round((($Stats.ThisYearCount - $Stats.LastYearCount) / $Stats.LastYearCount) * 100, 1) } else { 0 }

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
        <p class="subtitle">Last $LookbackDays days of activity</p>

        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-label">Total Work Orders</div>
                <div class="kpi-value">$($Stats.TotalWorkOrders)</div>
                <div class="kpi-sub">Last $LookbackDays days</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">This Month</div>
                <div class="kpi-value">$($Stats.ThisMonthCount)</div>
                <div class="kpi-sub">$($Stats.ThisMonthUsers) active users</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Month-over-Month</div>
                <div class="kpi-value $(if ($thisMonthGrowth -ge 0) { 'positive' } else { 'negative' })">$($thisMonthGrowth -ge 0 ? '+' : '')$thisMonthGrowth%</div>
                <div class="kpi-sub">vs last month ($($Stats.LastMonthCount))</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-label">Year-over-Year</div>
                <div class="kpi-value $(if ($yoyGrowth -ge 0) { 'positive' } else { 'negative' })">$($yoyGrowth -ge 0 ? '+' : '')$yoyGrowth%</div>
                <div class="kpi-sub">vs last year ($($Stats.LastYearCount))</div>
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
        const dailyData = JSON.parse("${dailyTrendJson}");
        const locationData = JSON.parse("${locationJson}");
        const monthlyYoyData = JSON.parse("${monthlyYoyJson}");

        const last30Days = dailyData.slice(-30);
        const dailyLabels = last30Days.map(d => d.Date);
        const dailyWO = last30Days.map(d => d.WorkOrders);
        const dailyUsers = last30Days.map(d => d.ActiveUsers);

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

        const locLabels = locationData.map(l => l.LocationName);
        const locWO = locationData.map(l => l.WorkOrders);

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
            const { jsPDF } = window.jspdf;
            const dashboard = document.getElementById('dashboard');

            document.querySelector('.btn').textContent = 'Generating PDF...';
            document.querySelector('.btn').disabled = true;

            try {
                const canvas = await html2canvas(dashboard, { scale: 2 });
                const imgData = canvas.toDataURL('image/png');

                const pdf = new jsPDF('p', 'mm', 'a4');
                const pdfWidth = pdf.internal.pageSize.getWidth();
                const pdfHeight = pdf.internal.pageSize.getHeight();
                const imgWidth = pdfWidth - 20;
                const imgHeight = (canvas.height * imgWidth) / canvas.width;

                let heightLeft = imgHeight;
                let position = 10;

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

    $html | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Dashboard written to $OutputPath" -ForegroundColor Green
}

Export-Module -Function Generate-Dashboard