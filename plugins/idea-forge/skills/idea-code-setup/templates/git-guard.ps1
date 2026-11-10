# git-guard.ps1 - Claude Code Stop hook.
# When Claude Code is about to end a turn with uncommitted or unpushed work, send it back
# once to commit and push (or explain why not). Never blocks twice in a row, never errors out.

$ErrorActionPreference = 'SilentlyContinue'   # git writes to stderr; don't let that throw in PowerShell 5.1
try {
  [Console]::InputEncoding = [System.Text.Encoding]::UTF8
  $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json
  if ($hook.stop_hook_active) { exit 0 }    # already sent back once this turn

  $dir = [string]$env:CLAUDE_PROJECT_DIR
  if (-not $dir) { $dir = [string]$hook.cwd }
  if (-not $dir) { exit 0 }
  Set-Location -LiteralPath $dir

  $inside = git rev-parse --is-inside-work-tree 2>$null
  if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') { exit 0 }   # not a git repo yet

  $dirty = @(git status --porcelain 2>$null | Where-Object { $_ })
  $ahead = 0
  $unpushedNote = ''
  $remotes = @(git remote 2>$null | Where-Object { $_ })
  $null = git rev-parse --verify HEAD 2>$null
  $hasCommits = ($LASTEXITCODE -eq 0)
  if ($remotes.Count -gt 0 -and $hasCommits) {
    $null = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -eq 0) {
      $count = git rev-list --count '@{u}..HEAD' 2>$null
      if ($LASTEXITCODE -eq 0) { $ahead = [int]$count }
    } else {
      $ahead = 1
      $unpushedNote = ' (current branch has no upstream yet - push with -u)'
    }
  }

  if ($dirty.Count -eq 0 -and $ahead -eq 0) { exit 0 }

  $parts = @()
  if ($dirty.Count -gt 0) { $parts += "$($dirty.Count) uncommitted file change(s)" }
  if ($ahead -gt 0) { $parts += "unpushed commit(s)$unpushedNote" }
  $msg = "Git guard: this repo has " + ($parts -join ' and ') + ". " +
         "If this turn made a meaningful change, commit it now with a Conventional Commit message (reference FR IDs) and push. " +
         "If the work is incomplete or intentionally left uncommitted, say so in one line in your reply and stop."
  [Console]::Error.WriteLine($msg)
  exit 2
}
catch { exit 0 }
