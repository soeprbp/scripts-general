<#
.SYNOPSIS
  Simple UpKeep Work Order Status Dashboard

.DESCRIPTION
  - Logs into UpKeep v2 API using email/password to get a Session-Token
  - Retrieves all work orders via GET /api/v2/work-orders with paging
  - Counts work orders by status and builds a basic HTML dashboard
  - Optionally loops on an interval to refresh the HTML

.NOTES
  Requires: PowerShell 5+ (Core compatible), Internet access
#>

# ===================== CONFIGURATION =====================

# UpKeep credentials (recommend: secure these via SecretManagement, env vars, or a vault)
$UpKeepEmail    = "soperbp@welchpkg.com"
$UpKeepPassword = "Pow10ermad!"

# HTML output path
$OutputHtmlPath = "C:\UpKeepDashboard\UpKeep-WorkOrder-Dashboard.html"

# Poll interval in seconds (set to 0 or $null to run once and exit)
$RefreshIntervalSeconds = 300   # 5 minutes

# Work order status mapping for display + filtering
# Adjust the StatusValues to match your org if you use custom statuses.
$StatusConfig = @(
    @{ Name = "Open";        StatusValues = @("Open") }
    @{ Name = "In Progress"; StatusValues = @("In-Progress", "In Progress") }
    @{ Name = "Complete";    StatusValues = @("Complete", "Closed") }
)

# API base URLs
$UpKeepBaseUrlV2 = "https://api.onupkeep.com/api/v2"    # modern v2 API [web:2]
$AuthEndpoint    = "$UpKeepBaseUrlV2/auth"
$WorkOrdersEndpoint = "$UpKeepBaseUrlV2/work-orders"

# Paging defaults (UpKeep supports typical offset/limit style pagination) [web:1]
$PageSize = 200

# ===================== HELPER FUNCTIONS =====================

function Get-UpKeepSessionToken {
    param(
        [string]$Email,
        [string]$Password
    )

    Write-Verbose "Requesting UpKeep session token for $Email"

    $body = @{
        email    = $Email
        password = $Password
    }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $AuthEndpoint -Body $body
        if (-not $response.success) {
            throw "Authentication failed. Response: $($response | ConvertTo-Json -Depth 4)"
        }
        # v2 auth returns { success: true, result: { sessionToken, expiresAt } } [web:1]
        return $response.result.sessionToken
    }
    catch {
        throw "Error obtaining UpKeep Session Token: $($_.Exception.Message)"
    }
}

function Get-UpKeepWorkOrders {
    param(
        [string]$SessionToken,
        [int]$PageSize = 200
    )

    $allWorkOrders = @()
    $offset = 0

    $headers = @{
        "Session-Token" = $SessionToken
    }

    while ($true) {
        $uri = "$WorkOrdersEndpoint?limit=$PageSize&offset=$offset"
        Write-Verbose "Fetching work orders page at offset $offset"

        try {
            $page = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        }
        catch {
            throw "Error retrieving work orders: $($_.Exception.Message)"
        }

        if (-not $page.success) {
            throw "Work order API returned unsuccessful response: $($page | ConvertTo-Json -Depth 4)"
        }

        # v2 list endpoints typically return { success: true, results: [...] } [web:1]
        $results = $page.results
        if (-not $results -or $results.Count -eq 0) {
            break
        }

        $allWorkOrders += $results
        $offset += $PageSize
    }

    return $allWorkOrders
}

function Get-WorkOrderStatusSummary {
    param(
        [array]$WorkOrders,
        [array]$StatusConfig
    )

    # Normalize statuses once
    $normalized = $WorkOrders | ForEach-Object {
        # v2 work order objects contain a "status" field with values like "Open", "In-Progress", "On Hold", "Complete", etc. [web:10]
        [PSCustomObject]@{
            Status = $_.status
        }
    }

    $summary = @()

    foreach ($group in $StatusConfig) {
        $name          = $group.Name
        $statusValues  = $group.StatusValues

        $count = ($normalized | Where-Object {
                $statusValues -contains $_.Status
        }).Count

        $summary += [PSCustomObject]@{
            Name  = $name
            Count = $count
            StatusValues = ($statusValues -join ", ")
        }
    }

    # Add total line
    $totalCount = $normalized.Count
    $summary += [PSCustomObject]@{
        Name         = "Total"
        Count        = $totalCount
        StatusValues = "All"
    }

    return $summary
}

function New-WorkOrderDashboardHtml {
    param(
        [array]$Summary,
        [datetime]$GeneratedAt
    )

    $rows = $Summary | ForEach-Object {
        "<tr><td>$($_.Name)</td><td style='text-align:right;'>$($_.Count)</td><td>$($_.StatusValues)</td></tr>"
    } | Out-String

    $css = @"
body {
    font-family: Arial, sans-serif;
    margin: 20px;
    background-color: #f5f7fa;
}
h1 {
    color: #333333;
}
table {
    border-collapse: collapse;
    width: 100%;
    max-width: 600px;
    background-color: white;
}
th, td {
    border: 1px solid #dddddd;
    padding: 8px 12px;
}
th {
    background-color: #0063b1;
    color: white;
}
tr:nth-child(even) {
    background-color: #f2f2f2;
}
.footer {
    margin-top: 10px;
    font-size: 0.85em;
    color: #666666;
}
"@

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>UpKeep Work Order Dashboard</title>
    <style>
$css
    </style>
</head>
<body>
    <h1>UpKeep Work Order Dashboard</h1>
    <table>
        <thead>
            <tr>
                <th>Status Group</th>
                <th>Count</th>
                <th>Included Raw Statuses</th>
            </tr>
        </thead>
        <tbody>
$rows
        </tbody>
    </table>
    <div class="footer">
        Generated at: $GeneratedAt (local time)
    </div>
</body>
</html>
"@

    return $html
}

function Write-DashboardHtml {
    param(
        [string]$Path,
        [string]$Html
    )

    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $Html | Out-File -FilePath $Path -Encoding UTF8 -Force
}

# ===================== MAIN LOOP =====================

do {
    try {
        Write-Host "Authenticating to UpKeep..." -ForegroundColor Cyan
        $sessionToken = Get-UpKeepSessionToken -Email $UpKeepEmail -Password $UpKeepPassword

        Write-Host "Retrieving work orders..." -ForegroundColor Cyan
        $workOrders = Get-UpKeepWorkOrders -SessionToken $sessionToken -PageSize $PageSize

        Write-Host "Total work orders retrieved: $($workOrders.Count)" -ForegroundColor Green

        Write-Host "Building status summary..." -ForegroundColor Cyan
        $summary = Get-WorkOrderStatusSummary -WorkOrders $workOrders -StatusConfig $StatusConfig

        Write-Host "Generating HTML dashboard..." -ForegroundColor Cyan
        $now = Get-Date
        $html = New-WorkOrderDashboardHtml -Summary $summary -GeneratedAt $now

        Write-Host "Writing dashboard to $OutputHtmlPath" -ForegroundColor Cyan
        Write-DashboardHtml -Path $OutputHtmlPath -Html $html

        Write-Host "Dashboard updated at $now" -ForegroundColor Green
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($RefreshIntervalSeconds -and $RefreshIntervalSeconds -gt 0) {
        Write-Host "Waiting $RefreshIntervalSeconds seconds before next refresh..." -ForegroundColor Yellow
        Start-Sleep -Seconds $RefreshIntervalSeconds
    }

} while ($RefreshIntervalSeconds -and $RefreshIntervalSeconds -gt 0)
