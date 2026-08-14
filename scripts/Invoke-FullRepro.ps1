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

  Every build in this script goes through electron-builder compiled from source at an
  exact pinned commit (Build-ElectronBuilder.ps1) -- there's no packaged binary shortcut
  used anywhere, so the baseline and patched builds differ by exactly the two files PR
  #10085 touches, and nothing else.

.PARAMETER SkipPatchedBuilder
  Skip Phase 3 (building the electron-userland/electron-builder#10085 patch itself and
  re-testing). Phases 0-2 (differential download + baseline elevation behavior) don't
  need it and don't take nearly as long.

.PARAMETER BaselineCommit
  The exact electron-builder commit PR #10085 is based against. Override only if the PR
  has been rebased since this script was written.
#>
param(
  [switch]$SkipPatchedBuilder,
  [string]$BaselineCommit = 'c0b8235d7f86d90ffe7218765115b6948b180739'
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

Step "Phase 0: build electron-builder from source, pinned to PR #10085's base commit"
& "$PSScriptRoot\Build-ElectronBuilder.ps1" -Destination (Join-Path $root 'eb-baseline') -Branch $BaselineCommit
$baselineCli = Join-Path $root 'eb-baseline\packages\electron-builder\cli.js'

Step "Phase 1a: build v1.0.0 and v1.0.1, reproduce the differential-download failure (README Finding 1, single-range server)"
& "$PSScriptRoot\Build-Version.ps1" -Version '1.0.0' -FixtureDir $fixture -BuilderCommand $baselineCli
& "$PSScriptRoot\Build-Version.ps1" -Version '1.0.1' -FixtureDir $fixture -BuilderCommand $baselineCli
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

Step "Phase 1b: same update, but against the multi-range server (README Finding 1, the fix)"
& "$PSScriptRoot\Build-Version.ps1" -Version '1.0.2' -FixtureDir $fixture -BuilderCommand $baselineCli
$job = & "$PSScriptRoot\Start-UpdateServer.ps1" -DistDir $dist -Variant MultiRange

Pause-ForAction @"
Launch the installed app again:
  C:\Program Files\DiffUpd\DiffUpd.exe
It's now on 1.0.1; it should find 1.0.2 and this time actually save bytes. You'll
likely see the same wizard + UAC prompt as before, since main.js still calls
quitAndInstall() with default (non-silent) options -- that's Finding 2, covered next.
"@

Write-Host "Check the server's log (Receive-Job -Id $($job.Id) -Keep) for a line like:"
Write-Host '  206 multi-range(N) GET /DiffUpd%20Setup%201.0.2.exe ... bytesSent=<small> (of <full size> full)'
& "$PSScriptRoot\Get-DiffUpdVersion.ps1"
Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
Remove-Job -Id $job.Id -ErrorAction SilentlyContinue

Step "Phase 2: elevation-every-time (README Finding 2, baseline behavior PR #10085 patches)"
& "$PSScriptRoot\Build-Version.ps1" -Version '1.0.3' -FixtureDir $fixture -BuilderCommand $baselineCli
$job = & "$PSScriptRoot\Start-UpdateServer.ps1" -DistDir $dist -Variant MultiRange

Pause-ForAction @"
Launch the installed app again:
  C:\Program Files\DiffUpd\DiffUpd.exe
Expect: the wizard reappears, then a UAC prompt on interaction. This is the exact
baseline behavior PR #10085 patches.
"@
& "$PSScriptRoot\Get-DiffUpdVersion.ps1"
Stop-Job -Id $job.Id -ErrorAction SilentlyContinue
Remove-Job -Id $job.Id -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "isSilent:true vs false (drops the wizard, not the UAC prompt) is a two-hop bridge"
Write-Host "with a human check in the middle -- see README.md 'isSilent true vs false' for the"
Write-Host "exact steps; not scripted here to keep this phase linear."

if ($SkipPatchedBuilder) {
  Write-Host ""
  Write-Host "Skipping Phase 3 (-SkipPatchedBuilder). See README.md for the rest by hand." -ForegroundColor DarkGray
  return
}

Step "Phase 3: ACL loosening alone doesn't work; the patched electron-builder does (README 'The corruption bug' + electron-builder#10085)"
Write-Host "This phase needs a fresh install through THIS fixture's build/installer.nsh (the ACL-loosening customInstall hook), built with the PATCHED electron-builder, then a registry-cleanup-sensitive sequence to test the fix safely. See README.md 'Reproducing the electron-builder patch' for the exact sequence -- it's long enough (registry cleanup between attempts, a two-way check) that walking through it here would just repeat the doc. Run:"
Write-Host "  .\Build-ElectronBuilder.ps1 -Destination ..\eb-patched -Branch nsis-skip-unnecessary-elevation -Remote https://github.com/imlucas/electron-builder.git"
Write-Host "then follow README.md from 'Reproducing the electron-builder patch' onward."
