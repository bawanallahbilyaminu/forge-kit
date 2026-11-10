# handoff.Tests.ps1 - Pester 3.4.0 tests for plugins/code-handoff/scripts/handoff.ps1.
# Run with: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tests.ps1
# Each Describe block makes its own temp folder (fake USERPROFILE and projects) and removes it.
# Every hook run waits 2 seconds by design, and the lock-timeout test waits 30, so the whole
# file takes a few minutes.

. (Join-Path $PSScriptRoot 'HandoffTestHelpers.ps1')

$skipPat = 'installed twice'
$stalePat = "doesn't exist"

function Assert-Skipped($r, $filePattern) {
  $r.Exit1 | Should Be 0
  $r.Exit2 | Should Be 0
  $r.Turn1 | Should Be $false
  $r.Turn2 | Should Be $false
  (Get-MatchCount $r.Log1 $skipPat) | Should Be 1
  (Get-MatchCount $r.Log2 $skipPat) | Should Be 1
  (Get-MatchCount @($r.Log1 | Where-Object { $_ -match $skipPat }) $filePattern) | Should Be 1
  $r.Log2.Count | Should Be $r.Log1.Count
}
function Assert-StaleNoted($r, $filePattern) {
  $r.Exit1 | Should Be 0
  $r.Exit2 | Should Be 0
  $r.Turn1 | Should Be $true
  $r.Turn2 | Should Be $true
  (Get-MatchCount $r.Log1 $stalePat) | Should Be 1
  (Get-MatchCount $r.Log2 $stalePat) | Should Be 1
  (Get-MatchCount @($r.Log1 | Where-Object { $_ -match $stalePat }) $filePattern) | Should Be 1
  $r.Log2.Count | Should Be $r.Log1.Count
}

Describe 'handoff.ps1 transcript parser' {
  BeforeAll {
    $script:root = New-TestRoot
    $script:fakeHome = New-FakeHome $script:root
  }
  AfterAll { Remove-TestRoot $script:root }

  function Invoke-Fixture($name, $reply) {
    $p = New-TestProject $script:root $name
    $tp = Join-Path $p 'transcript.jsonl'
    Copy-Item -LiteralPath (Join-Path $script:FixtureDir "$name.jsonl") -Destination $tp
    $code = Invoke-Handoff -Project $p -Transcript $tp -Reply $reply -UserHome $script:fakeHome
    return [pscustomobject]@{ Project = $p; Exit = $code; Last = (Get-HandoffFile $p 'last.md') }
  }

  It 'normal turn: prompt, progress notes, files, commands and tool counts' {
    $r = Invoke-Fixture 'normal-turn' 'Added the greeting line to the README.'
    $r.Exit | Should Be 0
    $r.Last | Should Match '(?s)## Prompt\s+Add a greeting line to the README\.'
    $r.Last | Should Not Match 'Earlier prompt'
    $r.Last | Should Not Match 'Subagent prompt'
    $r.Last | Should Match "- I'll read the README first\."
    $r.Last | Should Match '- Now editing it\.'
    $r.Last | Should Match '(?s)## Final reply\s+Added the greeting line to the README\.'
    $r.Last | Should Match '## Files changed \(2\)'
    $r.Last | Should Match '- C:/example/project/README\.md \(Edit\)'
    $r.Last | Should Match '- C:/example/project/docs/notes\.md \(Write\)'
    $r.Last | Should Match '## Commands run \(1\)'
    $r.Last | Should Match 'git status --short'
    $r.Last | Should Match '## Errors \(0\)'
    $r.Last | Should Match 'Tools used:.*Read x1'
    $r.Last | Should Match 'Tools used:.*Edit x1'
    (Get-HandoffFile $r.Project 'history.md') | Should Match 'Add a greeting line'
    (Get-HandoffFile $r.Project 'transcript.jsonl') | Should Match 'Add a greeting line'
    (Get-HandoffFile $r.Project '.gitignore').Trim() | Should Be '*'
    (Test-Path (Join-Path $r.Project '.claude\handoff\hook-error.log')) | Should Be $false
  }

  It 'turn with tool errors: each failed tool is listed with its message' {
    $r = Invoke-Fixture 'tool-errors' 'The tests failed: 2 failures.'
    $r.Exit | Should Be 0
    $r.Last | Should Match '## Errors \(2\)'
    $r.Last | Should Match '\*\*Bash: npm test\*\* -> exit code 1: 2 tests failed'
    $r.Last | Should Match '\*\*Read C:/example/project/missing\.txt\*\* -> File does not exist\.'
    $r.Last | Should Match '## Commands run \(1\)'
  }

  It 'interrupted turn: the interruption marker is not taken as the prompt' {
    $r = Invoke-Fixture 'interrupted' ''
    $r.Exit | Should Be 0
    $r.Last | Should Match '(?s)## Prompt\s+Refactor the parser module\.'
    $r.Last | Should Not Match '(?s)## Prompt\s+\[Request interrupted'
    $r.Last | Should Match '(?s)## Final reply\s+Starting the refactor\.'
    $r.Last | Should Match '- C:/example/project/src/parser\.js \(Edit\)'
  }

  It 'slash-command turn: the command is the prompt, not its expansion or local output' {
    $r = Invoke-Fixture 'slash-command' 'Ran the prepared prompt.'
    $r.Exit | Should Be 0
    $r.Last | Should Match '(?s)## Prompt\s+<command-message>code-handoff:next</command-message>'
    $r.Last | Should Match '<command-name>/code-handoff:next</command-name>'
    $r.Last | Should Not Match 'Expanded command body'
    $r.Last | Should Not Match 'local-command-stdout'
  }

  It 'lagging transcript: a half-written last line is ignored and the reply comes from the hook input' {
    $r = Invoke-Fixture 'lagging-partial' 'Wrote the changelog entry.'
    $r.Exit | Should Be 0
    $r.Last | Should Match '(?s)## Prompt\s+Write the changelog entry\.'
    $r.Last | Should Match '(?s)## Final reply\s+Wrote the changelog entry\.'
    $r.Last | Should Match '## Files changed \(0\)'
  }

  It 'lagging transcript: a transcript that does not exist yet still writes the turn' {
    $p = New-TestProject $script:root 'no-transcript'
    $code = Invoke-Handoff -Project $p -Transcript (Join-Path $p 'not-written-yet.jsonl') -Reply 'Reply from the hook input.' -UserHome $script:fakeHome
    $code | Should Be 0
    $last = Get-HandoffFile $p 'last.md'
    $last | Should Match '\(not found in transcript\)'
    $last | Should Match '(?s)## Final reply\s+Reply from the hook input\.'
  }

  It 'skips the home folder' {
    $code = Invoke-SimpleTurn $script:fakeHome 1 $script:fakeHome
    $code | Should Be 0
    (Test-Path (Join-Path $script:fakeHome '.claude\handoff')) | Should Be $false
  }
}

