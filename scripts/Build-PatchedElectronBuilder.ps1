<#
.SYNOPSIS
  Clones and compiles the electron-userland/electron-builder#10085 patch branch from
  source, so Build-Version.ps1 can build fixture installers with it instead of stock
  ebx/electron-builder.

.DESCRIPTION
  This is a full pnpm monorepo build (~2000 packages) -- expect several minutes for
  `pnpm install` and a couple more for `tsc --build`. Requires `gh` authenticated with
  at least read access; the fork is public so no special access is needed.

.PARAMETER Destination
  Where to clone electron-builder. Defaults to .\electron-builder next to this repo.

.PARAMETER Branch
  Branch to build. Defaults to the PR's branch on the imlucas fork.

.OUTPUTS
  Prints the path to the compiled cli.js to pass as -BuilderCommand to Build-Version.ps1.
#>
param(
  [string]$Destination = (Join-Path (Split-Path $PSScriptRoot -Parent) 'electron-builder'),
  [string]$Branch = 'nsis-skip-unnecessary-elevation',
  [string]$Remote = 'https://github.com/imlucas/electron-builder.git'
)

if (-not (Test-Path $Destination)) {
  git clone --depth 50 --branch $Branch $Remote $Destination
} else {
  Write-Host "$Destination already exists, pulling latest..."
  Push-Location $Destination
  git fetch origin $Branch
  git checkout $Branch
  git pull
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
  Write-Host "Built. Pass this to Build-Version.ps1 -BuilderCommand:" -ForegroundColor Green
  Write-Host $cli
} else {
  Write-Warning "Expected cli.js not found at $cli -- check the build output above."
}
