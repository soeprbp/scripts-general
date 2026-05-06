param(
    [string]$BaseUrl = "https://encore.welchpkg.com"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Resolve-AbsoluteUrl {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Base,
        [Parameter(Mandatory=$true)]
        [string]$Relative
    )

    try {
        $baseUri = [System.Uri]$Base
        $outUri = [System.Uri]::new($baseUri, $Relative)
        return $outUri.AbsoluteUri
    }
    catch {
        return $null
    }
}

function Get-WebText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Url
    )

    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20
        return [pscustomobject]@{
            Url        = $Url
            StatusCode = [int]$resp.StatusCode
            Content    = $resp.Content
            Headers    = $resp.Headers
        }
    }
    catch {
        $ex = $_.Exception
        $resp = $ex.Response

        $statusCode = $null
        $content = $null
        $headers = $null

        if ($null -ne $resp) {
            try { $statusCode = [int]$resp.StatusCode } catch {}

            try { $headers = $resp.Headers } catch {}

            try {
                $stream = $resp.GetResponseStream()
                if ($null -ne $stream) {
                    $reader = New-Object System.IO.StreamReader($stream)
                    try {
                        $content = $reader.ReadToEnd()
                    }
                    finally {
                        $reader.Close()
                    }
                }
            }
            catch {}
        }

        return [pscustomobject]@{
            Url        = $Url
            StatusCode = $statusCode
            Content    = $content
            Headers    = $headers
        }
    }
}

$rootUrl = $BaseUrl.TrimEnd("/") + "/"
Write-Host "Fetching root page: $rootUrl" -ForegroundColor Cyan

$root = Get-WebText -Url $rootUrl

if ([string]::IsNullOrWhiteSpace($root.Content)) {
    throw "Could not fetch homepage content from $rootUrl"
}

Write-Host ""
Write-Host "Root page status: $($root.StatusCode)" -ForegroundColor Green

$patterns = @(
    "(?i)(?:src|href)\s*=\s*[""'']([^""'']+\.(?:js|css)(?:\?[^""'']*)?)[""'']",
    "(?i)[""''](\/[^""'']+\/(?:openapi|swagger)[^""'']*)[""'']",
    "(?i)[""'']([^""'']*openapi[^""'']*)[""'']",
    "(?i)[""'']([^""'']*swagger[^""'']*)[""'']",
    "(?i)[""'']([^""'']*\/api\/[^""'']*)[""'']",
    "(?i)[""'']([^""'']*connect\/token[^""'']*)[""'']",
    "(?i)[""'']([^""'']*oauth[^""'']*)[""'']",
    "(?i)[""'']([^""'']*bearer[^""'']*)[""'']"
)

$discovered = New-Object System.Collections.Generic.HashSet[string]

foreach ($pattern in $patterns) {
    $matches = [regex]::Matches($root.Content, $pattern)
    foreach ($m in $matches) {
        if ($m.Groups.Count -gt 1) {
            $candidate = $m.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                [void]$discovered.Add($candidate)
            }
        }
    }
}

Write-Host ""
Write-Host "Candidates found directly in HTML:" -ForegroundColor Yellow
($discovered | Sort-Object) | ForEach-Object { Write-Host "  $_" }

$assetUrls = New-Object System.Collections.Generic.List[string]

foreach ($item in $discovered) {
    if ($item -match "\.(js|css)(\?|$)") {
        $abs = Resolve-AbsoluteUrl -Base $rootUrl -Relative $item
        if (-not [string]::IsNullOrWhiteSpace($abs)) {
            [void]$assetUrls.Add($abs)
        }
    }
}

$assetUrls = $assetUrls | Sort-Object -Unique

Write-Host ""
Write-Host "Linked JS/CSS assets to inspect:" -ForegroundColor Yellow
$assetUrls | ForEach-Object { Write-Host "  $_" }

$interestingRegexes = @(
    "(?i)https?:\/\/[^""'\s]+",
    "(?i)\/api\/[A-Za-z0-9_\-\/\.]+",
    "(?i)\/swagger[^\s""'`]+",
    "(?i)\/openapi[^\s""'`]+",
    "(?i)connect\/token",
    "(?i)authorization",
    "(?i)bearer",
    "(?i)access_token",
    "(?i)token",
    "(?i)login",
    "(?i)auth"
)

$findings = New-Object System.Collections.Generic.List[object]

foreach ($assetUrl in $assetUrls) {
    Write-Host ""
    Write-Host "Inspecting asset: $assetUrl" -ForegroundColor Cyan
    $asset = Get-WebText -Url $assetUrl

    if ([string]::IsNullOrWhiteSpace($asset.Content)) {
        Write-Host "  Failed or empty." -ForegroundColor DarkYellow
        continue
    }

    foreach ($rx in $interestingRegexes) {
        $matches = [regex]::Matches($asset.Content, $rx)
        foreach ($m in $matches) {
            $value = $m.Value.Trim()
            if ($value.Length -gt 3) {
                $findings.Add([pscustomobject]@{
                    Asset = $assetUrl
                    Hit   = $value
                }) | Out-Null
            }
        }
    }
}

$results = $findings |
    Group-Object -Property Hit |
    ForEach-Object {
        [pscustomobject]@{
            Count = $_.Count
            Hit   = $_.Name
        }
    } |
    Sort-Object -Property @(
        @{ Expression = "Count"; Descending = $true },
        @{ Expression = "Hit";   Descending = $false }
    )

Write-Host ""
Write-Host "=== Most likely API/Auth clues ===" -ForegroundColor Green
$results |
    Where-Object {
        $_.Hit -match "(?i)\/api\/|swagger|openapi|token|bearer|authorization|auth|login|connect\/token"
    } |
    Select-Object -First 100 |
    Format-Table -AutoSize

Write-Host ""
Write-Host "=== Direct HTML clues again ===" -ForegroundColor Green
$discovered |
    Sort-Object |
    ForEach-Object { Write-Host "  $_" }