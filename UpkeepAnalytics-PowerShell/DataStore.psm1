# Data Storage Module

function Initialize-DataStore {
    param([string]$DataPath)

    if (-not (Test-Path $DataPath)) {
        New-Item -ItemType Directory -Path $DataPath -Force | Out-Null
    }
}

function Save-WorkOrders {
    param(
        [string]$DataPath,
        [array]$WorkOrders
    )

    $workOrdersFile = Join-Path $DataPath "workorders.json"
    $WorkOrders | ConvertTo-Json -Depth 10 | Set-Content -Path $workOrdersFile -Encoding UTF8
    Write-Host "Saved $($WorkOrders.Count) work orders to $workOrdersFile" -ForegroundColor Gray
}

function Load-WorkOrders {
    param([string]$DataPath)

    $workOrdersFile = Join-Path $DataPath "workorders.json"
    if (Test-Path $workOrdersFile) {
        $content = Get-Content -Path $workOrdersFile -Raw
        return $content | ConvertFrom-Json
    }
    return @()
}

function Compute-Statistics {
    param(
        [array]$WorkOrders,
        [int]$LookbackDays
    )

    $now = Get-Date
    $oneYearAgo = $now.AddYears(-1)
    $twoYearsAgo = $now.AddYears(-2)
    $startOfThisMonth = Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0
    $startOfLastMonth = $startOfThisMonth.AddMonths(-1)

    $dailyStats = @{}
    $monthlyStats = @{}
    $locationStats = @{}

    foreach ($wo in $WorkOrders) {
        $created = [datetime]::Parse($wo.createdAt)
        $dateKey = $created.ToString("yyyy-MM-dd")
        $monthKey = $created.ToString("yyyy-MM")
        $locationId = $wo.location.id
        $locationName = $wo.location.name

        if (-not $dailyStats.ContainsKey($dateKey)) {
            $dailyStats[$dateKey] = @{
                Date = $dateKey
                WorkOrders = 0
                UniqueUsers = @{}
            }
        }
        $dailyStats[$dateKey].WorkOrders++

        if ($wo.createdBy -and $wo.createdBy.id) {
            $dailyStats[$dateKey].UniqueUsers[$wo.createdBy.id] = $true
        }

        $monthKey2 = $created.ToString("yyyy-MM")
        if (-not $monthlyStats.ContainsKey($monthKey2)) {
            $monthlyStats[$monthKey2] = @{
                Month = $monthKey2
                WorkOrders = 0
                ActiveUsers = @{}
            }
        }
        $monthlyStats[$monthKey2].WorkOrders++
        if ($wo.createdBy -and $wo.createdBy.id) {
            $monthlyStats[$monthKey2].ActiveUsers[$wo.createdBy.id] = $true
        }

        if ($locationId) {
            if (-not $locationStats.ContainsKey($locationId)) {
                $locationStats[$locationId] = @{
                    LocationId = $locationId
                    LocationName = $locationName
                    WorkOrders = 0
                    ActiveUsers = @{}
                }
            }
            $locationStats[$locationId].WorkOrders++
            if ($wo.createdBy -and $wo.createdBy.id) {
                $locationStats[$locationId].ActiveUsers[$wo.createdBy.id] = $true
            }
        }
    }

    $thisMonthCount = 0
    $lastMonthCount = 0
    $thisMonthUsers = 0
    $lastMonthUsers = 0
    $thisYearCount = 0
    $lastYearCount = 0

    foreach ($key in $monthlyStats.Keys) {
        $month = $monthlyStats[$key]
        $monthDate = [datetime]::Parse("$key-01")

        if ($monthDate -ge $startOfThisMonth) {
            $thisMonthCount += $month.WorkOrders
            $thisMonthUsers = [Math]::Max($thisMonthUsers, $month.ActiveUsers.Count)
        }
        elseif ($monthDate -ge $startOfLastMonth -and $monthDate -lt $startOfThisMonth) {
            $lastMonthCount += $month.WorkOrders
            $lastMonthUsers = [Math]::Max($lastMonthUsers, $month.ActiveUsers.Count)
        }

        if ($monthDate -ge (Get-Date -Year $now.Year -Month 1 -Day 1)) {
            $thisYearCount += $month.WorkOrders
        }
        elseif ($monthDate -ge (Get-Date -Year ($now.Year - 1) -Month 1 -Day 1) -and $monthDate -lt (Get-Date -Year $now.Year -Month 1 -Day 1)) {
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
        $lastYearCount = if ($monthlyStats.ContainsKey($lastYearMonthKey)) { $monthlyStats[$lastYearMonthKey].WorkOrders } else { 0 }
        $change = if ($lastYearCount -gt 0) { [Math]::Round((($currentCount - $lastYearCount) / $lastYearCount) * 100, 1) } else { 0 }

        $monthlyYoy += @{
            Month = $currentMonthKey
            MonthName = $currentMonthDate.ToString("MMM yyyy")
            CurrentYear = $currentCount
            LastYear = $lastYearCount
            ChangePercent = $change
        }
    }
    [array]::Reverse($monthlyYoy)

    $dailyTrend = @()
    $sortedDays = $dailyStats.Keys | Sort-Object
    foreach ($day in $sortedDays) {
        $d = $dailyStats[$day]
        $dailyTrend += @{
            Date = $d.Date
            WorkOrders = $d.WorkOrders
            ActiveUsers = $d.UniqueUsers.Count
        }
    }

    $locationTrend = @()
    foreach ($loc in $locationStats.Values | Sort-Object { $_.WorkOrders } -Descending) {
        $locationTrend += @{
            LocationId = $loc.LocationId
            LocationName = $loc.LocationName
            WorkOrders = $loc.WorkOrders
            ActiveUsers = $loc.ActiveUsers.Count
        }
    }

    return @{
        TotalWorkOrders = $WorkOrders.Count
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
}

Export-Module -Function Initialize-DataStore, Save-WorkOrders, Load-WorkOrders, Compute-Statistics