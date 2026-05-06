# 1. Complete Registry Cleanup
$paths = @(
    "HKCU:\Software\Policies\Google\Chrome",
    "HKCU:\Software\Policies\Google\Chrome\Recommended"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        # Only remove the AI-specific ones we added, leave IT ones like ExtensionSettings alone
        $targets = @("AIInnovationFeaturesAllowed", "GenAiDefaultAvailability", "TabOrganizerSettings", "HistorySearchSettings", "CreateThemesSettings", "DevToolsGenAiSettings")
        foreach ($t in $targets) {
            Remove-ItemProperty -Path $path -Name $t -ErrorAction SilentlyContinue
        }
    }
}

# 2. Add ONLY the Recommended ones back cleanly
$recPath = "HKCU:\Software\Policies\Google\Chrome\Recommended"
if (-not (Test-Path $recPath)) { New-Item -Path $recPath -Force | Out-Null }
Set-ItemProperty -Path $recPath -Name "AIInnovationFeaturesAllowed" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $recPath -Name "GenAiDefaultAvailability" -Value 0 -Type DWord -Force

# 3. Kill Chrome
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 4. Relaunch
Start-Process "chrome.exe"
