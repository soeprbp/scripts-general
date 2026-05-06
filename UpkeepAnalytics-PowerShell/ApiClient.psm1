# UpKeep API Client Module

function Initialize-UpKeepSession {
    param(
        [string]$BaseUrl,
        [string]$ApiKey
    )

    try {
        $headers = @{
            "Authorization" = "Bearer $ApiKey"
            "Content-Type" = "application/json"
        }

        $response = Invoke-RestMethod -Uri "$BaseUrl/users/me" -Method Get -Headers $headers -ErrorAction Stop

        return @{
            BaseUrl = $BaseUrl
            ApiKey = $ApiKey
            UserId = $response.id
        }
    }
    catch {
        Write-Host "Auth error: $_" -ForegroundColor Red
        return $null
    }
}

function Get-WorkOrders {
    param(
        [hashtable]$Session,
        [datetime]$SinceDate
    )

    $allWorkOrders = @()
    $page = 1
    $limit = 200
    $headers = @{
        "Authorization" = "Bearer $($Session.ApiKey)"
        "Content-Type" = "application/json"
    }

    while ($true) {
        $url = "$($Session.BaseUrl)/work-orders?limit=$limit&page=$page&sort=createdDesc"

        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -ErrorAction Stop

            if ($response.data -and $response.data.Count -gt 0) {
                foreach ($wo in $response.data) {
                    $createdDate = [datetime]::Parse($wo.createdAt)

                    if ($createdDate -lt $SinceDate) {
                        Write-Host "Reached $($SinceDate.ToString('yyyy-MM-dd')) - stopping fetch" -ForegroundColor Gray
                        return $allWorkOrders
                    }

                    $allWorkOrders += $wo
                }

                Write-Host "Page $page: fetched $($response.data.Count) work orders (total: $($allWorkOrders.Count))" -ForegroundColor Gray

                if ($response.data.Count -lt $limit) {
                    break
                }

                $page++
                Start-Sleep -Milliseconds 200
            }
            else {
                break
            }
        }
        catch {
            Write-Host "Error fetching page $page : $_" -ForegroundColor Red
            break
        }
    }

    return $allWorkOrders
}

Export-Module -Function Initialize-UpKeepSession, Get-WorkOrders