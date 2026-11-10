# check-shared-refs.ps1 - check that files shared between skills are identical copies.
# Skills can be installed one by one, each in its own folder, so a skill must not read
# files from a sibling skill. Shared files are therefore copied into each skill, and this
# script checks every copy against its source by SHA-256 hash.
# Usage (from the repo root): powershell -NoProfile -File scripts/check-shared-refs.ps1
# Exits 1 if any copy differs or is missing, so CI can use it.

# Add more shared files here. Paths are relative to the repo root.
$shared = @(
  @{
    Source = 'plugins/idea-forge/skills/idea-launch/references/projects-folder.md'
    Copies = @(
      'plugins/idea-forge/skills/idea-council/references/projects-folder.md',
      'plugins/idea-forge/skills/idea-refine/references/projects-folder.md',
      'plugins/idea-forge/skills/idea-code-setup/references/projects-folder.md'
    )
  }
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function HashOf($rel) {
  $path = Join-Path $root $rel
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

$failed = 0
$checked = 0
foreach ($set in $shared) {
  $srcHash = HashOf $set.Source
  if (-not $srcHash) {
    Write-Host "FAIL $($set.Source)"
    Write-Host '     source file is missing'
    $failed++
    continue
  }
  Write-Host "src  $($set.Source)"
  foreach ($copy in $set.Copies) {
    $checked++
    $h = HashOf $copy
    if (-not $h) {
      Write-Host "FAIL $copy"
      Write-Host '     copy is missing'
      $failed++
    } elseif ($h -ne $srcHash) {
      Write-Host "FAIL $copy"
      Write-Host "     differs from $($set.Source)"
      $failed++
    } else {
      Write-Host "ok   $copy"
    }
  }
}

Write-Host ''
Write-Host "$checked copies checked, $failed failed."
if ($failed -gt 0) { exit 1 }
exit 0
