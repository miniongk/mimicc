$ErrorActionPreference = 'Stop'
$keyPath = Join-Path $PSScriptRoot 'src-tauri\tauri.key'
$env:TAURI_SIGNING_PRIVATE_KEY = Get-Content $keyPath -Raw
Write-Host "Key loaded: $($env:TAURI_SIGNING_PRIVATE_KEY.Substring(0, 40))..."
& bun run tauri build
