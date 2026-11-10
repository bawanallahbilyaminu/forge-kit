# run-tests.ps1 - run the Pester tests under tests/ with Pester 3.4.0.
# Pester 3.4.0 ships with Windows PowerShell 5.1 (Windows 10/11 and Windows Server), so no
# install is needed locally or on the windows-latest CI image. The tests use Pester 3 syntax
# (Should Be), so a newer Pester is never loaded by accident.
# Usage (from the repo root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tests.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tests.ps1 -Path tests/handoff
# Exits 1 if any test fails or no tests ran, so CI can use it.

param([string]$Path = 'tests')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pesterVersion = [version]'3.4.0'

if ($PSVersionTable.PSEdition -eq 'Core') {
  Write-Host 'Run this with Windows PowerShell 5.1 (powershell.exe), not pwsh.'
  exit 1
}
$pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -eq $pesterVersion } | Select-Object -First 1
if (-not $pester) {
  Write-Host "Pester $pesterVersion not found. It ships with Windows PowerShell 5.1; to install it:"
  Write-Host "  Install-Module Pester -RequiredVersion $pesterVersion -Scope CurrentUser -SkipPublisherCheck -Force"
  exit 1
}
Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module $pester.Path -Force

$target = $Path
if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $root $target }
$result = Invoke-Pester -Script $target -PassThru
Write-Host ''
Write-Host "Pester $pesterVersion, PowerShell $($PSVersionTable.PSVersion): $($result.PassedCount) passed, $($result.FailedCount) failed, $($result.TotalCount) total."
if ($result.TotalCount -eq 0 -or $result.FailedCount -gt 0) { exit 1 }
exit 0
