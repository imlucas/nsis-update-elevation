<#
.SYNOPSIS
  Reports the exact writability state the electron-userland/electron-builder#10085
  patch's IsDirWritable / IsRegKeyWritable checks would see, plus the raw ACLs, without
  needing to run an installer at all. Useful for confirming a customInstall ACL-loosening
  hook actually took effect before spending a UAC-click cycle to test it live.

.PARAMETER InstallDir
  The app's install directory. Defaults to "C:\Program Files\DiffUpd".

.PARAMETER AppGuid
  The GUID electron-builder computed for this app (the last segment of
  HKLM:\Software\<APP_GUID>). Find it with:
    Get-ChildItem HKLM:\Software | Where-Object {
      (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).InstallLocation -like '*DiffUpd*'
    }
  or from HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\<guid> DisplayName.
#>
param(
  [string]$InstallDir = 'C:\Program Files\DiffUpd',
  [string]$AppGuid
)

Write-Host "=== File ACL: $InstallDir ===" -ForegroundColor Cyan
if (Test-Path $InstallDir) {
  (Get-Acl $InstallDir).Access |
    Where-Object { $_.IdentityReference -like '*Users*' -or $_.IdentityReference -like '*Administrators*' } |
    Select-Object IdentityReference, FileSystemRights, AccessControlType |
    Format-Table -AutoSize
} else {
  Write-Warning "$InstallDir does not exist."
}

Write-Host "=== Live directory-writability probe (mirrors IsDirWritable) ===" -ForegroundColor Cyan
$testFile = Join-Path $InstallDir '.write-test.tmp'
try {
  [IO.File]::WriteAllText($testFile, '1')
  Remove-Item $testFile -Force
  Write-Host "dirWritable = 1 (current unelevated token CAN write to $InstallDir)" -ForegroundColor Green
} catch {
  Write-Host "dirWritable = 0 ($($_.Exception.Message))" -ForegroundColor Yellow
}

if ($AppGuid) {
  $regKey = "Software\$AppGuid"
  Write-Host "=== Registry: HKLM:\$regKey ===" -ForegroundColor Cyan
  $hklm = Get-ItemProperty "HKLM:\$regKey" -ErrorAction SilentlyContinue
  $hkcu = Get-ItemProperty "HKCU:\$regKey" -ErrorAction SilentlyContinue
  Write-Host "HKLM InstallLocation: $($hklm.InstallLocation)"
  Write-Host "HKCU InstallLocation: $($hkcu.InstallLocation)"

  Write-Host "=== Live registry-writability probe (mirrors IsRegKeyWritable) ===" -ForegroundColor Cyan
  try {
    New-ItemProperty -Path "HKLM:\$regKey" -Name '.write-test' -Value '1' -Force -ErrorAction Stop | Out-Null
    Remove-ItemProperty -Path "HKLM:\$regKey" -Name '.write-test' -ErrorAction SilentlyContinue
    Write-Host "regWritable = 1 (current unelevated token CAN write to HKLM:\$regKey)" -ForegroundColor Green
  } catch {
    Write-Host "regWritable = 0 ($($_.Exception.Message))" -ForegroundColor Yellow
  }
} else {
  Write-Host "(pass -AppGuid to also probe the registry key)" -ForegroundColor DarkGray
}
