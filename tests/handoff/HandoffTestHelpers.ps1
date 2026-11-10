# HandoffTestHelpers.ps1 - helpers for handoff.Tests.ps1 (Pester 3.4.0, Windows PowerShell 5.1).
# Every test runs plugins/code-handoff/scripts/handoff.ps1 in a child powershell.exe with a
# temporary USERPROFILE and temporary projects, the way Claude Code runs the Stop hook.
# Nothing here reads or writes the real user profile.

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:HandoffScript = Join-Path $script:RepoRoot 'plugins\code-handoff\scripts\handoff.ps1'
$script:FixtureDir = Join-Path $script:RepoRoot 'tests\fixtures\handoff'
$script:PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

# A new empty temp folder for one Describe block. Remove it with Remove-TestRoot.
function New-TestRoot {
  $p = Join-Path ([System.IO.Path]::GetTempPath()) ('forge-kit-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  return $p
}
function Remove-TestRoot($root) {
  if ($root -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
function New-FakeHome($root) {
  $h = Join-Path $root 'home'
  New-Item -ItemType Directory -Force -Path (Join-Path $h '.claude') | Out-Null
  # With USERPROFILE pointing here, Windows resolves LocalApplicationData to home\AppData\Local.
  # If that folder is missing, powershell.exe writes its module analysis cache relative to the
  # working directory instead, so create it to keep everything inside the temp folder.
  New-Item -ItemType Directory -Force -Path (Join-Path $h 'AppData\Local') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $h 'AppData\Roaming') | Out-Null
  return $h
}
function New-TestProject($root, $name) {
  $p = Join-Path $root $name
  New-Item -ItemType Directory -Force -Path (Join-Path $p '.claude') | Out-Null
  return $p
}
function Set-TestFile($path, $text) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  [System.IO.File]::WriteAllText($path, $text, $script:Utf8)
}

# Settings JSON with one Stop hook: shell form (a command string) or exec form (command + args).
function New-HookJson($command) {
  return (@{ hooks = @{ Stop = @(@{ hooks = @(@{ type = 'command'; command = $command }) }) } } | ConvertTo-Json -Depth 8)
}
function New-ExecHookJson($argsList) {
  return (@{ hooks = @{ Stop = @(@{ hooks = @(@{ type = 'command'; command = 'powershell.exe'; args = $argsList }) }) } } | ConvertTo-Json -Depth 8)
}

# A one-turn synthetic transcript: "test prompt <n>" and "reply <n>".
function New-SimpleTranscript($project, $n) {
  $tp = Join-Path $project 'transcript.jsonl'
  $u = @{ type = 'user'; message = @{ role = 'user'; content = "test prompt $n" } } | ConvertTo-Json -Compress -Depth 5
  $a = @{ type = 'assistant'; message = @{ role = 'assistant'; content = @(@{ type = 'text'; text = "reply $n" }) } } | ConvertTo-Json -Compress -Depth 5
  [System.IO.File]::WriteAllText($tp, "$u`n$a`n", $script:Utf8)
  return $tp
}

# Runs handoff.ps1 once with the Stop hook JSON on stdin. Returns the exit code, or the
# Process object with -NoWait. -PluginRoot '' runs it as the installer copy.
function Invoke-Handoff {
  param(
    [string]$Project,
    [string]$Transcript,
    [string]$Reply = '',
    [string]$UserHome,
    [string]$PluginRoot = 'C:\fake-plugin-cache\code-handoff\0.0.0',
    [string]$Session = 'test-session',
    [switch]$NoWait
  )
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:PowerShellExe
  $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:HandoffScript + '"'
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = $Project   # Claude Code runs hooks in the project folder
  $psi.RedirectStandardInput = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $UserHome
  $psi.EnvironmentVariables['CLAUDE_PROJECT_DIR'] = $Project
  if ($PluginRoot) { $psi.EnvironmentVariables['CLAUDE_PLUGIN_ROOT'] = $PluginRoot }
  elseif ($psi.EnvironmentVariables.ContainsKey('CLAUDE_PLUGIN_ROOT')) { $psi.EnvironmentVariables.Remove('CLAUDE_PLUGIN_ROOT') }
  $json = @{ session_id = $Session; transcript_path = $Transcript; cwd = $Project; last_assistant_message = $Reply } | ConvertTo-Json -Compress
  $proc = [System.Diagnostics.Process]::Start($psi)
  $proc.StandardInput.Write($json)
  $proc.StandardInput.Close()
  if ($NoWait) { return $proc }
  $proc.WaitForExit()
  $code = $proc.ExitCode
  $proc.Dispose()
  return $code
}

# Runs the hook for turn $n of a simple transcript.
function Invoke-SimpleTurn($project, $n, $userHome) {
  $tp = New-SimpleTranscript $project $n
  return (Invoke-Handoff -Project $project -Transcript $tp -Reply "reply $n" -UserHome $userHome)
}

function Get-HandoffFile($project, $name) {
  $p = Join-Path $project ".claude\handoff\$name"
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return [System.IO.File]::ReadAllText($p, $script:Utf8)
}
function Get-LogLines($project) {
  $log = Join-Path $project '.claude\handoff\hook-error.log'
  if (-not (Test-Path -LiteralPath $log)) { return ,@() }
  return ,@([System.IO.File]::ReadAllLines($log) | Where-Object { $_ })
}
function Get-MatchCount($lines, $pattern) { return @($lines | Where-Object { $_ -match $pattern }).Count }
function Test-TurnWritten($project, $n) {
  $last = Get-HandoffFile $project 'last.md'
  return ($null -ne $last) -and ($last -match "test prompt $n")
}
function Get-TurnCount($project) {
  $h = Get-HandoffFile $project 'history.md'
  if (-not $h) { return 0 }
  return ([regex]::Matches($h, '# Claude Code - latest turn')).Count
}

# The mutex name handoff.ps1 uses for a project (same formula as the script).
function Get-HandoffMutexName($project) {
  $handoff = Join-Path $project '.claude\handoff'
  $sha = [System.Security.Cryptography.SHA1]::Create()
  $hex = ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($handoff.ToLowerInvariant())))) -replace '-', ''
  return 'Local\claude-handoff-' + $hex
}

# Runs two simple turns and collects what the tests check.
function Invoke-TwoRuns($project, $userHome) {
  $e1 = Invoke-SimpleTurn $project 1 $userHome
  $l1 = Get-LogLines $project
  $t1 = Test-TurnWritten $project 1
  $e2 = Invoke-SimpleTurn $project 2 $userHome
  $l2 = Get-LogLines $project
  $t2 = Test-TurnWritten $project 2
  return [pscustomobject]@{ Exit1 = $e1; Exit2 = $e2; Turn1 = $t1; Turn2 = $t2; Log1 = $l1; Log2 = $l2 }
}
