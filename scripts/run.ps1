$ErrorActionPreference = 'Stop'
$AppDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Binary = if ($env:ZBXTABLE_BIN) { $env:ZBXTABLE_BIN } else { Join-Path $AppDir 'build\zbxtable.exe' }
if (-not (Test-Path $Binary)) { throw 'Binary not found. Run scripts\install.ps1 first.' }
New-Item -ItemType Directory -Path (Join-Path $AppDir 'log'), (Join-Path $AppDir 'download'), (Join-Path $AppDir 'upload') -Force | Out-Null
Set-Location $AppDir
& $Binary web
