# GitGuardTestHelpers.ps1 - helpers for git-guard.Tests.ps1 (Pester 3.4.0, Windows PowerShell 5.1).
# Tests the shipped template, plugins/idea-forge/skills/idea-code-setup/templates/git-guard.ps1,
# by running it in a child powershell.exe with the Stop hook JSON on stdin, the way Claude Code
# does. Repos are temporary, their remote is a local bare repo (no network), the git identity is
# set in each temp repo's own config, and the user's global and system git config are ignored.

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:GitGuardScript = Join-Path $script:RepoRoot 'plugins\idea-forge\skills\idea-code-setup\templates\git-guard.ps1'
# For a deliberate-break check, point this at a modified temp copy instead of the real file.
if ($env:GIT_GUARD_UNDER_TEST) { $script:GitGuardScript = $env:GIT_GUARD_UNDER_TEST }
$script:PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function New-GuardTestRoot {
  $p = Join-Path ([System.IO.Path]::GetTempPath()) ('forge-kit-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 12))
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  # An empty global git config, so the user's settings (signing, hooks, untracked-file display)
  # can't change what git status reports.
  [System.IO.File]::WriteAllText((Join-Path $p 'empty.gitconfig'), '', $script:Utf8)
  return $p
}
function Remove-GuardTestRoot($root) {
  if ($root -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

# Sets the git environment for this process (setup commands) and returns the old values.
function Enter-GitSandbox($root) {
  $names = @('GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM', 'GIT_CEILING_DIRECTORIES', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')
  $saved = @{}
  foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
  [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', (Join-Path $root 'empty.gitconfig'), 'Process')
  [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1', 'Process')
  [Environment]::SetEnvironmentVariable('GIT_CEILING_DIRECTORIES', $root, 'Process')
  foreach ($n in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')) { [Environment]::SetEnvironmentVariable($n, $null, 'Process') }
  return $saved
}
function Exit-GitSandbox($saved) {
  if (-not $saved) { return }
  foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
}

# Runs git in $dir and throws if it fails. Native stderr must not throw in 5.1, hence SilentlyContinue.
function Invoke-TestGit {
  param([string]$Dir, [Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  $ErrorActionPreference = 'SilentlyContinue'
  $out = & git -C $Dir @GitArgs 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in $Dir ($LASTEXITCODE): $out" }
  return $out
}
function Set-TestFile($path, $text) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  [System.IO.File]::WriteAllText($path, $text, $script:Utf8)
}

# A repo on branch main with one commit, no remote.
function New-TestRepo($root, $name) {
  $repo = Join-Path $root $name
  New-Item -ItemType Directory -Force -Path $repo | Out-Null
  Invoke-TestGit $repo init -q -b main | Out-Null
  Invoke-TestGit $repo config user.name 'Test User' | Out-Null
  Invoke-TestGit $repo config user.email 'test@example.invalid' | Out-Null
  Invoke-TestGit $repo config commit.gpgsign false | Out-Null
  Set-TestFile (Join-Path $repo 'README.md') "test repo`n"
  Invoke-TestGit $repo add README.md | Out-Null
  Invoke-TestGit $repo commit -q -m 'initial commit' | Out-Null
  return $repo
}
# A repo like New-TestRepo, pushed to a local bare remote, with main tracking origin/main.
function New-TestRepoWithRemote($root, $name) {
  $bare = Join-Path $root "$name-remote.git"
  New-Item -ItemType Directory -Force -Path $bare | Out-Null
  Invoke-TestGit $bare init -q --bare -b main | Out-Null
  $repo = New-TestRepo $root $name
  Invoke-TestGit $repo remote add origin $bare | Out-Null
  Invoke-TestGit $repo push -q -u origin main | Out-Null
  return $repo
}
function Add-TestCommit($repo, $file, $message) {
  Set-TestFile (Join-Path $repo $file) "$message`n"
  Invoke-TestGit $repo add $file | Out-Null
  Invoke-TestGit $repo commit -q -m $message | Out-Null
}

# Runs git-guard.ps1 once. Returns ExitCode and Stderr. -NoProjectDir leaves CLAUDE_PROJECT_DIR
# unset, so the script falls back to "cwd" in the hook input. -RawInput sends that text as is.
# ($RawInput is untyped on purpose: a [string] parameter would turn $null into ''.)
function Invoke-GitGuard {
  param(
    [string]$Dir,
    [object]$StopHookActive = $false,
    [switch]$NoProjectDir,
    $RawInput = $null,
    [string]$Root
  )
  $ProjectDir = $Dir
  if ($NoProjectDir) { $ProjectDir = '' }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:PowerShellExe
  $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:GitGuardScript + '"'
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = $Dir
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardError = $true
  $vars = $psi.EnvironmentVariables
  if ($ProjectDir) { $vars['CLAUDE_PROJECT_DIR'] = $ProjectDir }
  elseif ($vars.ContainsKey('CLAUDE_PROJECT_DIR')) { $vars.Remove('CLAUDE_PROJECT_DIR') }
  $vars['GIT_CONFIG_GLOBAL'] = (Join-Path $Root 'empty.gitconfig')
  $vars['GIT_CONFIG_NOSYSTEM'] = '1'
  $vars['GIT_CEILING_DIRECTORIES'] = $Root
  foreach ($n in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')) { if ($vars.ContainsKey($n)) { $vars.Remove($n) } }
  if ($null -ne $RawInput) { $json = $RawInput }
  else { $json = @{ session_id = 'test-session'; stop_hook_active = $StopHookActive; cwd = $Dir; hook_event_name = 'Stop' } | ConvertTo-Json -Compress }
  $proc = [System.Diagnostics.Process]::Start($psi)
  $proc.StandardInput.Write($json)
  $proc.StandardInput.Close()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()
  $r = [pscustomobject]@{ ExitCode = $proc.ExitCode; Stderr = $stderr.Trim() }
  $proc.Dispose()
  return $r
}
