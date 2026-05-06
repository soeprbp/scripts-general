<#
.SYNOPSIS
  UpKeep Work Order Status Dashboard with Incremental Sync

.DESCRIPTION
  - Authenticates to UpKeep v2 API using environment variables
  - Fetches only work orders changed since the last successful sync
  - Stores local cache + sync state on disk
  - Builds an HTML dashboard from cached work orders
  - Auto-refreshes every 15 minutes

.REQUIREMENTS
  - PowerShell 5.1+ or PowerShell 7+
  - Environment variables:
      UPKEEP_EMAIL
      UPKEEP_PASSWORD
#>

# ===================== CONFIGURATION =====================

$OutputHtmlPath = "C:\UpKeepDashboard\UpKeep-WorkOrder-Dashboard.html"
$CacheDirectory = "C:\UpKeepDashboard"
$CacheFilePath  = Join-Path $CacheDirectory "UpKeep-WorkOrders-Cache.json"
$StateFilePath  = Join-Path $CacheDirectory "UpKeep-WorkOrders-State.json"

# Auto-refresh every 15 minutes
$RefreshIntervalSeconds = 900

# UpKeep API version
$UpKeepApiVersion = "2022-09-14"

# API paging
$PageSize = 200

# Incremental sync settings
$ForceFullSync = $false
$InitialLookbackDays = 90
$SyncOverlapMinutes = 10

# Optional cache cleanup:
# Completed / Closed work orders older than this many days can be removed from cache.
# Set to 0 to disable cleanup.
$PurgeCompletedAfterDays = 180

# Status grouping for dashboard
$StatusConfig = @(
    @{ Name = "Open";        StatusValues = @("Open") }
    @{ Name = "In Progress"; StatusValues = @("In-Progress", "In Progress") }
    @{ Name = "On Hold";     StatusValues = @("On Hold", "On-Hold") }
    @{ Name = "Complete";    StatusValues = @("Complete", "Closed") }
)

# API endpoints
$UpKeepBaseUrlV2    = [string]"https://api.onupkeep.com/api/v2"
$AuthEndpoint       = [string]::Format("{0}/auth", $UpKeepBaseUrlV2)
$WorkOrdersEndpoint = [string]::Format("{0}/work-orders", $UpKeepBaseUrlV2)

# ===================== HELPER FUNCTIONS =====================

function Ensure-DirectoryExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-RequiredEnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $value = [Environment]::GetEnvironmentVariable($Name)

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable '$Name' is not set."
    }

    return $value
}

function ConvertTo-UnixMilliseconds {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$DateTimeValue
    )

    $dto = [DateTimeOffset]::new($DateTimeValue.ToUniversalTime())
    return $dto.ToUnixTimeMilliseconds()
}

function Get-SafeDateTimeForSort {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return [datetime]::MinValue
    }

    try {
        if ($Value -is [long] -or $Value -is [int] -or $Value -is [double] -or $Value -is [decimal]) {
            return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Value).UtcDateTime
        }
    }
    catch {}

    try {
        $stringValue = [string]$Value
        if ($stringValue -match '^\d{13}$') {
            return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$stringValue).UtcDateTime
        }
    }
    catch {}

    try {
        return [datetime]$Value
    }
    catch {
        return [datetime]::MinValue
    }
}

