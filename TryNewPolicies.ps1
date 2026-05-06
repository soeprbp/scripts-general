# 1. Cleanup old/failed keys
$regPath = "HKCU:\Software\Policies\Google\Chrome\Recommended"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

# 2. Try consolidated and updated policy names for 2026
$policies = @{
    "GenAiFeaturesAllowed"           = 1
    "GenerativeAiAllowed"           = 1
    "AiFeaturesDefaultAvailability"  = 0
    "AIInnovationFeaturesAllowed"    = 1 # Keep for backward compat
    "GenAiDefaultAvailability"       = 0 # Keep for backward compat
}

foreach ($name in $policies.Keys) {
    Set-ItemProperty -Path $regPath -Name $name -Value $policies[$name] -Type DWord -Force
}

# 3. Kill and Relaunch
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process "chrome.exe"