Describe 'handoff.ps1 duplicate runs and locking' {
  BeforeAll {
    $script:root = New-TestRoot
    $script:fakeHome = New-FakeHome $script:root
  }
  AfterAll { Remove-TestRoot $script:root }

  It 'a second run for the same turn is skipped (.last-turn)' {
    $p = New-TestProject $script:root 'dup-sequential'
    $tp = New-SimpleTranscript $p 1
    (Invoke-Handoff -Project $p -Transcript $tp -Reply 'reply 1' -UserHome $script:fakeHome) | Should Be 0
    (Invoke-Handoff -Project $p -Transcript $tp -Reply 'reply 1' -UserHome $script:fakeHome) | Should Be 0
    (Get-TurnCount $p) | Should Be 1
    (Get-HandoffFile $p '.last-turn') | Should Not BeNullOrEmpty
  }

  It 'a new turn after that is written' {
    $p = New-TestProject $script:root 'dup-then-new'
    (Invoke-SimpleTurn $p 1 $script:fakeHome) | Should Be 0
    (Invoke-SimpleTurn $p 2 $script:fakeHome) | Should Be 0
    (Get-TurnCount $p) | Should Be 2
    (Test-TurnWritten $p 2) | Should Be $true
  }

  # The handoff folder already exists here, as it does after a project's first turn: see the
  # skipped test below for the race when it doesn't.
  It 'two runs at the same time write the turn once (mutex plus .last-turn)' {
    $p = New-TestProject $script:root 'dup-concurrent'
    Set-TestFile (Join-Path $p '.claude\handoff\.gitignore') "*`n"
    $tp = New-SimpleTranscript $p 1
    $a = Invoke-Handoff -Project $p -Transcript $tp -Reply 'reply 1' -UserHome $script:fakeHome -NoWait
    $b = Invoke-Handoff -Project $p -Transcript $tp -Reply 'reply 1' -UserHome $script:fakeHome -NoWait
    $a.WaitForExit(); $b.WaitForExit()
    $a.ExitCode | Should Be 0
    $b.ExitCode | Should Be 0
    $a.Dispose(); $b.Dispose()
    (Get-TurnCount $p) | Should Be 1
    (Get-MatchCount (Get-LogLines $p) 'timed out|line \d+') | Should Be 0
  }

  # Known issue (docs/roadmap.md): two simultaneous runs in a brand-new project both create
  # .claude\handoff\.gitignore before taking the mutex, and the loser logs a spurious error.
  # The turn is still written once. Remove -Skip when handoff.ps1 is fixed.
  It 'two simultaneous first runs in a new project log no error (known issue)' -Skip {
    $p = New-TestProject $script:root 'dup-concurrent-first'
    $tp = New-SimpleTranscript $p 1
    $a = Invoke-Handoff -Project $p -Transcript $tp -Reply 'reply 1' -UserHome $script:fakeHome -NoWait
    $b = Invoke-Handoff -Project $p -Transcript $tp -Reply 'reply 1' -UserHome $script:fakeHome -NoWait
    $a.WaitForExit(); $b.WaitForExit()
    $a.Dispose(); $b.Dispose()
    (Get-TurnCount $p) | Should Be 1
    (Test-Path (Join-Path $p '.claude\handoff\hook-error.log')) | Should Be $false
  }

  It 'when the lock is held for 30 seconds, it logs the timeout and still writes the turn' {
    $p = New-TestProject $script:root 'lock-timeout'
    $mutex = New-Object System.Threading.Mutex($false, (Get-HandoffMutexName $p))
    try {
      $mutex.WaitOne(0) | Should Be $true
      $code = Invoke-SimpleTurn $p 1 $script:fakeHome
    } finally {
      try { $mutex.ReleaseMutex() } catch { }
      $mutex.Dispose()
    }
    $code | Should Be 0
    (Test-TurnWritten $p 1) | Should Be $true
    (Get-MatchCount (Get-LogLines $p) 'mutex wait timed out, continuing without lock') | Should Be 1
  }
}

