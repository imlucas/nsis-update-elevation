<#
.SYNOPSIS
  Bumps the fixture app's version and builds an NSIS installer for it.

.PARAMETER Version
  The version string to set in fixture/package.json, e.g. "1.0.1".

.PARAMETER FixtureDir
  Path to the fixture app directory (containing package.json/main.js/eb.yml).
  Defaults to ..\fixture relative to this script.

.PARAMETER BuilderCommand
  Path to a locally-built electron-builder cli.js (see Build-ElectronBuilder.ps1),
  pinned to whichever commit/branch you built. Run Build-ElectronBuilder.ps1 first;
  defaults to the cli.js at its default output location (..\electron-builder next to
  this repo).

.EXAMPLE
  .\Build-ElectronBuilder.ps1 -Branch c0b8235d7f86d90ffe7218765115b6948b180739
  .\Build-Version.ps1 -Version 1.0.1

.EXAMPLE
  # Build with the patched electron-builder instead of the baseline
  .\Build-Version.ps1 -Version 1.0.6 -BuilderCommand '..\eb-patched\packages\electron-builder\cli.js'
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Version,

  [string]$FixtureDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'fixture'),

  [string]$BuilderCommand = (Join-Path (Split-Path $PSScriptRoot -Parent) 'electron-builder\packages\electron-builder\cli.js')
)

$pkgPath = Join-Path $FixtureDir 'package.json'
$pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
$pkg.version = $Version
($pkg | ConvertTo-Json -Depth 10) | Set-Content $pkgPath

Push-Location $FixtureDir
try {
  if (-not (Test-Path (Join-Path $FixtureDir 'node_modules'))) {
    Write-Host 'Running npm install (first build only)...'
    npm install
  }

  node $BuilderCommand --config eb.yml --win nsis --x64 --publish never
}
finally {
  Pop-Location
}

$distDir = Join-Path $FixtureDir 'dist'
$exe = Join-Path $distDir "DiffUpd Setup $Version.exe"
$blockmap = "$exe.blockmap"
if (Test-Path $exe) {
  $size = (Get-Item $exe).Length
  Write-Host "Built: $exe ($size bytes)"
  if (Test-Path $blockmap) { Write-Host "Blockmap: $blockmap ($((Get-Item $blockmap).Length) bytes)" }
  Write-Host "latest.yml:"
  Get-Content (Join-Path $distDir 'latest.yml')
} else {
  Write-Warning "Expected installer not found at $exe -- check builder output above."
}
