<#
.SYNOPSIS
  Starts one of the two test update servers as a background job.

.PARAMETER DistDir
  Directory to serve (an electron-builder dist\ folder containing the versioned
  installers, blockmaps, and latest.yml). Defaults to ..\fixture\dist.

.PARAMETER Port
  Port to listen on. Must match eb.yml's publish.url. Defaults to 8099.

.PARAMETER Variant
  Which server to run:
    MultiRange  (default) -- the fix. Answers RFC 7233 multipart/byteranges correctly;
                real differential downloads work.
    SingleRange -- reproduces the documented failure: honors single-range requests (so
                the naive `curl -r 0-99 -> 206` check passes) but has no multipart
                support, so electron-updater always falls back to a full download.

.OUTPUTS
  The PowerShell Job object. Use `Receive-Job -Id <id> -Keep` to read its log, and
  `Stop-Job` / `Remove-Job` when done. The job survives file changes in DistDir --
  no restart needed between builds, since it reads from disk on every request.
#>
param(
  [string]$DistDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'fixture\dist'),
  [int]$Port = 8099,
  [ValidateSet('MultiRange', 'SingleRange')]
  [string]$Variant = 'MultiRange'
)

$scriptName = if ($Variant -eq 'MultiRange') { 'differential-update-test-server.mjs' } else { 'single-range-test-server.mjs' }
$serverScript = Join-Path (Split-Path $PSScriptRoot -Parent) "server\$scriptName"

$existing = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($existing) {
  Write-Warning "Port $Port is already in use (PID $($existing.OwningProcess)). Stop it first if you want a fresh server."
}

$job = Start-Job -Name "diffupd-update-server-$Variant" -ScriptBlock {
  param($script, $dir, $port)
  node $script $dir $port
} -ArgumentList $serverScript, $DistDir, $Port

Start-Sleep -Seconds 1
Write-Host "Server job started (Id=$($job.Id), variant=$Variant). Serving $DistDir on port $Port."
Write-Host "Check it's alive: Invoke-WebRequest http://127.0.0.1:$Port/latest.yml"
Write-Host "Read its log:      Receive-Job -Id $($job.Id) -Keep"
Write-Host "Stop it:           Stop-Job -Id $($job.Id); Remove-Job -Id $($job.Id)"
$job
