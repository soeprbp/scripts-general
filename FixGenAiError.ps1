$recPath = "HKCU:\Software\Policies\Google\Chrome\Recommended"

# Try value 1 (Enabled, but without model improvement sharing) 
# This is often the only allowed 'on' value for enterprise accounts.
Set-ItemProperty -Path $recPath -Name "GenAiDefaultSettings" -Value 1 -Type DWord -Force

# Also try the 'Availability' variant just in case version 147 uses both
Set-ItemProperty -Path $recPath -Name "GenAiDefaultAvailability" -Value 0 -Type DWord -Force

Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process "chrome.exe"
