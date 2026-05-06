# 1. Cleanup all old policy attempts
$paths = @(
    "HKCU:\Software\Policies\Google\Chrome",
    "HKCU:\Software\Policies\Google\Chrome\Recommended"
)
$oldNames = @("AIInnovationFeaturesAllowed", "GenAiDefaultAvailability", "TabOrganizerSettings", "HistorySearchSettings", "CreateThemesSettings", "DevToolsGenAiSettings", "GenAiFeaturesAllowed", "GenerativeAiAllowed", "AiFeaturesDefaultAvailability")

foreach ($path in $paths) {
    if (Test-Path $path) {
        foreach ($name in $oldNames) {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        }
    }
}

# 2. Apply OFFICIAL 2026 Chrome 147 Policies (Recommended Path)
$recPath = "HKCU:\Software\Policies\Google\Chrome\Recommended"
if (-not (Test-Path $recPath)) { New-Item -Path $recPath -Force | Out-Null }

$newPolicies = @{
    "GenAiDefaultSettings"          = 0  # 0 = Allow all features + model improvement
    "DevToolsGenAiSettings"         = 0  # 0 = Enabled
    "AIModeSettings"                = 0  # 0 = Enabled (usually 1 is disabled)
    "GeminiActOnWebSettings"        = 0  # 0 = Enabled
    "SearchContentSharingSettings"  = 0  # 0 = Enabled
}

foreach ($name in $newPolicies.Keys) {
    Set-ItemProperty -Path $recPath -Name $name -Value $newPolicies[$name] -Type DWord -Force
}

# 3. Final Kill and Relaunch
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process "chrome.exe"
