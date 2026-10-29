[CmdletBinding()]
param(
  [string]$InstallRoot = (Join-Path $env:ProgramData 'zbxtable'),
  [string]$RuntimeRoot = '',
  [switch]$Purge,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) { $RuntimeRoot = $InstallRoot }

function Assert-SafePath([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetPathRoot($full)
  if ($full.TrimEnd('\') -eq $root.TrimEnd('\')) { throw "Refusing to remove a filesystem root: $full" }
  $blocked = @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData)
  foreach ($item in $blocked) {
    if ($item -and $full.TrimEnd('\').Equals($item.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove a system directory: $full"
    }
  }
  return $full
}

function Get-ConfigValue([string]$Path, [string]$Key) {
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$([regex]::Escape($Key))\s*=" } | Select-Object -First 1
  if ($line) { return (($line -split '=', 2)[1]).Trim() }
  return ''
}

function Remove-ZbxTableTables {
  if (-not $Purge) { return }
  $config = @((Join-Path $InstallRoot 'config\app.conf'), (Join-Path $RuntimeRoot 'config\app.conf')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $config) { Write-Host '[zbxtable] No configuration found; database tables were not changed.'; return }
  $type = (Get-ConfigValue $config 'dbtype').ToLowerInvariant()
  $hostName = Get-ConfigValue $config 'dbhost'; if (-not $hostName) { $hostName = '127.0.0.1' }
  $port = Get-ConfigValue $config 'dbport'; if (-not $port) { $port = if ($type -eq 'postgres' -or $type -eq 'postgresql') { '5432' } else { '3306' } }
  $user = Get-ConfigValue $config 'dbuser'; $password = Get-ConfigValue $config 'dbpass'; $configured = Get-ConfigValue $config 'dbname'
  if (-not $configured) { Write-Host '[zbxtable] Database name is missing; tables were not changed.'; return }
  $mysql = Get-Command mysql -ErrorAction SilentlyContinue
  $psql = Get-Command psql -ErrorAction SilentlyContinue
  $isPg = $type -eq 'postgres' -or $type -eq 'postgresql'
  if ((-not $isPg -and -not $mysql) -or ($isPg -and -not $psql)) { Write-Host '[zbxtable] Database client is not installed; tables were not changed.'; return }
  $env:MYSQL_PWD = $password; $env:PGPASSWORD = $password
  $databases = @($configured)
  try {
    if ($isPg) { $listed = & $psql.Source -h $hostName -p $port -U $user -d postgres -Atqc 'SELECT datname FROM pg_database' 2>$null }
    else { $listed = & $mysql.Source --protocol=TCP -h $hostName -P $port -u $user --batch --skip-column-names -e 'SHOW DATABASES' 2>$null }
    foreach ($db in $listed) { if ($db -and $db -match '(?i)zbxtable' -and $databases -notcontains $db) { $databases += $db } }
  } catch { }
  $usable = @{}
  foreach ($db in $databases) {
    if ($db -notmatch '^[A-Za-z0-9_]+$') { continue }
    if ($isPg) { $tables = @(& $psql.Source -h $hostName -p $port -U $user -d $db -Atqc "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname='public' AND LEFT(tablename, 9) = 'zbxtable_'" 2>$null) }
    else { $tables = @(& $mysql.Source --protocol=TCP -h $hostName -P $port -u $user --batch --skip-column-names --database=$db -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND LEFT(table_name, 9) = 'zbxtable_'" 2>$null) }
    $tables = @($tables | Where-Object { $_ -match '^zbxtable_[A-Za-z0-9_]+$' })
    if ($tables.Count) { $usable[$db] = $tables; Write-Host "[zbxtable] Database candidate $hostName`:$port/$db ($($tables.Count) zbxtable_ tables)" }
  }
  if (-not $usable.Count) { Write-Host '[zbxtable] No database containing zbxtable_ tables was found; no database changes made.'; return }
  $names = @($usable.Keys); $selected = $names[0]
  if ($names.Count -gt 1) {
    for ($i=0; $i -lt $names.Count; $i++) { Write-Host "  $($i+1)) $($names[$i])" }
    $input = Read-Host 'Database number (default 1)'; if ($input) { $n = 0; if (-not [int]::TryParse($input, [ref]$n) -or $n -lt 1 -or $n -gt $names.Count) { Write-Host '[zbxtable] Invalid selection; tables were not changed.'; return }; $selected = $names[$n-1] }
  }
  $tables = @($usable[$selected]); Write-Host "[zbxtable] Tables to delete in $selected`: $($tables -join ', ')"
  $confirm = Read-Host "Type DELETE TABLES to remove only these tables (database and Zabbix tables are kept)"
  if ($confirm -cne 'DELETE TABLES') { Write-Host '[zbxtable] Database table deletion cancelled.'; return }
  foreach ($table in $tables) {
    if ($isPg) { & $psql.Source -h $hostName -p $port -U $user -d $selected -v ON_ERROR_STOP=1 -c "DROP TABLE IF EXISTS `"$table`"" | Out-Null }
    else { & $mysql.Source --protocol=TCP -h $hostName -P $port -u $user --database=$selected -e "DROP TABLE IF EXISTS ``$table``" | Out-Null }
    Write-Host "[zbxtable] Removed table: $selected.$table"
  }
  Remove-Item Env:MYSQL_PWD,Env:PGPASSWORD -ErrorAction SilentlyContinue
}

$InstallRoot = Assert-SafePath $InstallRoot
$RuntimeRoot = Assert-SafePath $RuntimeRoot
if (-not $Yes) {
  $scope = if ($Purge) { "program, configuration and runtime files" } else { "program and runtime files (config/app.conf is preserved)" }
  $answer = Read-Host "This removes $scope. Type DELETE to continue"
  if ($answer -cne 'DELETE') { Write-Host 'Uninstall cancelled.'; exit 0 }
}

Get-Service -Name 'zbxtable' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
Remove-ZbxTableTables
$configBackup = Join-Path ([IO.Path]::GetTempPath()) ('zbxtable-app-' + [guid]::NewGuid().ToString('N') + '.conf')
if (-not $Purge) {
  foreach ($candidate in @((Join-Path $InstallRoot 'config\app.conf'), (Join-Path $RuntimeRoot 'config\app.conf'))) {
    if (Test-Path -LiteralPath $candidate) { Copy-Item -LiteralPath $candidate -Destination $configBackup -Force; break }
  }
}

if ($RuntimeRoot -ne $InstallRoot -and (Test-Path -LiteralPath $RuntimeRoot)) { Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force }
if (Test-Path -LiteralPath $InstallRoot) { Remove-Item -LiteralPath $InstallRoot -Recurse -Force }
if (-not $Purge -and (Test-Path -LiteralPath $configBackup)) {
  New-Item -ItemType Directory -Path (Join-Path $InstallRoot 'config') -Force | Out-Null
  Copy-Item -LiteralPath $configBackup -Destination (Join-Path $InstallRoot 'config\app.conf') -Force
  Remove-Item -LiteralPath $configBackup -Force
  Write-Host "Preserved configuration: $(Join-Path $InstallRoot 'config\app.conf')"
}
Write-Host 'ZbxTable has been removed. Zabbix services and the shared database were not modified.'
