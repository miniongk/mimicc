$ErrorActionPreference = 'Stop'
$desktopDir = $PSScriptRoot
$keyPath = Join-Path $desktopDir 'src-tauri\tauri.key'
$env:TAURI_SIGNING_PRIVATE_KEY = [System.IO.File]::ReadAllText($keyPath).Trim()
Write-Host "[build-final] Key loaded: $($env:TAURI_SIGNING_PRIVATE_KEY.Substring(0, 40))..."
Set-Location $desktopDir
& bun run tauri build 2>&1
