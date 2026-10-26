$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Version = if ($env:ZBXTABLE_VERSION) { $env:ZBXTABLE_VERSION } else { (git -C $Root describe --tags --always --dirty 2>$null) }
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = 'dev' }
$SafeVersion = $Version -replace '/', '-'
$Dist = Join-Path $Root 'dist'
$Stage = Join-Path $env:SystemDrive ('zbxstage-' + [guid]::NewGuid().ToString('N'))
$Package = Join-Path $Stage ("zbxtable-$SafeVersion")
$Archive = Join-Path $Dist ("zbxtable-$SafeVersion-source.zip")
$TarArchive = Join-Path $Dist ("zbxtable-$SafeVersion-source.tar.gz")

New-Item -ItemType Directory -Path $Package, $Dist -Force | Out-Null
try {
  Push-Location $Root
  $files = git -c core.quotePath=false ls-files -co --exclude-standard
  foreach ($file in $files) {
    if ($file -match '^(dist|build)/' -or $file -eq 'config/app.conf') { continue }
    $source = Join-Path $Root $file
    if (-not (Test-Path -LiteralPath $source)) {
      Write-Warning "Git index contains a missing file; skipping: $file"
      continue
    }
    $target = Join-Path $Package $file
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
  }
  Pop-Location
  $web = Join-Path $Root 'api\v1\web\web\index.html'
  if (Test-Path $web) {
    Write-Warning 'The Windows ZIP source package does not copy the frontend bundle because Windows path limits can reject generated asset names. Use the TAR.GZ package for the bundled frontend, or let install.ps1 build the frontend.'
  } else {
    Write-Warning 'Frontend bundle not found. The installer will build it when Node.js/npm and network access are available.'
  }
  @("ZbxTable release: $Version", "Created: $([DateTime]::UtcNow.ToString('o'))", 'Runtime config and local data are excluded.') | Set-Content (Join-Path $Package 'RELEASE-MANIFEST.txt') -Encoding UTF8
  if (Test-Path $Archive) { Remove-Item $Archive -Force }
  Compress-Archive -Path $Package -DestinationPath $Archive -CompressionLevel Optimal
  $hash = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  $(Split-Path $Archive -Leaf)" | Set-Content "$Archive.sha256" -Encoding ASCII
  if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) { throw 'tar.exe is required to create the Linux-compatible source archive.' }
  if (Test-Path $TarArchive) { Remove-Item $TarArchive -Force }
  & tar.exe -czf $TarArchive -C $Stage "zbxtable-$SafeVersion"
  if ($LASTEXITCODE -ne 0) { throw "tar.exe failed with exit code $LASTEXITCODE" }
  $tarHash = (Get-FileHash $TarArchive -Algorithm SHA256).Hash.ToLowerInvariant()
  "$tarHash  $(Split-Path $TarArchive -Leaf)" | Set-Content "$TarArchive.sha256" -Encoding ASCII
  $bash = Get-Command bash.exe -ErrorAction SilentlyContinue
  $bashPath = if ($bash) { $bash.Source } elseif (Test-Path (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')) { Join-Path $env:ProgramFiles 'Git\bin\bash.exe' } else { $null }
  if ($bashPath) {
    $env:ZBXTABLE_VERSION = $Version
    & $bashPath (Join-Path $Root 'scripts/package-release.sh')
    if ($LASTEXITCODE -ne 0) { throw "Git Bash TAR.GZ creation failed with exit code $LASTEXITCODE" }
    Write-Host 'Git Bash regenerated TAR.GZ with the available frontend bundle.'
  }
  Write-Host "Created: $Archive"
  Write-Host "Checksum: $Archive.sha256"
  Write-Host "Created: $TarArchive"
  Write-Host "Checksum: $TarArchive.sha256"
} finally {
  if ((Get-Location).Path -eq $Root) { Pop-Location -ErrorAction SilentlyContinue }
  Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
}
