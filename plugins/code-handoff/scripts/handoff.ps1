# handoff.ps1 - Claude Code Stop hook.
# After every Claude Code turn, writes a readable summary to .claude/handoff/ so a
# planning chat can read what Claude Code did without screenshots.
#   handoff/last.md          latest turn (prompt, reply, files changed, commands, errors)
#   handoff/history.md       every turn appended, newest at the bottom
#   handoff/transcript.jsonl copy of the latest session's full transcript
# Installed at user level, so it runs for every project. Always exits 0 so it can never block Claude Code.

$ErrorActionPreference = 'Stop'
$handoff = $null
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
  if (-not (Test-Path -LiteralPath $gi)) { [System.IO.File]::WriteAllText($gi, "*`n", $utf8) }

  # Serialise runs for this project: Claude Code can fire the Stop hook twice for one turn.
  $mutex = New-Object System.Threading.Mutex($false, ('Local\claude-handoff-' + (Sha1Hex $handoff.ToLowerInvariant())))
  try { $null = $mutex.WaitOne(30000) } catch { }   # an abandoned mutex still counts as acquired

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
  if ((Test-Path -LiteralPath $keyFile) -and ([System.IO.File]::ReadAllText($keyFile).Trim() -eq $turnKey)) { exit 0 }

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
}
catch {
  try {
    if (-not $handoff) { exit 0 }
    $log = Join-Path $handoff 'hook-error.log'
    [System.IO.File]::AppendAllText($log, "$(Get-Date -Format s) $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))`r`n", $utf8)
  } catch {}
}
exit 0