function Get-UpKeepSessionToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email,

        [Parameter(Mandatory = $true)]
        [string]$Password
    )

    $body = @{
        email    = $Email
        password = $Password
    }

    $headers = @{
        "Accept"         = "application/json"
        "upkeep-version" = $UpKeepApiVersion
    }

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $AuthEndpoint `
            -Headers $headers `
            -Body $body `
            -ContentType "application/x-www-form-urlencoded"

        if (-not $response) {
            throw "Authentication returned no response."
        }

        if ($response.success -ne $true) {
            $json = $response | ConvertTo-Json -Depth 10 -Compress
            throw "Authentication failed. Response: $json"
        }

        if (-not $response.result -or [string]::IsNullOrWhiteSpace($response.result.sessionToken)) {
            $json = $response | ConvertTo-Json -Depth 10 -Compress
            throw "Authentication succeeded but no session token was returned. Response: $json"
        }

        return $response.result.sessionToken
    }
    catch {
        throw "Error obtaining UpKeep session token: $($_.Exception.Message)"
    }
}

function Load-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Object,

        [int]$Depth = 20
    )

    $json = $Object | ConvertTo-Json -Depth $Depth
    $json | Out-File -LiteralPath $Path -Encoding UTF8 -Force
}

function Load-CacheTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $table = @{}
    $data = Load-JsonFile -Path $Path

    if ($null -eq $data) {
        return $table
    }

    foreach ($item in @($data)) {
        if ($null -eq $item) {
            continue
        }

        $id = [string]$item.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            continue
        }

        $table[$id] = $item
    }

    return $table
}

function Save-CacheTable {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheTable,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $items = @($CacheTable.Values | Sort-Object {
        Get-SafeDateTimeForSort -Value $_.updatedAt
    } -Descending)

    Save-JsonFile -Path $Path -Object $items -Depth 30
}

function Load-SyncState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $state = Load-JsonFile -Path $Path
    if ($null -eq $state) {
        return [PSCustomObject]@{
            lastSuccessfulSyncUtc = $null
        }
    }

    if (-not ($state.PSObject.Properties.Name -contains "lastSuccessfulSyncUtc")) {
        $state | Add-Member -NotePropertyName "lastSuccessfulSyncUtc" -NotePropertyValue $null
    }

    return $state
}

function Save-SyncState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [datetime]$LastSuccessfulSyncUtc
    )

    $state = [PSCustomObject]@{
        lastSuccessfulSyncUtc = $LastSuccessfulSyncUtc.ToUniversalTime().ToString("o")
    }

    Save-JsonFile -Path $Path -Object $state -Depth 5
}

function Get-IncrementalSyncWindow {
    param(
        [Parameter(Mandatory = $true)]
        $State,

        [bool]$ForceFullSync = $false,

        [int]$InitialLookbackDays = 90,

        [int]$SyncOverlapMinutes = 10
    )

    $window = [ordered]@{
        UseUpdatedFilter = $true
        StartUtc         = $null
        EndUtc           = (Get-Date).ToUniversalTime()
        Mode             = ""
    }

    if ($ForceFullSync) {
        $window.UseUpdatedFilter = $false
        $window.Mode = "FullSync"
        return [PSCustomObject]$window
    }

    if ($null -ne $State -and -not [string]::IsNullOrWhiteSpace([string]$State.lastSuccessfulSyncUtc)) {
        try {
            $lastSync = [datetime]::Parse([string]$State.lastSuccessfulSyncUtc).ToUniversalTime()
            $window.StartUtc = $lastSync.AddMinutes(-1 * [math]::Abs($SyncOverlapMinutes))
            $window.Mode = "Incremental"
            return [PSCustomObject]$window
        }
        catch {
        }
    }

    $window.StartUtc = (Get-Date).ToUniversalTime().AddDays(-1 * [math]::Abs($InitialLookbackDays))
    $window.Mode = "BootstrapLookback"
    return [PSCustomObject]$window
}

function Invoke-UpKeepGetPaged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $true)]
        [string]$SessionToken,

        [Parameter(Mandatory = $true)]
        [hashtable]$QueryParameters,

        [int]$PageSize = 200
    )

    $allResults = @()
    $offset = 0

    $headers = @{
        "Accept"         = "application/json"
        "Session-Token"  = $SessionToken
        "upkeep-version" = $UpKeepApiVersion
    }

    while ($true) {
        try {
            $builder = New-Object System.UriBuilder([System.Uri]$Endpoint)

            $pairs = @()
            foreach ($key in $QueryParameters.Keys) {
                $value = $QueryParameters[$key]
                if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                    $pairs += ("{0}={1}" -f [uri]::EscapeDataString([string]$key), [uri]::EscapeDataString([string]$value))
                }
            }

            $pairs += "limit=$PageSize"
            $pairs += "offset=$offset"

            $builder.Query = ($pairs -join "&")
            $uri = $builder.Uri.AbsoluteUri
        }
        catch {
            throw "Failed to build URI from '$Endpoint'. Error: $($_.Exception.Message)"
        }

        Write-Host "Requesting: $uri" -ForegroundColor DarkCyan

        try {
            $response = Invoke-RestMethod `
                -Method Get `
                -Uri $uri `
                -Headers $headers
        }
        catch {
            throw "Error retrieving data at offset ${offset}: $($_.Exception.Message)"
        }

        if (-not $response) {
            throw "API returned no response at offset ${offset}."
        }

        if ($response.success -ne $true) {
            $json = $response | ConvertTo-Json -Depth 15 -Compress
            throw "API returned unsuccessful response at offset ${offset}. Response: $json"
        }

        $results = @()
        if ($null -ne $response.results) {
            $results = @($response.results)
        }

        if ($results.Count -eq 0) {
            break
        }

        $allResults += $results

        if ($results.Count -lt $PageSize) {
            break
        }

        $offset += $PageSize
    }

    return @($allResults)
}

function Get-UpKeepWorkOrdersIncremental {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionToken,

        [Parameter(Mandatory = $true)]
        $SyncWindow,

        [int]$PageSize = 200
    )

    $query = @{
        orderBy = "updatedAt ASC"
    }

    if ($SyncWindow.UseUpdatedFilter -and $null -ne $SyncWindow.StartUtc) {
        $query["updatedAtGreaterThanOrEqualTo"] = [string](ConvertTo-UnixMilliseconds -DateTimeValue $SyncWindow.StartUtc)
        $query["updatedAtLessThanOrEqualTo"]    = [string](ConvertTo-UnixMilliseconds -DateTimeValue $SyncWindow.EndUtc)
    }

    return Invoke-UpKeepGetPaged `
        -Endpoint $WorkOrdersEndpoint `
        -SessionToken $SessionToken `
        -QueryParameters $query `
        -PageSize $PageSize
}

function Merge-WorkOrdersIntoCache {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheTable,

        [Parameter(Mandatory = $true)]
        [array]$IncomingWorkOrders
    )

    $updatedCount = 0

    foreach ($wo in @($IncomingWorkOrders)) {
        if ($null -eq $wo) {
            continue
        }

        $id = [string]$wo.id
        if ([string]::IsNullOrWhiteSpace($id)) {
            continue
        }

        $CacheTable[$id] = $wo
        $updatedCount++
    }

    return $updatedCount
}

