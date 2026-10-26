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

$InstallRoot = Assert-SafePath $InstallRoot
$RuntimeRoot = Assert-SafePath $RuntimeRoot
if (-not $Yes) {
  $scope = if ($Purge) { "program, configuration and runtime files" } else { "program and runtime files (config/app.conf is preserved)" }
  $answer = Read-Host "This removes $scope. Type DELETE to continue"
  if ($answer -cne 'DELETE') { Write-Host 'Uninstall cancelled.'; exit 0 }
}

Get-Service -Name 'zbxtable' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
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
