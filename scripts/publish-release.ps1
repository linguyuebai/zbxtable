[CmdletBinding()]
param(
  [string]$Version = $env:ZBXTABLE_VERSION,
  [string]$Branch = '3.0',
  [string]$Repository = '',
  [switch]$Upload,
  [switch]$Draft,
  [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $Root

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required command not found: $Name" }
}

Require-Command 'git'
$required = @(
  'README.md', 'README.zh-CN.md', 'go.mod', 'go.sum', '.gitignore',
  'config/app.conf.example', 'scripts/install.ps1', 'scripts/install.bat',
  'scripts/install.sh', 'scripts/package-release.ps1', 'scripts/package-release.sh',
  'scripts/install-release.ps1', 'scripts/install-release.sh', 'scripts/bootstrap-linux.sh', 'scripts/uninstall.ps1', 'scripts/uninstall.sh', 'docs/README.md'
)
if (-not $SkipChecks) {
  $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_)) })
  if ($missing.Count) { throw "Required files are missing: $($missing -join ', ')" }
  $sensitive = @(git ls-files -co --exclude-standard | Where-Object {
      $_ -match '(^|[/\\])app\.conf$' -or $_ -match '(^|[/\\])\.env($|\.)' -or
      $_ -match '(^|[/\\])(log|logs|download|upload|build|dist)([/\\]|$)'
    })
  if ($sensitive.Count) { throw "Sensitive or generated paths would be published: $($sensitive -join ', ')" }
  git diff --check
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = (git describe --tags --always --dirty 2>$null)
}
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = 'dev' }
$Tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
$env:ZBXTABLE_VERSION = $Version

Write-Host "Creating release package: $Version"
$packageScript = Join-Path $Root 'scripts\package-release.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $packageScript
if ($LASTEXITCODE -ne 0) { throw "Package creation failed with exit code $LASTEXITCODE" }
$archive = Get-ChildItem (Join-Path $Root 'dist') -Filter "zbxtable-$($Version -replace '/', '-')-source.zip" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $archive) { throw 'Source ZIP was not created.' }
$tarArchive = Get-Item ((Join-Path $Root 'dist') + "\zbxtable-$($Version -replace '/', '-')-source.tar.gz")

$assets = @($archive.FullName, $archive.FullName + '.sha256', $tarArchive.FullName, $tarArchive.FullName + '.sha256')
foreach ($name in @('install-release.ps1', 'install-release.bat', 'install-release.sh', 'install.ps1', 'install.bat', 'install.sh', 'bootstrap-linux.sh', 'uninstall.ps1', 'uninstall.bat', 'uninstall.sh')) {
  $path = Join-Path $Root "scripts\$name"
  if (Test-Path -LiteralPath $path) { $assets += $path }
}
Write-Host "Package: $($archive.FullName)"
Write-Host "Package: $($tarArchive.FullName)"
Write-Host "Checksums: $($archive.FullName).sha256, $($tarArchive.FullName).sha256"
Write-Host "Installer assets: $($assets.Count - 2)"

if (-not $Upload) {
  Write-Host 'Upload not requested. Re-run with -Upload after authenticating GitHub CLI.'
  Write-Host "gh release create $Tag <assets> --target $Branch"
  exit 0
}

Require-Command 'gh'
& gh auth status
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run: gh auth login' }
$title = "ZbxTable $Tag"
$args = @('release', 'create', $Tag) + $assets + @('--target', $Branch, '--title', $title, '--generate-notes')
if (-not [string]::IsNullOrWhiteSpace($Repository)) { $args += @('--repo', $Repository) }
if ($Draft) { $args += '--draft' }
& gh @args
if ($LASTEXITCODE -ne 0) { throw "GitHub Release upload failed with exit code $LASTEXITCODE" }
Write-Host "GitHub Release uploaded: $Tag"
