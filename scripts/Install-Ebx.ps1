<#
.SYNOPSIS
  Downloads the ebx binary (electron-builder as a single executable,
  github.com/imlucas/ebx -- a pure passthrough, so results speak for stock
  electron-builder too) into a local bin directory.

.DESCRIPTION
  Requires `gh` already authenticated against an account with read access to the
  private imlucas/ebx repo.

.PARAMETER Destination
  Directory to place ebx.exe in. Defaults to $env:USERPROFILE\bin.
#>
param(
  [string]$Destination = (Join-Path $env:USERPROFILE 'bin')
)

New-Item -ItemType Directory -Force -Path $Destination | Out-Null

gh release download --repo imlucas/ebx --pattern 'ebx-win32-x64.exe' --dir $Destination --clobber
$downloaded = Join-Path $Destination 'ebx-win32-x64.exe'
$target = Join-Path $Destination 'ebx.exe'
if (Test-Path $target) { Remove-Item $target -Force }
Rename-Item $downloaded 'ebx.exe'

Write-Host "ebx.exe installed at $target"
& $target --version
