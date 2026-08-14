<#
.SYNOPSIS
  Bumps the fixture app's version and builds an NSIS installer for it.

.PARAMETER Version
  The version string to set in fixture/package.json, e.g. "1.0.1".

.PARAMETER FixtureDir
  Path to the fixture app directory (containing package.json/main.js/eb.yml).
  Defaults to ..\fixture relative to this script.

.PARAMETER BuilderCommand
  How to invoke electron-builder. Either the path to ebx.exe (stock builder), or the
  path to a locally-built electron-builder cli.js (see Build-PatchedElectronBuilder.ps1)
  to exercise the electron-userland/electron-builder#10085 patch. Defaults to
  "$env:USERPROFILE\bin\ebx.exe".

.EXAMPLE
  .\Build-Version.ps1 -Version 1.0.1

.EXAMPLE
  # Build with the locally patched electron-builder instead of stock ebx
  .\Build-Version.ps1 -Version 1.0.6 -BuilderCommand 'C:\src\electron-builder\packages\electron-builder\cli.js'
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$Version,

  [string]$FixtureDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'fixture'),

  [string]$BuilderCommand = (Join-Path $env:USERPROFILE 'bin\ebx.exe')
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

  if ($BuilderCommand -like '*.js') {
    node $BuilderCommand --config eb.yml --win nsis --x64 --publish never
  } else {
    & $BuilderCommand --config eb.yml --win nsis --x64 --publish never
  }
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