function Normalize-StatusValue {
    param(
        [AllowNull()]
        [string]$Status
    )

    if ([string]::IsNullOrWhiteSpace($Status)) {
        return ""
    }

    $normalized = $Status.Trim().ToLowerInvariant()
    $normalized = $normalized -replace '[_\s]+', '-'
    return $normalized
}

function Get-WorkOrderStatusSummary {
    param(
        [Parameter(Mandatory = $true)]
        [array]$WorkOrders,

        [Parameter(Mandatory = $true)]
        [array]$StatusConfig
    )

    $normalizedWorkOrders = @()
    foreach ($wo in @($WorkOrders)) {
        $normalizedWorkOrders += [PSCustomObject]@{
            RawStatus        = [string]$wo.status
            NormalizedStatus = Normalize-StatusValue -Status ([string]$wo.status)
        }
    }

    $summary = @()
    $matchedIndexes = @{}

    for ($i = 0; $i -lt $StatusConfig.Count; $i++) {
        $group = $StatusConfig[$i]
        $name = [string]$group.Name
        $statusValues = @($group.StatusValues)
        $normalizedTargets = @($statusValues | ForEach-Object { Normalize-StatusValue -Status ([string]$_) })

        $count = 0

        for ($j = 0; $j -lt $normalizedWorkOrders.Count; $j++) {
            if ($normalizedTargets -contains $normalizedWorkOrders[$j].NormalizedStatus) {
                $count++
                $matchedIndexes[$j] = $true
            }
        }

        $summary += [PSCustomObject]@{
            Name         = $name
            Count        = $count
            StatusValues = ($statusValues -join ", ")
        }
    }

    $otherStatuses = @()
    for ($j = 0; $j -lt $normalizedWorkOrders.Count; $j++) {
        if (-not $matchedIndexes.ContainsKey($j)) {
            $otherStatuses += $normalizedWorkOrders[$j].RawStatus
        }
    }

    $otherDistinct = @(
        $otherStatuses |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )

    $otherLabel = if ($otherDistinct.Count -gt 0) { $otherDistinct -join ", " } else { "None" }

    $summary += [PSCustomObject]@{
        Name         = "Other"
        Count        = $otherStatuses.Count
        StatusValues = $otherLabel
    }

    $summary += [PSCustomObject]@{
        Name         = "Total"
        Count        = $normalizedWorkOrders.Count
        StatusValues = "All"
    }

    return @($summary)
}

function Get-StatusCount {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $item = $Summary | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($null -eq $item) {
        return 0
    }

    try {
        return [int]$item.Count
    }
    catch {
        return 0
    }
}

function Get-WorkOrderAgeDays {
    param(
        [Parameter(Mandatory = $true)]
        $WorkOrder
    )

    $candidateFields = @(
        "createdAt",
        "requestDate",
        "date",
        "dueDate"
    )

    foreach ($field in $candidateFields) {
        if ($WorkOrder.PSObject.Properties.Name -contains $field) {
            $dt = Get-SafeDateTimeForSort -Value $WorkOrder.$field
            if ($dt -ne [datetime]::MinValue) {
                return [int][math]::Floor(((Get-Date).ToUniversalTime() - $dt.ToUniversalTime()).TotalDays)
            }
        }
    }

    return 0
}

function Get-OpenAgingSummary {
    param(
        [Parameter(Mandatory = $true)]
        [array]$WorkOrders
    )

    $olderThan7 = 0
    $olderThan14 = 0
    $olderThan30 = 0

    foreach ($wo in @($WorkOrders)) {
        $status = Normalize-StatusValue -Status ([string]$wo.status)

        if ($status -notin @("open", "in-progress", "on-hold")) {
            continue
        }

        $ageDays = Get-WorkOrderAgeDays -WorkOrder $wo

        if ($ageDays -gt 7)  { $olderThan7++ }
        if ($ageDays -gt 14) { $olderThan14++ }
        if ($ageDays -gt 30) { $olderThan30++ }
    }

    return [PSCustomObject]@{
        OlderThan7  = $olderThan7
        OlderThan14 = $olderThan14
        OlderThan30 = $olderThan30
    }
}

