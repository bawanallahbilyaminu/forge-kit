# handoff.ps1 - Claude Code Stop hook.
# After every Claude Code turn, writes a readable summary to .claude/handoff/ so a
# planning chat can read what Claude Code did without screenshots.
#   handoff/last.md          latest turn (prompt, reply, files changed, commands, errors)
#   handoff/history.md       every turn appended, newest at the bottom
#   handoff/transcript.jsonl copy of the latest session's full transcript
# Installed at user level, so it runs for every project. Always exits 0 so it can never block Claude Code.
# Runs as the code-handoff plugin (CLAUDE_PLUGIN_ROOT set) or as a copy placed by
# installers\windows\install.ps1. If another handoff.ps1 Stop hook is active (the installer's
# in the user's settings.json, or an old per-project one in the project's settings.json or
# settings.local.json) and its script exists, the plugin copy steps aside. A hook whose
# script is missing is noted once and ignored. The plugin copy also notes, once, any
# leftover files from the old per-project setup.

$ErrorActionPreference = 'Stop'
$handoff = $null
$mutex = $null
$locked = $false
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Clip($s, $n) {
  if ($null -eq $s) { return '' }
  $s = [string]$s
  if ($s.Length -gt $n) { return $s.Substring(0, $n) + ' ...[truncated]' }
  return $s
}
function Sha1Hex($text) {
  $sha = [System.Security.Cryptography.SHA1]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$text)))) -replace '-', ''
}
# Expands one path token from a hook command into a full Windows path, or $null if it can't.
# Handles quotes, forward slashes, ~, %USERPROFILE%, $env:USERPROFILE, ${CLAUDE_PROJECT_DIR},
# $CLAUDE_PROJECT_DIR, Git Bash /c/... paths and paths relative to the project dir.
function ExpandHookPath($t, $projectDir) {
  try {
    $t = ([string]$t).Trim().TrimEnd(';').Trim('"', "'")
    if (-not $t) { return $null }
    $userHome = [string]$env:USERPROFILE
    $pairs = @(
      @('\$\{CLAUDE_PROJECT_DIR\}', $projectDir), @('\$env:CLAUDE_PROJECT_DIR', $projectDir),
      @('\$CLAUDE_PROJECT_DIR', $projectDir), @('%CLAUDE_PROJECT_DIR%', $projectDir),
      @('\$\{USERPROFILE\}', $userHome), @('\$env:USERPROFILE', $userHome),
      @('\$USERPROFILE', $userHome), @('%USERPROFILE%', $userHome),
      @('\$\{HOME\}', $userHome), @('\$env:HOME', $userHome), @('\$HOME', $userHome)
    )
    foreach ($pr in $pairs) {
      if ($t -match $pr[0]) {
        $val = [string]$pr[1]
        if (-not $val) { return $null }
        $t = [regex]::Replace($t, $pr[0], $val.Replace('$', '$$'), 'IgnoreCase')
      }
    }
    if ($t -match '^~([\\/]|$)') {
      if (-not $userHome) { return $null }
      $t = $userHome + $t.Substring(1)
    }
    if ($t -match '^/([a-zA-Z])/') { $t = $t.Substring(1, 1) + ':' + $t.Substring(2) }   # Git Bash /c/...
    if ($t -match '\$|%[^%]+%') { return $null }   # a variable we don't know
    $t = $t -replace '/', '\'
    if (-not [System.IO.Path]::IsPathRooted($t)) {
      if (-not $projectDir) { return $null }
      $t = Join-Path $projectDir $t
    }
    return $t
  } catch { return $null }
}
# Finds the handoff.ps1 path in a hook's command ($parts[0]) and args (the rest) and expands
# it, or $null.
function HookScriptPath($parts, $projectDir) {
  for ($i = 0; $i -lt $parts.Count; $i++) {
    $p = [string]$parts[$i]
    if (-not $p -or $p -notmatch '(?i)handoff\.ps1') { continue }
    # An exec-form arg (not the command string) that is the whole path, possibly with spaces
    if ($i -gt 0 -and $p.Trim().Trim('"', "'") -match '(?i)handoff\.ps1$') {
      $x = ExpandHookPath $p $projectDir
      if ($x) { return $x }
    }
    # Otherwise a token of a shell command string, quoted or not
    foreach ($m in [regex]::Matches($p, '"([^"]*)"|''([^'']*)''|(\S+)')) {
      $tok = $m.Groups[1].Value
      if (-not $tok) { $tok = $m.Groups[2].Value }
      if (-not $tok) { $tok = $m.Groups[3].Value }
      $tok = $tok.Trim().TrimEnd(';').Trim('"', "'")
      if ($tok -match '(?i)handoff\.ps1$') { return (ExpandHookPath $tok $projectDir) }
    }
  }
  return $null
}
# Looks in the settings file at $sp for Stop hooks running a handoff.ps1 that is not this
# plugin's copy: the installer's copy (user settings.json) or an old per-project copy
# (project settings.json or settings.local.json). Returns:
#   'active'  at least one such hook runs a script that exists
#   'stale'   there are such hooks, but none of their scripts exists or can be resolved
#   'none'    no such hook, no file, or bad JSON
function ForeignHandoffHook($sp, $pluginRoot, $projectDir) {
  try {
    if (-not $sp -or -not (Test-Path -LiteralPath $sp)) { return 'none' }
    $s = [System.IO.File]::ReadAllText($sp) | ConvertFrom-Json
    if (-not $s -or -not $s.hooks) { return 'none' }
    $root = (([string]$pluginRoot) -replace '\\', '/').TrimEnd('/').ToLowerInvariant()
    $foundAny = $false
    foreach ($g in @($s.hooks.Stop)) {
      if (-not $g) { continue }
      foreach ($h in @($g.hooks)) {
        if (-not $h) { continue }
        $parts = @([string]$h.command)
        if ($h.args) { foreach ($a in @($h.args)) { $parts += [string]$a } }
        $c = (($parts -join ' ') -replace '\\', '/').ToLowerInvariant()
        if ($c -notmatch 'handoff\.ps1') { continue }
        if ($c.Contains('claude_plugin_root')) { continue }
        if ($root -and $c.Contains($root)) { continue }
        $foundAny = $true
        $script = HookScriptPath $parts $projectDir
        $exists = $false
        if ($script) { try { $exists = Test-Path -LiteralPath $script -PathType Leaf } catch { $exists = $false } }
        if ($exists) { return 'active' }
      }
    }
    if ($foundAny) { return 'stale' }
  } catch { }
  return 'none'
}
function TextOf($content) {
  if ($null -eq $content) { return '' }
  if ($content -is [string]) { return $content }
  return (@($content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n")
}

try {
  [Console]::InputEncoding = [System.Text.Encoding]::UTF8
  $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json

  # Installed once for all projects: write into the current project's .claude\handoff
  $projectDir = [string]$env:CLAUDE_PROJECT_DIR
  if (-not $projectDir) { $projectDir = [string]$hook.cwd }
  if (-not $projectDir) { exit 0 }
  if ((Resolve-Path -LiteralPath $projectDir).Path.TrimEnd('\') -eq $env:USERPROFILE.TrimEnd('\')) { exit 0 }  # skip the home folder
  $handoff = Join-Path $projectDir '.claude\handoff'
  New-Item -ItemType Directory -Force -Path $handoff | Out-Null
  $gi = Join-Path $handoff '.gitignore'
  if (-not (Test-Path -LiteralPath $gi)) {
    # Two first runs in a new project can race here. If this write fails but the file now
    # exists, the other run wrote it: ignore that. Anything else goes to the outer catch.
    try { [System.IO.File]::WriteAllText($gi, "*`n", $utf8) }
    catch { if (-not (Test-Path -LiteralPath $gi)) { throw } }
  }

  if ($env:CLAUDE_PLUGIN_ROOT) {
    # Leftovers from the old per-project setup: note them once. Never delete, never skip for these.
    try {
      $leftMarker = Join-Path $handoff '.leftovers-noted'
      if (-not (Test-Path -LiteralPath $leftMarker)) {
        $found = @()
        foreach ($rel in @('.claude\commands\next.md', '.claude\hooks\handoff.ps1', '.claude\handoff-kit')) {
          if (Test-Path -LiteralPath (Join-Path $projectDir $rel)) { $found += $rel }
        }
        if ($found.Count -gt 0) {
          $note = "$(Get-Date -Format s) Found leftovers from the old per-project code-handoff setup in this project: " +
                  ($found -join ', ') + ". The code-handoff plugin now provides the hook and the command " +
                  "(/code-handoff:next), so these can be deleted. If a Stop hook in .claude\settings.json or " +
                  ".claude\settings.local.json still runs handoff.ps1, remove that hook entry first. Keep .claude\handoff\. " +
                  "See 'Upgrading from the per-project setup' in the code-handoff README. Nothing was deleted, and turns are still written.`r`n"
          [System.IO.File]::AppendAllText((Join-Path $handoff 'hook-error.log'), $note, $utf8)
          [System.IO.File]::WriteAllText($leftMarker, (Get-Date -Format s), $utf8)
        }
      }
    } catch { }

    # Double install: if another handoff.ps1 Stop hook is active and its script exists, let
    # that copy write the turn and stop here (before the mutex). A hook whose script is
    # missing can't write anything, so note it once and carry on writing the turn here.
    # Checked in order: user, project, project local.
    $userSettings = $null
    if ($env:USERPROFILE) { $userSettings = Join-Path $env:USERPROFILE '.claude\settings.json' }
    $sources = @(
      @{ Path = $userSettings; Marker = '.double-install-noted'; StaleMarker = '.stale-hook-noted-user'; Kind = 'user'; Label = '%USERPROFILE%\.claude\settings.json' },
      @{ Path = (Join-Path $projectDir '.claude\settings.json'); Marker = '.project-hook-noted'; StaleMarker = '.stale-hook-noted-project'; Kind = '.claude\settings.json'; Label = "this project's .claude\settings.json" },
      @{ Path = (Join-Path $projectDir '.claude\settings.local.json'); Marker = '.project-local-hook-noted'; StaleMarker = '.stale-hook-noted-local'; Kind = '.claude\settings.local.json'; Label = "this project's .claude\settings.local.json" }
    )
    foreach ($src in $sources) {
      $state = ForeignHandoffHook $src.Path $env:CLAUDE_PLUGIN_ROOT $projectDir
      if ($state -eq 'none') { continue }
      if ($state -eq 'stale') {
        try {
          $staleMarker = Join-Path $handoff $src.StaleMarker
          if (-not (Test-Path -LiteralPath $staleMarker)) {
            $note = "$(Get-Date -Format s) A Stop hook in $($src.Label) runs a handoff.ps1 that doesn't exist, or whose path can't be resolved. " +
                    "The plugin copy ignores that hook and writes each turn itself. The hook fails on every turn, so remove that " +
                    "handoff.ps1 entry from $($src.Label) and keep its other settings. " +
                    "See 'Upgrading from the per-project setup' in the code-handoff README.`r`n"
            [System.IO.File]::AppendAllText((Join-Path $handoff 'hook-error.log'), $note, $utf8)
            [System.IO.File]::WriteAllText($staleMarker, (Get-Date -Format s), $utf8)
          }
        } catch { }
        continue
      }
      $marker = Join-Path $handoff $src.Marker
      if (-not (Test-Path -LiteralPath $marker)) {
        if ($src.Kind -eq 'user') {
          $note = "$(Get-Date -Format s) code-handoff is installed twice: as the Claude Code plugin and by installers\windows\install.ps1 " +
                  "(Stop hook in %USERPROFILE%\.claude\settings.json). The plugin copy now skips so each turn is written once. " +
                  "To keep only the plugin, run 'powershell -ExecutionPolicy Bypass -File installers\windows\install.ps1 -Uninstall' " +
                  "from the forge-kit repo, or remove the handoff.ps1 Stop hook from %USERPROFILE%\.claude\settings.json.`r`n"
        } else {
          $note = "$(Get-Date -Format s) code-handoff is installed twice: as the Claude Code plugin and as a per-project Stop hook " +
                  "in this project's $($src.Kind). The plugin copy now skips so each turn is written once by the project copy. " +
                  "To keep only the plugin, remove the handoff.ps1 Stop hook entry from $($src.Kind) and keep its other settings. " +
                  "If you delete that hook's script but keep the entry, the plugin notices and writes the turns itself. " +
                  "See 'Upgrading from the per-project setup' in the code-handoff README.`r`n"
        }
        [System.IO.File]::AppendAllText((Join-Path $handoff 'hook-error.log'), $note, $utf8)
        [System.IO.File]::WriteAllText($marker, (Get-Date -Format s), $utf8)
      }
      exit 0
    }
  }

  # Serialise runs for this project: Claude Code can fire the Stop hook twice for one turn.
  # Released in the outer finally, which every path after this point goes through.
  $mutex = New-Object System.Threading.Mutex($false, ('Local\claude-handoff-' + (Sha1Hex $handoff.ToLowerInvariant())))
  try { $locked = $mutex.WaitOne(30000) }
  catch {
    # AbandonedMutexException: the previous holder exited without releasing; we now own it.
    $ex = $_.Exception
    if ($ex -is [System.Threading.AbandonedMutexException] -or $ex.InnerException -is [System.Threading.AbandonedMutexException]) { $locked = $true }
  }
  if (-not $locked) {
    [System.IO.File]::AppendAllText((Join-Path $handoff 'hook-error.log'), "$(Get-Date -Format s) mutex wait timed out, continuing without lock`r`n", $utf8)
  }

  Start-Sleep -Seconds 2   # the transcript is written asynchronously; give it a moment

  # --- read the transcript (shared access, Claude Code may still be writing) ---
  $all = ''
  $tp = [string]$hook.transcript_path
  if ($tp -and (Test-Path -LiteralPath $tp)) {
    $fs = [System.IO.File]::Open($tp, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
    $all = $sr.ReadToEnd(); $sr.Close()
  }
  $lines = $all -split "`n"

  # --- walk back to the last real user prompt ---
  $events = New-Object System.Collections.ArrayList
  $prompt = ''
  $scanned = 0
  for ($i = $lines.Count - 1; $i -ge 0 -and $scanned -lt 5000; $i--) {
    $l = $lines[$i].Trim()
    if (-not $l) { continue }
    $scanned++
    try { $e = $l | ConvertFrom-Json } catch { continue }
    if ($e.isSidechain) { continue }
    if ($e.type -eq 'user' -and -not $e.isMeta) {
      $c = $e.message.content
      $isToolResult = $false
      if (-not ($c -is [string])) { $isToolResult = @($c | Where-Object { $_.type -eq 'tool_result' }).Count -gt 0 }
      if (-not $isToolResult) {
        $t = TextOf $c
        if ($t -and $t -notmatch '^\s*(<local-command|<system-reminder|\[Request interrupted)') { $prompt = $t; break }
      }
    }
    [void]$events.Insert(0, $e)
  }

  # --- collect what happened after the prompt ---
  $edited = [ordered]@{}
  $commands = New-Object System.Collections.ArrayList
  $errors = New-Object System.Collections.ArrayList
  $texts = New-Object System.Collections.ArrayList
  $toolCounts = @{}
  $toolLabel = @{}
  foreach ($e in $events) {
    $c = $e.message.content
    if ($null -eq $c -or $c -is [string]) { continue }
    if ($e.type -eq 'assistant') {
      foreach ($b in $c) {
        if ($b.type -eq 'text' -and $b.text) { [void]$texts.Add([string]$b.text) }
        elseif ($b.type -eq 'tool_use') {
          $n = [string]$b.name
          if ($toolCounts.ContainsKey($n)) { $toolCounts[$n]++ } else { $toolCounts[$n] = 1 }
          $inp = $b.input
          $label = $n
          if ($n -in @('Edit', 'Write', 'MultiEdit', 'NotebookEdit')) {
            $p = [string]$inp.file_path
            if (-not $p) { $p = [string]$inp.notebook_path }
            if ($p) { $edited[$p] = $n }
            $label = "$n $p"
          }
          elseif ($n -in @('Bash', 'PowerShell')) {
            [void]$commands.Add((Clip $inp.command 300))
            $label = "${n}: " + (Clip $inp.command 120)
          }
          elseif ($inp.file_path) { $label = "$n $($inp.file_path)" }
          elseif ($inp.pattern) { $label = "$n $($inp.pattern)" }
          $toolLabel[[string]$b.id] = $label
        }
      }
    }
    elseif ($e.type -eq 'user') {
      foreach ($b in $c) {
        if ($b.type -eq 'tool_result' -and $b.is_error) {
          $what = $toolLabel[[string]$b.tool_use_id]
          if (-not $what) { $what = 'tool' }
          $msg = (Clip (TextOf $b.content) 500) -replace "`r?`n", ' '
          [void]$errors.Add("- **$what** -> $msg")
        }
      }
    }
  }

  $reply = [string]$hook.last_assistant_message
  if (-not $reply -and $texts.Count -gt 0) { $reply = $texts[$texts.Count - 1] }
  if (-not $prompt) { $prompt = '(not found in transcript)' }

  # --- skip a turn that was already written (duplicate hook run) ---
  $turnKey = Sha1Hex ("$($hook.session_id)|$prompt|$reply")
  $keyFile = Join-Path $handoff '.last-turn'
  $duplicate = (Test-Path -LiteralPath $keyFile) -and ([System.IO.File]::ReadAllText($keyFile).Trim() -eq $turnKey)
  if (-not $duplicate) {

    # --- build the markdown ---
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Claude Code - latest turn')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- **When:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("- **Session:** $($hook.session_id)")
    [void]$sb.AppendLine("- **Working dir:** $($hook.cwd)")
    if ($toolCounts.Count -gt 0) {
      $summary = ($toolCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "$($_.Key) x$($_.Value)" }) -join ', '
      [void]$sb.AppendLine("- **Tools used:** $summary")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Prompt'); [void]$sb.AppendLine(''); [void]$sb.AppendLine((Clip $prompt 6000)); [void]$sb.AppendLine('')
    if ($texts.Count -gt 1) {
      [void]$sb.AppendLine('## Progress notes along the way'); [void]$sb.AppendLine('')
      for ($k = 0; $k -lt $texts.Count - 1; $k++) { [void]$sb.AppendLine('- ' + ((Clip $texts[$k] 400) -replace "`r?`n", ' ')) }
      [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('## Final reply'); [void]$sb.AppendLine(''); [void]$sb.AppendLine((Clip $reply 12000)); [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## Files changed ($($edited.Count))"); [void]$sb.AppendLine('')
    foreach ($k in $edited.Keys) { [void]$sb.AppendLine("- $k ($($edited[$k]))") }
    if ($edited.Count -eq 0) { [void]$sb.AppendLine('- none') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## Commands run ($($commands.Count))"); [void]$sb.AppendLine('')
    if ($commands.Count -gt 0) {
      [void]$sb.AppendLine('```')
      foreach ($cmd in $commands) { [void]$sb.AppendLine($cmd) }
      [void]$sb.AppendLine('```')
    } else { [void]$sb.AppendLine('- none') }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## Errors ($($errors.Count))"); [void]$sb.AppendLine('')
    foreach ($er in $errors) { [void]$sb.AppendLine($er) }
    if ($errors.Count -eq 0) { [void]$sb.AppendLine('- none') }
    $md = $sb.ToString()

    # --- write outputs ---
    [System.IO.File]::WriteAllText((Join-Path $handoff 'last.md'), $md, $utf8)
    $hist = Join-Path $handoff 'history.md'
    [System.IO.File]::AppendAllText($hist, "`n`n---`n`n" + $md, $utf8)
    if ((Get-Item -LiteralPath $hist).Length -gt 600KB) {
      $h = [System.IO.File]::ReadAllText($hist, $utf8)
      [System.IO.File]::WriteAllText($hist, $h.Substring($h.Length - 400000), $utf8)
    }
    [System.IO.File]::WriteAllText($keyFile, $turnKey, $utf8)
    if ($all) {
      try { [System.IO.File]::WriteAllText((Join-Path $handoff 'transcript.jsonl'), $all, $utf8) } catch { }
    }
  }   # end if (-not $duplicate)
}
catch {
  try {
    if ($handoff) {
      $log = Join-Path $handoff 'hook-error.log'
      [System.IO.File]::AppendAllText($log, "$(Get-Date -Format s) $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))`r`n", $utf8)
    }
  } catch {}
}
finally {
  if ($mutex) {
    if ($locked) { try { $mutex.ReleaseMutex() } catch {} }
    try { $mutex.Dispose() } catch {}
  }
}
exit 0
