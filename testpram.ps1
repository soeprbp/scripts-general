param(
    [string]$BaseUrl = "http://encore.welchpkg.com",
    [string]$Username,
    [string]$Password,
    [string]$DataSourceId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PlainTextPassword {
    param([string]$ExistingPassword)

    if (-not [string]::IsNullOrWhiteSpace($ExistingPassword)) {
        return $ExistingPassword
    }

    $secure = Read-Host "Password" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-ErrorBody {
    param($Exception)

    try {
        $response = $Exception.Response
        if ($null -eq $response) { return $null }

        $stream = $response.GetResponseStream()
        if ($null -eq $stream) { return $null }

        $reader = New-Object System.IO.StreamReader($stream)
        $body = $reader.ReadToEnd()
        $reader.Close()
        return $body
    }
    catch {
        return $null
    }
}

function Get-TokenFromResponse {
    param($Response)

    if ($null -eq $Response) { return $null }

    $candidateNames = @("token", "Token", "access_token", "AccessToken")

    foreach ($name in $candidateNames) {
        $prop = $Response.PSObject.Properties[$name]
        if ($null -ne $prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return [string]$prop.Value
        }
    }

    return $null
}

if ([string]::IsNullOrWhiteSpace($Username)) {
    $Username = Read-Host "Username"
}

$Password = Get-PlainTextPassword -ExistingPassword $Password

$authRaw = if ([string]::IsNullOrWhiteSpace($DataSourceId)) {
    "$Username`:$Password"
}
else {
    "$Username`:$Password`:$DataSourceId"
}

$authB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($authRaw))
$uri = $BaseUrl.TrimEnd("/") + "/api/Account"

$headers = @{
    Authorization = "Basic $authB64"
    Accept        = "application/json"
}

$attempts = @(
    @{
        Name        = "JSON body with raw id"
        Body        = (@{ id = $authRaw } | ConvertTo-Json -Compress)
        ContentType = "application/json"
    },
    @{
        Name        = "JSON body with base64 id"
        Body        = (@{ id = $authB64 } | ConvertTo-Json -Compress)
        ContentType = "application/json"
    },
    @{
        Name        = "Plain raw body"
        Body        = $authRaw
        ContentType = "text/plain"
    },
    @{
        Name        = "Plain base64 body"
        Body        = $authB64
        ContentType = "text/plain"
    },
    @{
        Name        = "No body"
        Body        = $null
        ContentType = $null
    }
)

Write-Host ""
Write-Host "Testing EnCore auth against: $uri"
Write-Host "Username: $Username"
if (-not [string]::IsNullOrWhiteSpace($DataSourceId)) {
    Write-Host "DataSourceId: $DataSourceId"
}
Write-Host ""

$success = $false

foreach ($attempt in $attempts) {
    Write-Host "Trying: $($attempt.Name) ..." -ForegroundColor Cyan

    try {
        if ($null -ne $attempt.ContentType) {
            $response = Invoke-RestMethod `
                -Method Post `
                -Uri $uri `
                -Headers $headers `
                -Body $attempt.Body `
                -ContentType $attempt.ContentType
        }
        else {
            $response = Invoke-RestMethod `
                -Method Post `
                -Uri $uri `
                -Headers $headers
        }

        $token = Get-TokenFromResponse -Response $response

        Write-Host "HTTP call succeeded." -ForegroundColor Green
        Write-Host "Response:"
        $response | ConvertTo-Json -Depth 8

        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $previewLen = [Math]::Min(24, $token.Length)
            $preview = $token.Substring(0, $previewLen)

            Write-Host ""
            Write-Host "Token found." -ForegroundColor Green
            Write-Host "Token preview: $preview..."
            Write-Host ""
            Write-Host "Use this header for later calls:"
            Write-Host "Authorization: Bearer <token>"

            $success = $true
            break
        }
        else {
            Write-Warning "Call worked, but no token property was found. Inspect the response above."
        }
    }
    catch {
        $body = Get-ErrorBody -Exception $_.Exception
        Write-Warning ("Failed: " + $_.Exception.Message)

        if (-not [string]::IsNullOrWhiteSpace($body)) {
            Write-Host "Server response body:"
            Write-Host $body
        }

        Write-Host ""
    }
}

if (-not $success) {
    Write-Host ""
    Write-Host "No token was returned by any attempt." -ForegroundColor Yellow
    Write-Host "Next things to verify:"
    Write-Host "  1. Username/password are valid for API access"
    Write-Host "  2. DataSourceId is required for your EnCore instance"
    Write-Host "  3. /api/Account is exposed on this server"
    Write-Host "  4. The body format expected by your environment"
}