$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Embed = Join-Path $Root 'api\v1\web\web'
$WebDir = $env:ZBXTABLE_WEB_DIR
$Repo = if ($env:ZBXTABLE_WEB_REPO) { $env:ZBXTABLE_WEB_REPO } else { 'https://github.com/canghai908/zbxtable-web.git' }
$Ref = if ($env:ZBXTABLE_WEB_REF) { $env:ZBXTABLE_WEB_REF } else { '3.0' }
$Temp = $null

if ($env:ZBXTABLE_SKIP_FRONTEND -eq '1') { Write-Host 'Frontend build skipped.'; exit 0 }
if ($env:ZBXTABLE_KEEP_EMBEDDED_FRONTEND -eq '1' -and (Test-Path (Join-Path $Embed 'index.html'))) { Write-Host "Keeping existing embedded frontend: $Embed"; exit 0 }
if (-not $WebDir) {
  foreach ($candidate in @((Join-Path $Root '..\zbxtable-web'), (Join-Path $Root '..\zbxtable-web-master\zbxtable-web-master'))) {
    if (Test-Path (Join-Path $candidate 'package.json')) { $WebDir = (Resolve-Path $candidate).Path; break }
  }
}
if (-not $WebDir) {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required to download the frontend.' }
  $Temp = Join-Path ([System.IO.Path]::GetTempPath()) ('zbxtable-web-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $Temp -Force | Out-Null
  $WebDir = Join-Path $Temp 'web'
  Write-Host "Downloading frontend: $Repo ($Ref)"
  git clone --depth 1 --branch $Ref $Repo $WebDir 2>$null
  if ($LASTEXITCODE -ne 0) { git clone --depth 1 $Repo $WebDir }
}
try {
  if (-not (Test-Path (Join-Path $WebDir 'package.json'))) { throw "Frontend package.json not found: $WebDir" }
  node (Join-Path $Root 'scripts\patch-frontend-zabbix.js') $WebDir
  if ($LASTEXITCODE -ne 0) { throw 'Applying the Zabbix integration UI patch failed.' }
  if (-not $env:NODE_OPTIONS) { $env:NODE_OPTIONS = '--openssl-legacy-provider' }
  Push-Location $WebDir
  if ((Get-Command yarn -ErrorAction SilentlyContinue) -and (Test-Path 'yarn.lock')) { yarn install --frozen-lockfile; yarn build }
  else { npm ci; npm run build }
  Pop-Location
  $output = if (Test-Path (Join-Path $WebDir 'web')) { Join-Path $WebDir 'web' } elseif (Test-Path (Join-Path $WebDir 'app\build')) { Join-Path $WebDir 'app\build' } else { throw 'Frontend output web or app/build was not found.' }
  Remove-Item $Embed -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $Embed -Force | Out-Null
  Copy-Item (Join-Path $output '*') $Embed -Recurse -Force
  Write-Host "Frontend embedded: $Embed"
} finally {
  if ((Get-Location).Path -eq $WebDir) { Pop-Location -ErrorAction SilentlyContinue }
  if ($Temp) { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