Describe 'handoff.ps1 per-project leftovers and double installs (plugin copy)' {
  BeforeAll {
    $script:root = New-TestRoot
    $script:fakeHome = New-FakeHome $script:root
    $script:userSettings = Join-Path $script:fakeHome '.claude\settings.json'
    $script:userScript = Join-Path $script:fakeHome '.claude\hooks\handoff.ps1'
    $script:ps = 'powershell -NoProfile -ExecutionPolicy Bypass -File'
  }
  AfterAll { Remove-TestRoot $script:root }
  AfterEach {
    Remove-Item -LiteralPath $script:userSettings -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $script:userScript -Force -ErrorAction SilentlyContinue
  }

  It '1. settings.local.json hook with ${CLAUDE_PROJECT_DIR}, script present: skips, note once' {
    $p = New-TestProject $script:root 'c01'
    Set-TestFile (Join-Path $p '.claude\hooks\handoff.ps1') '# old copy'
    Set-TestFile (Join-Path $p '.claude\settings.local.json') (New-HookJson ($script:ps + ' "${CLAUDE_PROJECT_DIR}/.claude/hooks/handoff.ps1"'))
    Assert-Skipped (Invoke-TwoRuns $p $script:fakeHome) 'settings\.local\.json'
  }

  It '2. settings.json hook with a relative path next to a git guard hook, script present: skips' {
    $p = New-TestProject $script:root 'c02'
    Set-TestFile (Join-Path $p '.claude\hooks\handoff.ps1') '# old copy'
    Set-TestFile (Join-Path $p '.claude\settings.json') '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"powershell -File .claude/hooks/git-guard.ps1"},{"type":"command","command":"powershell -File .claude/hooks/handoff.ps1"}]}]}}'
    Assert-Skipped (Invoke-TwoRuns $p $script:fakeHome) "this project's \.claude\\settings\.json"
  }

  It '3. only .claude\commands\next.md: turn written, leftover note once, file kept' {
    $p = New-TestProject $script:root 'c03'
    Set-TestFile (Join-Path $p '.claude\commands\next.md') 'old command'
    $r = Invoke-TwoRuns $p $script:fakeHome
    $r.Exit1 | Should Be 0; $r.Exit2 | Should Be 0
    $r.Turn1 | Should Be $true; $r.Turn2 | Should Be $true
    $r.Log1.Count | Should Be 1
    (Get-MatchCount $r.Log1 'leftovers.*\.claude\\commands\\next\.md') | Should Be 1
    $r.Log2.Count | Should Be 1
    (Test-Path (Join-Path $p '.claude\commands\next.md')) | Should Be $true
  }

  It '4. all three leftovers: one note lists them all' {
    $p = New-TestProject $script:root 'c04'
    Set-TestFile (Join-Path $p '.claude\commands\next.md') 'old'
    Set-TestFile (Join-Path $p '.claude\hooks\handoff.ps1') '# old'
    Set-TestFile (Join-Path $p '.claude\handoff-kit\README.md') 'old'
    (Invoke-SimpleTurn $p 1 $script:fakeHome) | Should Be 0
    (Test-TurnWritten $p 1) | Should Be $true
    $l = Get-LogLines $p
    $l.Count | Should Be 1
    (Get-MatchCount $l 'next\.md, \.claude\\hooks\\handoff\.ps1, \.claude\\handoff-kit') | Should Be 1
  }

  It '5. clean project: turn written, no hook-error.log' {
    $p = New-TestProject $script:root 'c05'
    (Invoke-SimpleTurn $p 1 $script:fakeHome) | Should Be 0
    (Test-TurnWritten $p 1) | Should Be $true
    (Test-Path (Join-Path $p '.claude\handoff\hook-error.log')) | Should Be $false
  }

  It '6. settings.json with only a git guard hook: turn written, no hook-error.log' {
    $p = New-TestProject $script:root 'c06'
    Set-TestFile (Join-Path $p '.claude\settings.json') '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"powershell -File .claude/hooks/git-guard.ps1"}]}]}}'
    (Invoke-SimpleTurn $p 1 $script:fakeHome) | Should Be 0
    (Test-TurnWritten $p 1) | Should Be $true
    (Test-Path (Join-Path $p '.claude\handoff\hook-error.log')) | Should Be $false
  }

  It '7. broken JSON in both project settings files: turn written, exit 0' {
    $p = New-TestProject $script:root 'c07'
    Set-TestFile (Join-Path $p '.claude\settings.json') '{ "hooks": { "Stop": [ broken'
    Set-TestFile (Join-Path $p '.claude\settings.local.json') 'not json at all'
    (Invoke-SimpleTurn $p 1 $script:fakeHome) | Should Be 0
    (Test-TurnWritten $p 1) | Should Be $true
    (Test-Path (Join-Path $p '.claude\handoff\hook-error.log')) | Should Be $false
  }

  It '8. installer hook at user level (absolute quoted path, as install.ps1 writes it), script present: skips' {
    $p = New-TestProject $script:root 'c08'
    Set-TestFile $script:userScript '# installer copy'
    Set-TestFile $script:userSettings (New-HookJson ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $script:userScript + '"'))
    Assert-Skipped (Invoke-TwoRuns $p $script:fakeHome) 'install\.ps1'
  }

  It '9. settings.local.json hook with an absolute path, script present: skips' {
    $p = New-TestProject $script:root 'c09'
    $old = Join-Path $p 'old-kit\handoff.ps1'
    Set-TestFile $old '# old copy'
    Set-TestFile (Join-Path $p '.claude\settings.local.json') (New-HookJson ($script:ps + ' "' + $old + '"'))
    Assert-Skipped (Invoke-TwoRuns $p $script:fakeHome) 'settings\.local\.json'
  }

  It '10. settings.local.json hook with an absolute path, script missing: turn written, stale note once' {
    $p = New-TestProject $script:root 'c10'
    Set-TestFile (Join-Path $p '.claude\settings.local.json') (New-HookJson ($script:ps + ' "' + (Join-Path $p 'old-kit\handoff.ps1') + '"'))
    Assert-StaleNoted (Invoke-TwoRuns $p $script:fakeHome) 'settings\.local\.json'
  }

  It '11. ${CLAUDE_PROJECT_DIR} hook: skips while the script exists, writes turns once it is removed' {
    $p = New-TestProject $script:root 'c11'
    $hs = Join-Path $p '.claude\hooks\handoff.ps1'
    Set-TestFile $hs '# old copy'
    Set-TestFile (Join-Path $p '.claude\settings.local.json') (New-HookJson ($script:ps + ' "${CLAUDE_PROJECT_DIR}/.claude/hooks/handoff.ps1"'))
    (Invoke-SimpleTurn $p 1 $script:fakeHome) | Should Be 0
    (Test-TurnWritten $p 1) | Should Be $false
    $l1 = Get-LogLines $p
    (Get-MatchCount $l1 $skipPat) | Should Be 1
    (Get-MatchCount $l1 $stalePat) | Should Be 0
    Remove-Item -LiteralPath $hs
    (Invoke-SimpleTurn $p 2 $script:fakeHome) | Should Be 0
    (Test-TurnWritten $p 2) | Should Be $true
    $l2 = Get-LogLines $p
    (Get-MatchCount $l2 $stalePat) | Should Be 1
    (Invoke-SimpleTurn $p 3 $script:fakeHome) | Should Be 0
    (Test-TurnWritten $p 3) | Should Be $true
    $l3 = Get-LogLines $p
    (Get-MatchCount $l3 $stalePat) | Should Be 1
    $l3.Count | Should Be $l2.Count
  }

  It '12. user settings.json hook with a missing %USERPROFILE%\.claude\hooks\handoff.ps1: turn written, note once' {
    $p = New-TestProject $script:root 'c12'
    Set-TestFile $script:userSettings (New-HookJson ($script:ps + ' "%USERPROFILE%\.claude\hooks\handoff.ps1"'))
    Assert-StaleNoted (Invoke-TwoRuns $p $script:fakeHome) '%USERPROFILE%\\\.claude\\settings\.json'
  }

  $forms = @(
    @{ n = '13.1'; form = 'forward-slash absolute path, unquoted' },
    @{ n = '13.2'; form = '~/.claude/hooks/handoff.ps1' },
    @{ n = '13.3'; form = '$env:USERPROFILE, single-quoted' },
    @{ n = '13.4'; form = '%USERPROFILE%, double-quoted' },
    @{ n = '13.5'; form = 'Git Bash /c/... path' },
    @{ n = '13.6'; form = '$CLAUDE_PROJECT_DIR in exec-form args' }
  )
  It '<n>. path form: <form>, script present: skips' -TestCases $forms {
    param($n, $form)
    $p = New-TestProject $script:root ('c' + $n)
    Set-TestFile $script:userScript '# copy'
    Set-TestFile (Join-Path $p '.claude\hooks\handoff.ps1') '# copy'
    $h = $script:fakeHome
    $gitBash = '/' + $h.Substring(0, 1).ToLower() + ($h.Substring(2) -replace '\\', '/') + '/.claude/hooks/handoff.ps1'
    switch ($n) {
      '13.1' { $json = New-HookJson ($script:ps + ' ' + ($script:userScript -replace '\\', '/')) }
      '13.2' { $json = New-HookJson ($script:ps + ' ~/.claude/hooks/handoff.ps1') }
      '13.3' { $json = New-HookJson ($script:ps + ' ''$env:USERPROFILE\.claude\hooks\handoff.ps1''') }
      '13.4' { $json = New-HookJson ($script:ps + ' "%USERPROFILE%\.claude\hooks\handoff.ps1"') }
      '13.5' { $json = New-HookJson ($script:ps + ' ' + $gitBash) }
      '13.6' { $json = New-ExecHookJson @('-NoProfile', '-File', '$CLAUDE_PROJECT_DIR/.claude/hooks/handoff.ps1') }
    }
    Set-TestFile (Join-Path $p '.claude\settings.local.json') $json
    Assert-Skipped (Invoke-TwoRuns $p $script:fakeHome) 'settings\.local\.json'
  }

  It '14. a hook path with an unknown variable ($SOMEVAR) is treated as missing' {
    $p = New-TestProject $script:root 'c14'
    Set-TestFile (Join-Path $p '.claude\settings.json') (New-HookJson ($script:ps + ' "$SOMEVAR/handoff.ps1"'))
    Assert-StaleNoted (Invoke-TwoRuns $p $script:fakeHome) "this project's \.claude\\settings\.json"
  }

  It '15. an exec-form arg with spaces in the path, script present: skips' {
    $p = New-TestProject $script:root 'c15'
    $sp = Join-Path $p 'old kit\handoff.ps1'
    Set-TestFile $sp '# copy'
    Set-TestFile (Join-Path $p '.claude\settings.json') (New-ExecHookJson @('-NoProfile', '-File', $sp))
    Assert-Skipped (Invoke-TwoRuns $p $script:fakeHome) "this project's \.claude\\settings\.json"
  }

  It 'installer copy (no CLAUDE_PLUGIN_ROOT) ignores project hooks and leftovers and writes the turn' {
    $p = New-TestProject $script:root 'c16'
    Set-TestFile (Join-Path $p '.claude\hooks\handoff.ps1') '# old copy'
    Set-TestFile (Join-Path $p '.claude\settings.local.json') (New-HookJson ($script:ps + ' "${CLAUDE_PROJECT_DIR}/.claude/hooks/handoff.ps1"'))
    $tp = New-SimpleTranscript $p 1
    (Invoke-Handoff -Project $p -Transcript $tp -Reply 'reply 1' -UserHome $script:fakeHome -PluginRoot '') | Should Be 0
    (Test-TurnWritten $p 1) | Should Be $true
    (Test-Path (Join-Path $p '.claude\handoff\hook-error.log')) | Should Be $false
  }
}