function Get-FieldValueIfExists {
    param(
        [Parameter(Mandatory = $true)]
        $Object,

        [Parameter(Mandatory = $true)]
        [string[]]$FieldNames
    )

    foreach ($field in $FieldNames) {
        if ($Object.PSObject.Properties.Name -contains $field) {
            $value = $Object.$field
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return "Unspecified"
}

function Get-PrioritySummary {
    param(
        [Parameter(Mandatory = $true)]
        [array]$WorkOrders
    )

    $counts = @{}

    foreach ($wo in @($WorkOrders)) {
        $priority = Get-FieldValueIfExists -Object $wo -FieldNames @("priority", "priorityName", "workOrderPriority", "priorityLabel")
        if (-not $counts.ContainsKey($priority)) {
            $counts[$priority] = 0
        }
        $counts[$priority]++
    }

    $result = @()
    foreach ($key in $counts.Keys) {
        $result += [PSCustomObject]@{
            Name  = $key
            Count = [int]$counts[$key]
        }
    }

    return @(
        $result | Sort-Object `
            @{ Expression = { $_.Count }; Descending = $true }, `
            @{ Expression = { $_.Name  }; Descending = $false }
    )
}

function Remove-OldCompletedFromCache {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$CacheTable,

        [Parameter(Mandatory = $true)]
        [int]$PurgeCompletedAfterDays
    )

    if ($PurgeCompletedAfterDays -le 0) {
        return 0
    }

    $removedCount = 0
    $cutoffUtc = (Get-Date).ToUniversalTime().AddDays(-1 * $PurgeCompletedAfterDays)
    $keysToRemove = @()

    foreach ($key in @($CacheTable.Keys)) {
        $wo = $CacheTable[$key]
        if ($null -eq $wo) {
            continue
        }

        $status = Normalize-StatusValue -Status ([string]$wo.status)
        $isComplete = ($status -eq "complete" -or $status -eq "closed")

        if (-not $isComplete) {
            continue
        }

        $updatedAtUtc = Get-SafeDateTimeForSort -Value $wo.updatedAt
        if ($updatedAtUtc -lt $cutoffUtc) {
            $keysToRemove += $key
        }
    }

    foreach ($key in $keysToRemove) {
        $CacheTable.Remove($key)
        $removedCount++
    }

    return $removedCount
}

function ConvertTo-HtmlEncoded {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ""
    }

    try {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        return [System.Web.HttpUtility]::HtmlEncode($Text)
    }
    catch {
        return [string]$Text
    }
}

function New-WorkOrderDashboardHtml {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Summary,

        [Parameter(Mandatory = $true)]
        [array]$PrioritySummary,

        [Parameter(Mandatory = $true)]
        $AgingSummary,

        [Parameter(Mandatory = $true)]
        [datetime]$GeneratedAt,

        [Parameter(Mandatory = $true)]
        [datetime]$NextRefreshTime
    )

    $openCount       = Get-StatusCount -Summary $Summary -Name "Open"
    $inProgressCount = Get-StatusCount -Summary $Summary -Name "In Progress"
    $onHoldCount     = Get-StatusCount -Summary $Summary -Name "On Hold"
    $completeCount   = Get-StatusCount -Summary $Summary -Name "Complete"
    $otherCount      = Get-StatusCount -Summary $Summary -Name "Other"
    $totalCount      = Get-StatusCount -Summary $Summary -Name "Total"

    $statusRows = foreach ($item in @($Summary | Where-Object { $_.Name -ne "Total" })) {
        $name = ConvertTo-HtmlEncoded -Text $item.Name
        $count = ConvertTo-HtmlEncoded -Text ([string]$item.Count)
        $statuses = ConvertTo-HtmlEncoded -Text $item.StatusValues

        $rowClass = switch ($item.Name) {
            "Open"        { "status-open" }
            "In Progress" { "status-progress" }
            "On Hold"     { "status-hold" }
            "Complete"    { "status-complete" }
            "Other"       { "status-other" }
            default       { "" }
        }

@"
<tr class="$rowClass">
    <td class="status-name">$name</td>
    <td class="status-count">$count</td>
    <td class="status-values">$statuses</td>
</tr>
"@
    }

    $priorityRows = foreach ($item in @($PrioritySummary)) {
        $name = ConvertTo-HtmlEncoded -Text $item.Name
        $count = [int]$item.Count
        $width = 0
        if ($totalCount -gt 0) {
            $width = [math]::Round(($count / $totalCount) * 100, 1)
        }

@"
<div class="priority-row">
    <div class="priority-top">
        <span class="priority-name">$name</span>
        <span class="priority-count">$count</span>
    </div>
    <div class="priority-bar-track">
        <div class="priority-bar-fill" style="width: $width%;"></div>
    </div>
</div>
"@
    }

    $rowsHtml = ($statusRows -join [Environment]::NewLine)
    $priorityHtml = ($priorityRows -join [Environment]::NewLine)

    $chartDataJs = @"
