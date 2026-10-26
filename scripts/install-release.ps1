[CmdletBinding()]
param(
  [string]$Version = 'latest',
  [string]$Repository = 'linguyuebai/zbxtable',
  [string]$InstallRoot = '',
  [switch]$Force,
  [switch]$SkipChecksum,
  [switch]$SkipFrontend
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Join-Path $env:ProgramData 'zbxtable' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('zbxtable-release-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
  $api = if ($Version -eq 'latest') { "https://api.github.com/repos/$Repository/releases/latest" } else { "https://api.github.com/repos/$Repository/releases/tags/$Version" }
  $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'zbxtable-installer'; 'Accept' = 'application/vnd.github+json' }
  $archiveAsset = @($release.assets | Where-Object { $_.name -match '-source\.zip$' } | Select-Object -First 1)
  $hashAsset = @($release.assets | Where-Object { $_.name -match '-source\.zip\.sha256$' } | Select-Object -First 1)
  if (-not $archiveAsset) { throw "No source ZIP asset found in release $Version." }
  $archive = Join-Path $temp $archiveAsset.name
  Invoke-WebRequest -Uri $archiveAsset.browser_download_url -OutFile $archive
  if (-not $SkipChecksum -and $hashAsset) {
    $hashFile = Join-Path $temp $hashAsset.name
    Invoke-WebRequest -Uri $hashAsset.browser_download_url -OutFile $hashFile
    $expected = ((Get-Content $hashFile -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { throw "SHA256 mismatch. Expected $expected, got $actual." }
    Write-Host 'SHA256 verification passed.'
  } elseif (-not $SkipChecksum) { throw 'Release has no SHA256 asset; refusing an unverified installation.' }

  if ((Test-Path $InstallRoot) -and -not $Force) { throw "Install directory exists: $InstallRoot. Use -Force to replace it." }
  $savedConfig = Join-Path $temp 'app.conf.saved'
  $existingConfig = Join-Path $InstallRoot 'config\app.conf'
  if ((Test-Path $InstallRoot) -and (Test-Path $existingConfig)) { Copy-Item $existingConfig $savedConfig -Force }
  if (Test-Path $InstallRoot) { Remove-Item $InstallRoot -Recurse -Force }
  New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
  Expand-Archive -Path $archive -DestinationPath $temp -Force
  $source = Get-ChildItem $temp -Directory | Where-Object { $_.Name -like 'zbxtable-*' } | Select-Object -First 1
  if (-not $source) { throw 'The release archive has no zbxtable source directory.' }
  Copy-Item (Join-Path $source.FullName '*') $InstallRoot -Recurse -Force
  if (Test-Path $savedConfig) { Copy-Item $savedConfig (Join-Path $InstallRoot 'config\app.conf') -Force }
  if ($SkipFrontend) { $env:ZBXTABLE_SKIP_FRONTEND = '1' }
  & (Join-Path $InstallRoot 'scripts\install.ps1')
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Application installation failed: $LASTEXITCODE" }
  Write-Host "ZbxTable installed to $InstallRoot"
} finally {
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
