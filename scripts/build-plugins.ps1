# build-plugins.ps1 - zip each plugin folder's contents into dist/<name>.plugin.
# The .plugin files are for uploading to the Claude app and attaching to GitHub Releases.
# Usage (from the repo root): powershell -NoProfile -File scripts/build-plugins.ps1
# Entries use forward slashes and the archive root is the plugin folder itself
# (so .claude-plugin/plugin.json sits at the top of the zip).

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$pluginsDir = Join-Path $root 'plugins'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$built = 0
foreach ($dir in @(Get-ChildItem -LiteralPath $pluginsDir -Directory)) {
  $manifest = Join-Path $dir.FullName '.claude-plugin\plugin.json'
  if (-not (Test-Path -LiteralPath $manifest)) {
    Write-Host "skip $($dir.Name): no .claude-plugin/plugin.json"
    continue
  }
  $meta = [System.IO.File]::ReadAllText($manifest) | ConvertFrom-Json
  $name = [string]$meta.name
  if (-not $name) { $name = $dir.Name }

  $out = Join-Path $dist "$name.plugin"
  if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

  $files = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force |
    Where-Object { $_.Name -ne '.DS_Store' -and $_.Name -ne 'Thumbs.db' } |
    Sort-Object FullName)

  $zip = [System.IO.Compression.ZipFile]::Open($out, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($f in $files) {
      $entry = $f.FullName.Substring($dir.FullName.Length + 1) -replace '\\', '/'
      $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $f.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
    }
  }
  finally { $zip.Dispose() }

  $size = [math]::Round((Get-Item -LiteralPath $out).Length / 1KB, 1)
  Write-Host "built dist/$name.plugin  v$($meta.version)  $($files.Count) files  $size KB"
  $built++
}

if ($built -eq 0) { Write-Host 'No plugins built.'; exit 1 }
exit 0
