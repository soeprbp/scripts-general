$source = "\\svwpefs\WelchEncoreShare\WELCHPKG\EDI\Logs\EDI_log.txt"
$destinationFolder = "C:\Users\soperbp\OneDrive - Welch Packaging Group\IT - Enterprise Solutions - Development\EDI\Log"
$destinationFile = Join-Path $destinationFolder "EDI_log.txt"

if (-not (Test-Path $destinationFolder)) {
    New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
}

Copy-Item -Path $source -Destination $destinationFile -Force