[
  { label: 'Open', value: $openCount, color: '#2563eb' },
  { label: 'In Progress', value: $inProgressCount, color: '#7c3aed' },
  { label: 'On Hold', value: $onHoldCount, color: '#d97706' },
  { label: 'Complete', value: $completeCount, color: '#059669' },
  { label: 'Other', value: $otherCount, color: '#64748b' }
]
"@

    $barMax = [math]::Max([math]::Max([math]::Max([math]::Max($openCount, $inProgressCount), $onHoldCount), $completeCount), [math]::Max($otherCount, 1))
    $barOpenPct = [math]::Round(($openCount / $barMax) * 100, 1)
    $barProgressPct = [math]::Round(($inProgressCount / $barMax) * 100, 1)
    $barHoldPct = [math]::Round(($onHoldCount / $barMax) * 100, 1)
    $barCompletePct = [math]::Round(($completeCount / $barMax) * 100, 1)
    $barOtherPct = [math]::Round(($otherCount / $barMax) * 100, 1)

    $generatedAtText = ConvertTo-HtmlEncoded -Text ($GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss"))
    $nextRefreshText = ConvertTo-HtmlEncoded -Text ($NextRefreshTime.ToString("yyyy-MM-dd HH:mm:ss"))

    $openText        = ConvertTo-HtmlEncoded -Text ([string]$openCount)
    $progressText    = ConvertTo-HtmlEncoded -Text ([string]$inProgressCount)
    $holdText        = ConvertTo-HtmlEncoded -Text ([string]$onHoldCount)
    $completeText    = ConvertTo-HtmlEncoded -Text ([string]$completeCount)
    $otherText       = ConvertTo-HtmlEncoded -Text ([string]$otherCount)
    $totalText       = ConvertTo-HtmlEncoded -Text ([string]$totalCount)

    $age7Text        = ConvertTo-HtmlEncoded -Text ([string]$AgingSummary.OlderThan7)
    $age14Text       = ConvertTo-HtmlEncoded -Text ([string]$AgingSummary.OlderThan14)
    $age30Text       = ConvertTo-HtmlEncoded -Text ([string]$AgingSummary.OlderThan30)

    $activeCount = [int]($openCount + $inProgressCount + $onHoldCount)
    $activePct = [math]::Round(($activeCount / [math]::Max($totalCount, 1)) * 100, 1)
    $completePct = [math]::Round(($completeCount / [math]::Max($totalCount, 1)) * 100, 1)

    $css = @"
:root {
    --bg: #f4f7fb;
    --panel: #ffffff;
    --text: #1f2937;
    --muted: #6b7280;
    --border: #e5e7eb;
    --shadow: 0 10px 30px rgba(15, 23, 42, 0.08);
    --blue: #2563eb;
    --purple: #7c3aed;
    --amber: #d97706;
    --green: #059669;
    --slate: #64748b;
    --ink: #111827;
}

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    padding: 24px;
    font-family: "Segoe UI", Arial, sans-serif;
    background: linear-gradient(180deg, #f8fbff 0%, var(--bg) 100%);
    color: var(--text);
}

.container {
    max-width: 1440px;
    margin: 0 auto;
}

.header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 20px;
    margin-bottom: 24px;
    flex-wrap: wrap;
}

.header-left h1 {
    margin: 0 0 8px 0;
    font-size: 34px;
    font-weight: 700;
    letter-spacing: -0.02em;
}

.header-left p {
    margin: 0;
    color: var(--muted);
    font-size: 14px;
}

.header-right {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 18px;
    box-shadow: var(--shadow);
    padding: 16px 18px;
    min-width: 280px;
}

.header-right .label {
    display: block;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    margin-bottom: 4px;
}

.header-right .value {
    font-size: 14px;
    font-weight: 600;
    color: var(--text);
    margin-bottom: 10px;
}

