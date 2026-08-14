<#
.SYNOPSIS
  Guided, sequential reproduction of every finding in README.md. Pauses at each step
  that genuinely needs a human at the keyboard (running an installer, approving a UAC
  prompt, clicking through a wizard) -- those cannot be scripted by design, and this
  script tells you exactly what to do and what to expect at each one.

.DESCRIPTION
  Run this from a normal (non-elevated) PowerShell prompt, as an admin account. It will
  stop and print instructions whenever it needs you to act; press Enter to continue once
  you've done it. Each phase also names which README.md section it reproduces.

.PARAMETER SkipPatchedBuilder
  Skip Phase 3 (building electron-userland/electron-builder#10085 from source). Phases 1
  and 2 (differential download + baseline elevation behavior) don't need it.
#>
param(
  [switch]$SkipPatchedBuilder
)

$root = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path $root 'fixture'
$dist = Join-Path $fixture 'dist'

function Pause-ForAction($message) {
  Write-Host ""
  Write-Host "ACTION REQUIRED:" -ForegroundColor Yellow
  Write-Host $message -ForegroundColor Yellow
  Read-Host "Press Enter once done"
}

function Step($title) {
  Write-Host ""
  Write-Host "=== $title ===" -ForegroundColor Cyan
}

Step "Phase 0: prerequisites"
& "$PSScriptRoot\Install-Ebx.ps1"

Step "Phase 1a: build v1.0.0 and v1.0.1, reproduce the differential-download failure (README verdict 1, single-range server)"
& "$PSScriptRoot\Build-Version.ps1" -Version '1.0.0' -FixtureDir $fixture
& "$PSScriptRoot\Build-Version.ps1" -Version '1.0.1' -FixtureDir $fixture
$job = & "$PSScriptRoot\Start-UpdateServer.ps1" -DistDir $dist -Variant SingleRange

Pause-ForAction @"
Run this installer directly (double-click it, don't launch an already-installed app):
  $dist\DiffUpd Setup 1.0.0.exe
In the wizard, use "change install location" and set it to:
  C:\Program Files\DiffUpd
Approve the UAC prompt when it appears -- this is expected (writing to Program Files
always needs elevation at least once). Finish the install, then launch:
  C:\Program Files\DiffUpd\DiffUpd.exe
Watch it check for the 1.0.1 update against the single-range server.
"@

Write-Host "Expected in the app's console/log (redirect stdout to see it -- GUI apps have no visible console):"
Write-Host '  Cannot download differentially, fallback to full download: Error: Content-Type "multipart/byteranges" is expected, but got "null"'
& "$PSScriptRoot\Get-DiffUpdVersion.ps1"
Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
Remove-Job -Id $job.Id -ErrorAction SilentlyContinue

Step "Phase 1b: same update, but against the multi-range server (README verdict 1, the fix)"
& "$PSScriptRoot\Build-Version.ps1" -Version '1.0.2' -FixtureDir $fixture
$job = & "$PSScriptRoot\Start-UpdateServer.ps1" -DistDir $dist -Variant MultiRange

Pause-ForAction @"
Launch the installed app again:
  C:\Program Files\DiffUpd\DiffUpd.exe
It's now on 1.0.1; it should find 1.0.2 and this time actually save bytes. You'll
likely see the same wizard + UAC prompt as before, since main.js still calls
quitAndInstall() with default (non-silent) options -- that's README verdict 2, not a
bug in the server fix.
"@

Write-Host "Check the server's log (Receive-Job -Id $($job.Id) -Keep) for a line like:"
Write-Host '  206 multi-range(N) GET /DiffUpd%20Setup%201.0.2.exe ... bytesSent=<small> (of <full size> full)'
& "$PSScriptRoot\Get-DiffUpdVersion.ps1"

Step "Phase 2: isSilent:true drops the wizard but not the UAC prompt (README bonus round)"
Write-Host "Edit fixture\main.js: change quitAndInstall() to quitAndInstall(true, true), then:"
Write-Host "  .\Build-Version.ps1 -Version 1.0.3   # this hop still uses 1.0.2's OLD code -> wizard+UAC, expected"
Write-Host "  # launch, let it land on 1.0.3, THEN:"
Write-Host "  .\Build-Version.ps1 -Version 1.0.4   # NOW governed by 1.0.3's new isSilent:true code"
Write-Host "  # launch again -- expect a bare UAC prompt, no wizard"
Write-Host "(Not fully scripted here since it's a two-hop bridge with a human check in the middle -- see README.md 'isSilent true vs false' for the exact reasoning.)"

if ($SkipPatchedBuilder) {
  Write-Host ""
  Write-Host "Skipping Phase 3 (-SkipPatchedBuilder). See README.md for the rest by hand." -ForegroundColor DarkGray
  Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
  Remove-Job -Id $job.Id -ErrorAction SilentlyContinue
  return
}

Step "Phase 3: ACL loosening alone doesn't work; patched electron-builder does (README 'The corruption bug' + electron-builder#10085)"
Write-Host "This phase needs a fresh install through THIS fixture's build/installer.nsh (the ACL-loosening customInstall hook), then a rebuild with the patched electron-builder to test the fix. See README.md 'Reproducing the electron-builder patch' for the exact sequence -- it's long enough (registry cleanup between attempts, a two-way check) that walking through it here would just repeat the doc. Run:"
Write-Host "  .\Build-PatchedElectronBuilder.ps1"
Write-Host "then follow README.md from 'Reproducing the electron-builder patch' onward."

Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
Remove-Job -Id $job.Id -ErrorAction SilentlyContinue
