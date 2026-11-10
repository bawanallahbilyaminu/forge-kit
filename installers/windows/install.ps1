# install.ps1 - installs the Claude Code -> planning chat handoff for ALL projects,
# without the plugin system. The code-handoff plugin is the recommended way; use this
# installer only if you don't use Claude Code plugins. Don't use both.
#
# Run from the repo root:
#   powershell -ExecutionPolicy Bypass -File installers\windows\install.ps1             install
#   powershell -ExecutionPolicy Bypass -File installers\windows\install.ps1 -Uninstall  remove it again
#   add -Force to install even though the code-handoff plugin is installed and enabled
#
# Install copies handoff.ps1 and /next into %USERPROFILE%\.claude and adds a Stop hook to
# %USERPROFILE%\.claude\settings.json. Uninstall removes exactly that hook entry and those
# two files. Project .claude\handoff folders are never touched.
param(
  [switch]$Uninstall,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
Remove-TypeData System.Array -ErrorAction SilentlyContinue   # keeps arrays as arrays in ConvertTo-Json (PowerShell 5.1)
$utf8 = New-Object System.Text.UTF8Encoding($false)

$kit = Join-Path $PSScriptRoot '..\..\plugins\code-handoff'
$claude = Join-Path $env:USERPROFILE '.claude'
$hooksDir = Join-Path $claude 'hooks'
$cmdDir = Join-Path $claude 'commands'
$settingsPath = Join-Path $claude 'settings.json'
$hookFile = Join-Path $hooksDir 'handoff.ps1'
$cmdFile = Join-Path $cmdDir 'next.md'
$scriptPath = $hookFile -replace '\\', '/'
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

# Text that marks the two files as ours, so uninstall never deletes a user's own file.
$hookMarker = 'handoff.ps1 - Claude Code Stop hook'
$cmdMarker = 'Run the next prompt prepared by the planning chat'

function Read-Settings {
  if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
  $raw = [System.IO.File]::ReadAllText($settingsPath)
  if (-not $raw.Trim()) { return $null }
  return ($raw | ConvertFrom-Json)
}

function Write-Settings($s) {
  $json = $s | ConvertTo-Json -Depth 50
  $null = $json | ConvertFrom-Json   # sanity check before writing
  [System.IO.File]::WriteAllText($settingsPath, $json, $utf8)
}

# True for a hook entry that runs the installer's copy of handoff.ps1.
function Test-OurHook($h) {
  if (-not $h) { return $false }
  $c = (([string]$h.command + ' ' + (@($h.args) -join ' ')) -replace '\\', '/').ToLowerInvariant()
  return $c.Contains($scriptPath.ToLowerInvariant())
}

# How Claude Code records plugins (checked against Claude Code 2.1.x):
#   %USERPROFILE%\.claude\plugins\installed_plugins.json  -> "plugins": { "<name>@<marketplace>": [ { scope, installPath, version, ... } ] }
#   %USERPROFILE%\.claude\settings.json                   -> "enabledPlugins": { "<name>@<marketplace>": true | false }
# The plugin is active when it is installed and enabledPlugins has it set to true.
function Get-PluginState {
  $state = [pscustomobject]@{ Installed = @(); Enabled = @() }
  $ip = Join-Path $claude 'plugins\installed_plugins.json'
  if (Test-Path -LiteralPath $ip) {
    try {
      $j = [System.IO.File]::ReadAllText($ip) | ConvertFrom-Json
      if ($j.plugins) {
        $state.Installed = @($j.plugins.PSObject.Properties | Where-Object { $_.Name -like 'code-handoff@*' } | ForEach-Object { $_.Name })
      }
    } catch { Write-Host "Could not read $ip, so the plugin check is skipped: $($_.Exception.Message)" }
  }
  try {
    $s = Read-Settings
    if ($s -and $s.enabledPlugins) {
      foreach ($name in $state.Installed) {
        $p = $s.enabledPlugins.PSObject.Properties[$name]
        if ($p -and $p.Value -eq $true) { $state.Enabled += $name }
      }
    }
  } catch { Write-Host "Could not read settings.json for enabledPlugins: $($_.Exception.Message)" }
  return $state
}

# ------------------------------------------------------------------ uninstall
if ($Uninstall) {
  $s = $null
  if (Test-Path -LiteralPath $settingsPath) { $s = Read-Settings }
  $removed = 0
  if ($s -and $s.hooks -and ($s.hooks.PSObject.Properties.Name -contains 'Stop')) {
    $groups = @()
    foreach ($g in @($s.hooks.Stop)) {
      if (-not $g) { continue }
      $all = @($g.hooks)
      $keep = @($all | Where-Object { -not (Test-OurHook $_) })
      $removed += ($all.Count - $keep.Count)
      if ($keep.Count -eq $all.Count) { $groups += $g }               # untouched group
      elseif ($keep.Count -gt 0) { $g.hooks = $keep; $groups += $g }  # other hooks stay in this group
    }
    if ($removed -gt 0) {
      Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak-handoff-uninstall" -Force
      Write-Host "Backed up settings.json to settings.json.bak-handoff-uninstall"
      if ($groups.Count -gt 0) { $s.hooks.Stop = $groups }
      else { $s.hooks.PSObject.Properties.Remove('Stop') }
      if (@($s.hooks.PSObject.Properties).Count -eq 0) { $s.PSObject.Properties.Remove('hooks') }
      Write-Settings $s
      Write-Host "Removed $removed handoff Stop hook entry(ies) from settings.json. Other settings and hooks are unchanged."
    }
  }
  if ($removed -eq 0) { Write-Host 'No installer handoff Stop hook found in settings.json.' }

  foreach ($pair in @(@($hookFile, $hookMarker), @($cmdFile, $cmdMarker))) {
    $f = $pair[0]
    if (-not (Test-Path -LiteralPath $f)) { continue }
    if ([System.IO.File]::ReadAllText($f).Contains($pair[1])) {
      Remove-Item -LiteralPath $f -Force
      Write-Host "Removed $f"
    } else {
      Write-Host "Left $f in place: it doesn't look like the file this installer copied."
    }
  }
  Write-Host 'Done. Restart open Claude Code sessions (claude --continue) to unload the hook.'
  exit 0
}

# ------------------------------------------------------------------ install
$plugin = Get-PluginState
if ($plugin.Enabled.Count -gt 0) {
  Write-Warning ("The code-handoff plugin is installed and enabled (" + ($plugin.Enabled -join ', ') + "). " +
    "Installing this copy as well would run the hook twice; the plugin copy would then step aside.")
  if (-not $Force) {
    Write-Host 'Nothing installed. Keep using the plugin, or uninstall it first (/plugin uninstall code-handoff), or re-run with -Force.'
    exit 1
  }
  Write-Host '-Force given: installing anyway.'
} elseif ($plugin.Installed.Count -gt 0) {
  Write-Host ("The code-handoff plugin is installed but disabled (" + ($plugin.Installed -join ', ') + "). Continuing. Don't enable both.")
}

New-Item -ItemType Directory -Force -Path $hooksDir, $cmdDir | Out-Null
Copy-Item (Join-Path $kit 'scripts\handoff.ps1') $hookFile -Force
Copy-Item (Join-Path $kit 'commands\next.md') $cmdFile -Force
Write-Host "Copied hook script and /next command into $claude"

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

Write-Settings $s
Write-Host 'Added the Stop hook to settings.json. Done - restart open Claude Code sessions (claude --continue) to load it.'
Write-Host 'To remove it later: powershell -ExecutionPolicy Bypass -File installers\windows\install.ps1 -Uninstall'
