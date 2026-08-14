<#
.SYNOPSIS
  Clones and compiles electron-builder from source, at an exact pinned commit or branch.
  Use this for BOTH the baseline (unpatched) and patched builds -- see .PARAMETER Branch.

.DESCRIPTION
  This is a full pnpm monorepo build (~2000 packages) -- expect several minutes for
  `pnpm install` and a couple more for `tsc --build`. Requires `gh` authenticated with
  at least read access; both remotes below are public, so no special access is needed.

  Building from source and pinning an exact commit (rather than depending on whatever a
  packaged release happens to contain) matters here specifically because the baseline
  and patched builds need to differ by *only* the two files PR #10085 touches -- any
  other drift between them would confound the comparison.

.PARAMETER Destination
  Where to clone electron-builder. Defaults to .\electron-builder next to this repo.

.PARAMETER Branch
  Branch, tag, or commit SHA to build. Two common values:
    c0b8235d7f86d90ffe7218765115b6948b180739   -- PR #10085's exact base commit (baseline,
                                                    unpatched -- pair with the upstream Remote)
    nsis-skip-unnecessary-elevation             -- the patch itself (pair with the fork Remote)

.PARAMETER Remote
  Defaults to the upstream repo (electron-userland/electron-builder), which is what you
  want for a pinned baseline commit. Pass the fork (https://github.com/imlucas/electron-builder.git)
  when building the patch branch.

.EXAMPLE
  # Baseline: exactly what PR #10085 diffs against.
  .\Build-ElectronBuilder.ps1 -Destination .\eb-baseline -Branch c0b8235d7f86d90ffe7218765115b6948b180739

.EXAMPLE
  # The patch under test.
  .\Build-ElectronBuilder.ps1 -Destination .\eb-patched -Branch nsis-skip-unnecessary-elevation -Remote https://github.com/imlucas/electron-builder.git

.OUTPUTS
  Prints the path to the compiled cli.js to pass as -BuilderCommand to Build-Version.ps1.
#>
param(
  [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) 'electron-builder'),
  [Parameter(Mandatory = $true)]
  [string]$Branch,
  [string]$Remote = 'https://github.com/electron-userland/electron-builder.git'
)

if (-not (Test-Path $Destination)) {
  git clone $Remote $Destination
  Push-Location $Destination
  git checkout $Branch
  Pop-Location
} else {
  Write-Host "$Destination already exists, checking out $Branch..."
  Push-Location $Destination
  git fetch origin $Branch
  git checkout $Branch
  Pop-Location
}

Push-Location $Destination
try {
  Write-Host 'Running pnpm install (first run only, several minutes)...'
  pnpm install --frozen-lockfile

  Write-Host 'Compiling TypeScript...'
  npx tsc --build tsconfig.build.json --force
}
finally {
  Pop-Location
}

$cli = Join-Path $Destination 'packages\electron-builder\cli.js'
if (Test-Path $cli) {
  Write-Host "Built $Branch. Pass this to Build-Version.ps1 -BuilderCommand:" -ForegroundColor Green
  Write-Host $cli
} else {
  Write-Warning "Expected cli.js not found at $cli -- check the build output above."
}
