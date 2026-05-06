# -----------------------------------------------------------
# Chrome AI Feature Enabler (Recommended Policy Path)
# -----------------------------------------------------------

# 1. Define Paths
$localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
# Recommended path allows user-level overrides without "Mandatory" errors
$regPath = "HKCU:\Software\Policies\Google\Chrome\Recommended"

if (-not (Test-Path $localStatePath)) {
    Write-Error "Could not find Chrome Local State file."
    return
}

# 2. Apply Recommended Registry Policies
Write-Host "Applying Recommended Registry Policies..." -ForegroundColor Cyan
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# Remove the ones from the Mandatory path that were causing errors
Remove-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome" -Name "AIInnovationFeaturesAllowed" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome" -Name "GenAiDefaultAvailability" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\Software\Policies\Google\Chrome" -Name "TabOrganizerSettings" -ErrorAction SilentlyContinue

# Set policies in Recommended path
Set-ItemProperty -Path $regPath -Name "AIInnovationFeaturesAllowed" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $regPath -Name "GenAiDefaultAvailability" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $regPath -Name "TabOrganizerSettings" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $regPath -Name "HistorySearchSettings" -Value 0 -Type DWord -Force

# 3. Kill Chrome
Write-Host "Closing Chrome..." -ForegroundColor Yellow
Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 4. Modify Local State (Flags)
$localState = Get-Content $localStatePath -Raw | ConvertFrom-Json

# Force flags again to be sure
$aiFlags = @("glic@1", "glic-side-panel@1", "tab-organization@1", "history-search-settings@1", "compose-settings@1")
if ($null -eq $localState.browser.enabled_labs_experiments) {
    if ($null -eq $localState.browser) { $localState | Add-Member -NotePropertyName "browser" -NotePropertyValue @{} }
    $localState.browser | Add-Member -NotePropertyName "enabled_labs_experiments" -NotePropertyValue @()
}
foreach ($flag in $aiFlags) {
    if ($localState.browser.enabled_labs_experiments -notcontains $flag) {
        $localState.browser.enabled_labs_experiments += $flag
    }
}

# 5. Save and Relaunch
$localState | ConvertTo-Json -Depth 100 | Set-Content $localStatePath -Encoding UTF8
Write-Host "Policies moved to Recommended. Relaunching..." -ForegroundColor Green
Start-Process "chrome.exe"
