# install.ps1 - installs the Claude Code -> planning chat handoff for ALL projects.
# Run once from the repo root:  powershell -ExecutionPolicy Bypass -File installers\windows\install.ps1
# Use this OR the code-handoff Claude Code plugin, not both.
$ErrorActionPreference = 'Stop'
Remove-TypeData System.Array -ErrorAction SilentlyContinue   # keeps arrays as arrays in ConvertTo-Json (PowerShell 5.1)
$kit = Join-Path $PSScriptRoot '..\..\plugins\code-handoff'
$claude = Join-Path $env:USERPROFILE '.claude'
$hooksDir = Join-Path $claude 'hooks'
$cmdDir = Join-Path $claude 'commands'
New-Item -ItemType Directory -Force -Path $hooksDir, $cmdDir | Out-Null

Copy-Item (Join-Path $kit 'scripts\handoff.ps1') (Join-Path $hooksDir 'handoff.ps1') -Force
Copy-Item (Join-Path $kit 'commands\next.md') (Join-Path $cmdDir 'next.md') -Force
Write-Host "Copied hook script and /next command into $claude"

$settingsPath = Join-Path $claude 'settings.json'
$scriptPath = (Join-Path $hooksDir 'handoff.ps1') -replace '\\', '/'
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$raw = ''
if (Test-Path -LiteralPath $settingsPath) { $raw = [System.IO.File]::ReadAllText($settingsPath) }
if ($raw -match 'hooks/handoff\.ps1') {
  Write-Host 'The Stop hook is already in settings.json. Nothing else to do.'
  exit 0
}
if ($raw.Trim()) {
  Copy-Item $settingsPath "$settingsPath.bak-handoff" -Force
  Write-Host "Backed up settings.json to settings.json.bak-handoff"
  $s = $raw | ConvertFrom-Json
} else {
  $s = New-Object PSObject
}

$entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $command; async = $true; timeout = 30 }) }
if (-not ($s.PSObject.Properties.Name -contains 'hooks')) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
if (-not ($s.hooks.PSObject.Properties.Name -contains 'Stop')) { $s.hooks | Add-Member -NotePropertyName Stop -NotePropertyValue @() }
$s.hooks.Stop = @(@($s.hooks.Stop) + $entry)

$json = $s | ConvertTo-Json -Depth 50
$null = $json | ConvertFrom-Json   # sanity check before writing
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'Added the Stop hook to settings.json. Done - restart open Claude Code sessions (claude --continue) to load it.'