.kpi-grid {
    display: grid;
    grid-template-columns: repeat(6, minmax(140px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
}

.kpi-card {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 20px;
    box-shadow: var(--shadow);
    padding: 18px;
}

.kpi-card .kpi-label {
    font-size: 13px;
    color: var(--muted);
    margin-bottom: 10px;
}

.kpi-card .kpi-value {
    font-size: 30px;
    font-weight: 700;
    line-height: 1;
}

.kpi-open { border-top: 5px solid var(--blue); }
.kpi-open .kpi-value { color: var(--blue); }

.kpi-progress { border-top: 5px solid var(--purple); }
.kpi-progress .kpi-value { color: var(--purple); }

.kpi-hold { border-top: 5px solid var(--amber); }
.kpi-hold .kpi-value { color: var(--amber); }

.kpi-complete { border-top: 5px solid var(--green); }
.kpi-complete .kpi-value { color: var(--green); }

.kpi-other { border-top: 5px solid var(--slate); }
.kpi-other .kpi-value { color: var(--slate); }

.kpi-total { border-top: 5px solid var(--ink); }
.kpi-total .kpi-value { color: var(--ink); }

.aging-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(180px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
}

.aging-card {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 20px;
    box-shadow: var(--shadow);
    padding: 18px;
}

.aging-label {
    font-size: 13px;
    color: var(--muted);
    margin-bottom: 10px;
}

.aging-value {
    font-size: 30px;
    font-weight: 700;
    line-height: 1;
    color: var(--ink);
}

.main-grid {
    display: grid;
    grid-template-columns: 1.25fr 1.25fr 1fr;
    gap: 20px;
    margin-bottom: 20px;
}

.bottom-grid {
    display: grid;
    grid-template-columns: 1.2fr 1fr;
    gap: 20px;
}

.panel {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 22px;
    box-shadow: var(--shadow);
    overflow: hidden;
}

.panel-header {
    padding: 18px 20px;
    border-bottom: 1px solid var(--border);
}

.panel-title {
    margin: 0;
    font-size: 18px;
    font-weight: 700;
}

.panel-subtitle {
    margin: 6px 0 0 0;
    color: var(--muted);
    font-size: 13px;
}

.panel-body {
    padding: 20px;
}

.chart-wrap {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 320px;
}

.donut-container {
    display: flex;
    align-items: center;
    gap: 24px;
    flex-wrap: wrap;
    justify-content: center;
}

.donut-svg {
    width: 220px;
    height: 220px;
    overflow: visible;
}

.donut-center-text {
    font-size: 28px;
    font-weight: 700;
    fill: var(--ink);
    text-anchor: middle;
    dominant-baseline: middle;
}

.donut-center-sub {
    font-size: 12px;
    fill: var(--muted);
    text-anchor: middle;
}

.legend {
    display: grid;
    gap: 10px;
    min-width: 180px;
}

.legend-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    font-size: 14px;
}

.legend-left {
    display: flex;
    align-items: center;
    gap: 10px;
}

.legend-swatch {
    width: 12px;
    height: 12px;
    border-radius: 999px;
}

.legend-value {
    font-weight: 700;
}

.bar-chart {
    display: grid;
    gap: 14px;
}

.bar-row {
    display: grid;
    gap: 6px;
}

.bar-top {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: 14px;
}

.bar-label {
    font-weight: 600;
}

.bar-value {
    font-weight: 700;
}

.bar-track {
    height: 16px;
    width: 100%;
    background: #edf2f7;
    border-radius: 999px;
    overflow: hidden;
}

.bar-fill {
    height: 100%;
    border-radius: 999px;
}

.fill-open { background: var(--blue); }
.fill-progress { background: var(--purple); }
.fill-hold { background: var(--amber); }
.fill-complete { background: var(--green); }
.fill-other { background: var(--slate); }

.status-table {
    width: 100%;
    border-collapse: collapse;
}

.status-table thead th {
    text-align: left;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    padding: 0 0 14px 0;
    border-bottom: 1px solid var(--border);
}

.status-table tbody td {
    padding: 16px 0;
    border-bottom: 1px solid #f1f5f9;
    vertical-align: top;
}

.status-table tbody tr:last-child td {
    border-bottom: none;
}

.status-name {
    font-weight: 600;
}

.status-count {
    font-weight: 700;
    font-size: 18px;
}

.status-values {
    color: var(--muted);
    font-size: 13px;
    line-height: 1.5;
    padding-left: 12px !important;
}

.status-open .status-count { color: var(--blue); }
.status-progress .status-count { color: var(--purple); }
.status-hold .status-count { color: var(--amber); }
.status-complete .status-count { color: var(--green); }
.status-other .status-count { color: var(--slate); }

.priority-list {
    display: grid;
    gap: 14px;
}

.priority-row {
    display: grid;
    gap: 8px;
}

.priority-top {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    font-size: 14px;
}

.priority-name {
    font-weight: 600;
}

.priority-count {
    font-weight: 700;
}

.priority-bar-track {
    width: 100%;
    height: 14px;
    border-radius: 999px;
    background: #edf2f7;
    overflow: hidden;
}

.priority-bar-fill {
    height: 100%;
    border-radius: 999px;
    background: linear-gradient(90deg, var(--blue), var(--purple));
}

.footer-note {
    margin-top: 20px;
    color: var(--muted);
    font-size: 12px;
    text-align: center;
}

@media (max-width: 1250px) {
    .main-grid {
        grid-template-columns: 1fr 1fr;
    }

    .main-grid > .panel:last-child {
        grid-column: 1 / -1;
    }

    .bottom-grid {
        grid-template-columns: 1fr;
    }
}

@media (max-width: 980px) {
    .kpi-grid {
        grid-template-columns: repeat(3, minmax(140px, 1fr));
    }

    .aging-grid {
        grid-template-columns: 1fr;
    }

    .main-grid {
        grid-template-columns: 1fr;
    }
}

@media (max-width: 700px) {
    body {
        padding: 14px;
    }

    .kpi-grid {
        grid-template-columns: repeat(2, minmax(120px, 1fr));
    }

    .header-left h1 {
        font-size: 28px;
    }
}

@media (max-width: 480px) {
    .kpi-grid {
        grid-template-columns: 1fr;
    }
}
"@

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta http-equiv="refresh" content="900" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>UpKeep Work Order Dashboard</title>
    <style>
$css
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-left">
                <h1>UpKeep Work Order Dashboard</h1>
                <p>Status overview, aging, and priority mix.</p>
            </div>
            <div class="header-right">
                <span class="label">Last Updated</span>
                <div class="value">$generatedAtText</div>

                <span class="label">Next Refresh</span>
                <div class="value">$nextRefreshText</div>
            </div>
        </div>

        <div class="kpi-grid">
            <div class="kpi-card kpi-open">
                <div class="kpi-label">Open</div>
                <div class="kpi-value">$openText</div>
            </div>

            <div class="kpi-card kpi-progress">
                <div class="kpi-label">In Progress</div>
                <div class="kpi-value">$progressText</div>
            </div>

            <div class="kpi-card kpi-hold">
                <div class="kpi-label">On Hold</div>
                <div class="kpi-value">$holdText</div>
            </div>

            <div class="kpi-card kpi-complete">
                <div class="kpi-label">Complete</div>
                <div class="kpi-value">$completeText</div>
            </div>

            <div class="kpi-card kpi-other">
                <div class="kpi-label">Other</div>
                <div class="kpi-value">$otherText</div>
            </div>

            <div class="kpi-card kpi-total">
                <div class="kpi-label">Total Cached</div>
                <div class="kpi-value">$totalText</div>
            </div>
        </div>

        <div class="aging-grid">
            <div class="aging-card">
                <div class="aging-label">Open Older Than 7 Days</div>
                <div class="aging-value">$age7Text</div>
            </div>
            <div class="aging-card">
                <div class="aging-label">Open Older Than 14 Days</div>
                <div class="aging-value">$age14Text</div>
            </div>
            <div class="aging-card">
                <div class="aging-label">Open Older Than 30 Days</div>
                <div class="aging-value">$age30Text</div>
            </div>
        </div>

        <div class="main-grid">
            <div class="panel">
                <div class="panel-header">
                    <h2 class="panel-title">Status Mix</h2>
                    <p class="panel-subtitle">Current distribution by grouped status.</p>
                </div>
                <div class="panel-body chart-wrap">
                    <div class="donut-container">
                        <svg id="donutChart" class="donut-svg" viewBox="0 0 220 220" aria-label="Status donut chart">
                            <g id="donutSegments"></g>
                            <circle cx="110" cy="110" r="56" fill="white"></circle>
                            <text x="110" y="102" class="donut-center-text">$totalText</text>
                            <text x="110" y="124" class="donut-center-sub">Total</text>
                        </svg>
                        <div class="legend" id="donutLegend"></div>
                    </div>
                </div>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2 class="panel-title">Status Totals</h2>
                    <p class="panel-subtitle">Bar view for quick comparison.</p>
                </div>
                <div class="panel-body">
                    <div class="bar-chart">
                        <div class="bar-row">
                            <div class="bar-top">
                                <span class="bar-label">Open</span>
                                <span class="bar-value">$openText</span>
                            </div>
                            <div class="bar-track"><div class="bar-fill fill-open" style="width: $barOpenPct%;"></div></div>
                        </div>

                        <div class="bar-row">
                            <div class="bar-top">
                                <span class="bar-label">In Progress</span>
                                <span class="bar-value">$progressText</span>
                            </div>
                            <div class="bar-track"><div class="bar-fill fill-progress" style="width: $barProgressPct%;"></div></div>
                        </div>

                        <div class="bar-row">
                            <div class="bar-top">
                                <span class="bar-label">On Hold</span>
                                <span class="bar-value">$holdText</span>
                            </div>
                            <div class="bar-track"><div class="bar-fill fill-hold" style="width: $barHoldPct%;"></div></div>
                        </div>

                        <div class="bar-row">
                            <div class="bar-top">
                                <span class="bar-label">Complete</span>
                                <span class="bar-value">$completeText</span>
                            </div>
                            <div class="bar-track"><div class="bar-fill fill-complete" style="width: $barCompletePct%;"></div></div>
                        </div>

                        <div class="bar-row">
                            <div class="bar-top">
                                <span class="bar-label">Other</span>
                                <span class="bar-value">$otherText</span>
                            </div>
                            <div class="bar-track"><div class="bar-fill fill-other" style="width: $barOtherPct%;"></div></div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2 class="panel-title">Priority Breakdown</h2>
                    <p class="panel-subtitle">Based on the available priority field in the cache.</p>
                </div>
                <div class="panel-body">
                    <div class="priority-list">
$priorityHtml
                    </div>
                </div>
            </div>
        </div>

        <div class="bottom-grid">
            <div class="panel">
                <div class="panel-header">
                    <h2 class="panel-title">Work Order Status Breakdown</h2>
                    <p class="panel-subtitle">Grouped view instead of raw UpKeep status values.</p>
                </div>
                <div class="panel-body">
                    <table class="status-table">
                        <thead>
                            <tr>
                                <th>Status Group</th>
                                <th>Count</th>
                                <th>Included Raw Statuses</th>
                            </tr>
                        </thead>
                        <tbody>
$rowsHtml
                        </tbody>
                    </table>
                </div>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2 class="panel-title">Snapshot</h2>
                    <p class="panel-subtitle">Current headline numbers.</p>
                </div>
                <div class="panel-body">
                    <div class="priority-list">
                        <div class="priority-row">
                            <div class="priority-top">
                                <span class="priority-name">Total Cached Work Orders</span>
                                <span class="priority-count">$totalText</span>
                            </div>
                            <div class="priority-bar-track"><div class="priority-bar-fill" style="width: 100%;"></div></div>
                        </div>

                        <div class="priority-row">
                            <div class="priority-top">
                                <span class="priority-name">Open + In Progress + On Hold</span>
                                <span class="priority-count">$activeCount</span>
                            </div>
                            <div class="priority-bar-track"><div class="priority-bar-fill" style="width: $activePct%;"></div></div>
                        </div>

                        <div class="priority-row">
                            <div class="priority-top">
                                <span class="priority-name">Completed / Closed</span>
                                <span class="priority-count">$completeText</span>
                            </div>
                            <div class="priority-bar-track"><div class="priority-bar-fill" style="width: $completePct%;"></div></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="footer-note">
            Dashboard auto-refreshes every 15 minutes.
        </div>
    </div>

    <script>
        const chartData = $chartDataJs;

        const svgGroup = document.getElementById('donutSegments');
        const legend = document.getElementById('donutLegend');

        const cx = 110;
        const cy = 110;
        const radius = 78;
        const circumference = 2 * Math.PI * radius;

        const total = chartData.reduce((sum, item) => sum + item.value, 0);

        if (total > 0) {
            let offsetRatio = 0;

            chartData.forEach(item => {
                if (item.value <= 0) return;

                const fraction = item.value / total;
                const dash = fraction * circumference;
                const gap = circumference - dash;

                const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                circle.setAttribute('cx', cx);
                circle.setAttribute('cy', cy);
                circle.setAttribute('r', radius);
                circle.setAttribute('fill', 'none');
                circle.setAttribute('stroke', item.color);
                circle.setAttribute('stroke-width', '24');
                circle.setAttribute('stroke-linecap', 'butt');
                circle.setAttribute('transform', 'rotate(-90 110 110)');
                circle.setAttribute('stroke-dasharray', dash + ' ' + gap);
                circle.setAttribute('stroke-dashoffset', -1 * offsetRatio * circumference);
                svgGroup.appendChild(circle);

                offsetRatio += fraction;

                const legendItem = document.createElement('div');
                legendItem.className = 'legend-item';
                legendItem.innerHTML =
                    '<div class="legend-left">' +
                        '<span class="legend-swatch" style="background:' + item.color + ';"></span>' +
                        '<span>' + item.label + '</span>' +
                    '</div>' +
                    '<span class="legend-value">' + item.value + '</span>';
                legend.appendChild(legendItem);
            });
        } else {
            const emptyCircle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            emptyCircle.setAttribute('cx', cx);
            emptyCircle.setAttribute('cy', cy);
            emptyCircle.setAttribute('r', radius);
            emptyCircle.setAttribute('fill', 'none');
            emptyCircle.setAttribute('stroke', '#e5e7eb');
            emptyCircle.setAttribute('stroke-width', '24');
            svgGroup.appendChild(emptyCircle);

            legend.innerHTML = '<div class="legend-item"><span>No data available</span></div>';
        }
    </script>
</body>
</html>
"@

    return $html
}

