# check-powershell.ps1 - parse-check every .ps1 file in the repo and check it is ASCII-only.
# Windows PowerShell 5.1 misreads UTF-8 files without a BOM, so non-ASCII bytes are an error.
# Usage (from the repo root): powershell -NoProfile -File scripts/check-powershell.ps1
# Exits 1 if any file fails, so CI can use it.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1' |
  Where-Object { $_.FullName -notmatch '[\\/](\.git|dist|node_modules)[\\/]' })

$failed = 0
foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length + 1)
  $problems = @()

  $tokens = $null
  $errors = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
  foreach ($e in @($errors)) {
    if ($e) { $problems += "parse error line $($e.Extent.StartLineNumber): $($e.Message)" }
  }

  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $line = 1
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 10) { $line++ }
    elseif ($bytes[$i] -gt 127) { $problems += "non-ASCII byte on line $line"; break }
  }

  if ($problems.Count -gt 0) {
    $failed++
    Write-Host "FAIL $rel"
    foreach ($p in $problems) { Write-Host "     $p" }
  } else {
    Write-Host "ok   $rel"
  }
}

Write-Host ''
Write-Host "$($files.Count) file(s) checked, $failed failed. PowerShell $($PSVersionTable.PSVersion)"
if ($failed -gt 0) { exit 1 }
exit 0
