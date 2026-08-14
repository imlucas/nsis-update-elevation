<#
.SYNOPSIS
  Prints the installed DiffUpd.exe's version and quits with that string on stdout,
  for easy scripting/comparison between steps.
#>
param(
  [string]$Path = 'C:\Program Files\DiffUpd\DiffUpd.exe'
)

if (-not (Test-Path $Path)) {
  Write-Warning "$Path does not exist."
  return
}
(Get-Item $Path).VersionInfo.ProductVersion