function Write-DashboardHtml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        Ensure-DirectoryExists -Path $directory
    }

    $Html | Out-File -FilePath $Path -Encoding UTF8 -Force
}

# ===================== MAIN =====================

Ensure-DirectoryExists -Path $CacheDirectory

do {
    try {
        $UpKeepEmail = Get-RequiredEnvironmentVariable -Name "UPKEEP_EMAIL"
        $UpKeepPassword = Get-RequiredEnvironmentVariable -Name "UPKEEP_PASSWORD"

        $cacheTable = Load-CacheTable -Path $CacheFilePath
        $syncState = Load-SyncState -Path $StateFilePath

        $syncWindow = Get-IncrementalSyncWindow `
            -State $syncState `
            -ForceFullSync:$ForceFullSync `
            -InitialLookbackDays $InitialLookbackDays `
            -SyncOverlapMinutes $SyncOverlapMinutes

        Write-Host "Authenticating to UpKeep..." -ForegroundColor Cyan
        $sessionToken = Get-UpKeepSessionToken -Email $UpKeepEmail -Password $UpKeepPassword

        Write-Host "Retrieving changed work orders..." -ForegroundColor Cyan
        $changedWorkOrders = @(Get-UpKeepWorkOrdersIncremental `
            -SessionToken $sessionToken `
            -SyncWindow $syncWindow `
            -PageSize $PageSize)

        Write-Host "Changed work orders retrieved this run: $($changedWorkOrders.Count)" -ForegroundColor Green

        Write-Host "Merging results into local cache..." -ForegroundColor Cyan
        [void](Merge-WorkOrdersIntoCache -CacheTable $cacheTable -IncomingWorkOrders $changedWorkOrders)

        Write-Host "Purging stale completed work orders from cache..." -ForegroundColor Cyan
        [void](Remove-OldCompletedFromCache -CacheTable $cacheTable -PurgeCompletedAfterDays $PurgeCompletedAfterDays)

        Write-Host "Saving local cache..." -ForegroundColor Cyan
        Save-CacheTable -CacheTable $cacheTable -Path $CacheFilePath

        $nowUtc = (Get-Date).ToUniversalTime()
        Save-SyncState -Path $StateFilePath -LastSuccessfulSyncUtc $nowUtc

        $allCachedWorkOrders = @($cacheTable.Values)

        Write-Host "Building dashboard summary..." -ForegroundColor Cyan
        $summary = Get-WorkOrderStatusSummary -WorkOrders $allCachedWorkOrders -StatusConfig $StatusConfig
        $agingSummary = Get-OpenAgingSummary -WorkOrders $allCachedWorkOrders
        $prioritySummary = Get-PrioritySummary -WorkOrders $allCachedWorkOrders

        Write-Host "Generating HTML dashboard..." -ForegroundColor Cyan
        $nowLocal = Get-Date
        $nextRefresh = $nowLocal.AddSeconds($RefreshIntervalSeconds)

        $html = New-WorkOrderDashboardHtml `
            -Summary $summary `
            -PrioritySummary $prioritySummary `
            -AgingSummary $agingSummary `
            -GeneratedAt $nowLocal `
            -NextRefreshTime $nextRefresh

        Write-Host "Writing dashboard to $OutputHtmlPath" -ForegroundColor Cyan
        Write-DashboardHtml -Path $OutputHtmlPath -Html $html

        Write-Host "Dashboard updated at $nowLocal" -ForegroundColor Green
        Write-Host "Next sync in $RefreshIntervalSeconds seconds." -ForegroundColor Yellow
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Error location: $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkRed
    }

    if ($RefreshIntervalSeconds -and $RefreshIntervalSeconds -gt 0) {
        Write-Host "Waiting $RefreshIntervalSeconds seconds before next refresh..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RefreshIntervalSeconds
    }

} while ($RefreshIntervalSeconds -and $RefreshIntervalSeconds -gt 0)