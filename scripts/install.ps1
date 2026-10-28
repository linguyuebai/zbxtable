$ErrorActionPreference = 'Stop'
$AppDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ConfigDir = Join-Path $AppDir 'config'
$ConfigFile = Join-Path $ConfigDir 'app.conf'
$BuildDir = Join-Path $AppDir 'build'

function Ask([string]$Prompt, [string]$Default) {
  $value = Read-Host "$Prompt [$Default]"
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
  return $value
}

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
  throw 'Go 1.24 or newer is required.'
}
$goVersion = (& go version) -replace '.*go([0-9.]+).*', '$1'
try { $parsedGo = [version]$goVersion } catch { throw "Unable to parse Go version: $goVersion" }
if ($parsedGo -lt [version]'1.24') { throw "Go $goVersion is too old; Go 1.24 or newer is required." }
Write-Host "Environment check passed: $([Environment]::OSVersion.VersionString), Go $goVersion"

function Test-Port([string]$HostName, [int]$Port, [string]$Label) {
  try {
    $result = Test-NetConnection -ComputerName $HostName -Port $Port -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) { Write-Host "$Label reachable: $HostName`:$Port" }
    else { Write-Warning "$Label is not reachable: $HostName`:$Port; installation continues." }
  } catch { Write-Warning "Could not test $Label $HostName`:$Port" }
}

if (-not (Test-Path $ConfigFile) -or $env:ZBXTABLE_FORCE_CONFIG -eq '1') {
  $dbType = if ($env:ZBXTABLE_DB_TYPE) { $env:ZBXTABLE_DB_TYPE } else { Ask 'Database type' 'mysql' }
  $dbHost = if ($env:ZBXTABLE_DB_HOST) { $env:ZBXTABLE_DB_HOST } else { Ask 'Zabbix database host' '127.0.0.1' }
  $dbPort = if ($env:ZBXTABLE_DB_PORT) { $env:ZBXTABLE_DB_PORT } else { Ask 'Database port' '3306' }
  $dbName = if ($env:ZBXTABLE_DB_NAME) { $env:ZBXTABLE_DB_NAME } else { Ask 'ZbxTable database name' 'zbxtable' }
  $dbUser = if ($env:ZBXTABLE_DB_USER) { $env:ZBXTABLE_DB_USER } else { Ask 'Database user' 'zbxtable' }
  $dbPass = if ($env:ZBXTABLE_DB_PASS) { $env:ZBXTABLE_DB_PASS } else { Read-Host 'Database password' }
  $httpPort = if ($env:ZBXTABLE_HTTP_PORT) { $env:ZBXTABLE_HTTP_PORT } else { Ask 'HTTP port' '8089' }
  $runMode = if ($env:ZBXTABLE_RUN_MODE) { $env:ZBXTABLE_RUN_MODE } else { Ask 'Run mode' 'prod' }

  Test-Port $dbHost ([int]$dbPort) 'Database'

  New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
  @"
httpport=$httpPort
runmode=$runMode
timeout=12
log_level=3
log_path=log
maxlines=1000
maxsize=0
maxdays=10
daily=true
dbtype=$dbType
dbhost=$dbHost
dbuser=$dbUser
dbpass=$dbPass
dbname=$dbName
dbport=$dbPort
"@ | Set-Content -Path $ConfigFile -Encoding UTF8
  Write-Host "Wrote shared-database configuration: $dbType`:$dbPort/$dbName"
} else {
  Write-Host "Existing configuration found; keeping $ConfigFile"
  $httpPort = ((Get-Content $ConfigFile | Where-Object { $_ -match '^httpport=' }) -replace '^httpport=', '')
  if ([string]::IsNullOrWhiteSpace($httpPort)) { $httpPort = '8089' }
}

$httpProbe = Get-NetTCPConnection -LocalPort ([int]$httpPort) -State Listen -ErrorAction SilentlyContinue
if ($httpProbe) { throw "HTTP port $httpPort is already in use; choose another port. Existing Zabbix services are not modified." }

New-Item -ItemType Directory -Path $BuildDir, (Join-Path $AppDir 'log'), (Join-Path $AppDir 'download'), (Join-Path $AppDir 'upload') -Force | Out-Null
if ($env:ZBXTABLE_SKIP_FRONTEND -ne '1') {
  & (Join-Path $AppDir 'scripts\prepare-frontend.ps1')
}
Push-Location $AppDir
try {
  go mod download
  go build -trimpath -ldflags '-s -w' -o (Join-Path $BuildDir 'zbxtable.exe') ./main.go
} finally { Pop-Location }
Write-Host 'Installation complete. Run scripts\run.ps1 and open http://127.0.0.1:8089.'
