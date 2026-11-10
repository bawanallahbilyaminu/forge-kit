# git-guard.Tests.ps1 - Pester 3.4.0 tests for the shipped git-guard Stop hook,
# plugins/idea-forge/skills/idea-code-setup/templates/git-guard.ps1.
# Run with: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tests.ps1
#
# Expected behaviour, read from the script:
#   stop_hook_active true           -> exit 0, no message (never blocks twice in a row)
#   not a git repo                  -> exit 0, no message
#   clean, in sync with upstream    -> exit 0, no message
#   uncommitted changes (modified or untracked files)
#                                   -> exit 2, "Git guard: this repo has N uncommitted file change(s). ..."
#   commits ahead of upstream       -> exit 2, "... unpushed commit(s). ..."
#   remote set, branch has no upstream
#                                   -> exit 2, "... unpushed commit(s) (current branch has no upstream yet - push with -u). ..."
#   both                            -> exit 2, "... N uncommitted file change(s) and unpushed commit(s). ..."
#   no remote, or no commits yet    -> only uncommitted changes count
#   any error (bad JSON and so on)  -> exit 0
# The message goes to stderr, which Claude Code shows to the model when a Stop hook exits 2.

. (Join-Path $PSScriptRoot 'GitGuardTestHelpers.ps1')

$advice = 'If this turn made a meaningful change, commit it now with a Conventional Commit message'

Describe 'git-guard.ps1' {
  BeforeAll {
    $script:root = New-GuardTestRoot
    $script:savedGit = Enter-GitSandbox $script:root
  }
  AfterAll {
    Exit-GitSandbox $script:savedGit
    Remove-GuardTestRoot $script:root
  }

  It 'clean repo in sync with its upstream: exit 0, no message' {
    $repo = New-TestRepoWithRemote $script:root 'clean'
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 0
    $r.Stderr | Should BeNullOrEmpty
  }

  It 'modified tracked file: blocks with exit 2 and counts 1 uncommitted change' {
    $repo = New-TestRepoWithRemote $script:root 'modified'
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match '^Git guard: this repo has 1 uncommitted file change\(s\)\. '
    $r.Stderr | Should Not Match 'unpushed'
    $r.Stderr | Should Match ([regex]::Escape($advice))
  }

  It 'untracked file: blocks with exit 2 and counts 1 uncommitted change' {
    $repo = New-TestRepoWithRemote $script:root 'untracked'
    Set-TestFile (Join-Path $repo 'notes.txt') "new`n"
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match '^Git guard: this repo has 1 uncommitted file change\(s\)\. '
    $r.Stderr | Should Not Match 'unpushed'
  }

  It 'counts every changed path: 2 modified and 1 untracked is 3' {
    $repo = New-TestRepoWithRemote $script:root 'three-changes'
    Add-TestCommit $repo 'b.txt' 'add b'
    Invoke-TestGit $repo push -q | Out-Null
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    Set-TestFile (Join-Path $repo 'b.txt') "changed`n"
    Set-TestFile (Join-Path $repo 'c.txt') "new`n"
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match 'has 3 uncommitted file change\(s\)\.'
  }

  It 'unpushed commits: blocks with exit 2 and reports unpushed commits only' {
    $repo = New-TestRepoWithRemote $script:root 'ahead'
    Add-TestCommit $repo 'feature.txt' 'add feature'
    Add-TestCommit $repo 'feature2.txt' 'add feature 2'
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match '^Git guard: this repo has unpushed commit\(s\)\. '
    $r.Stderr | Should Not Match 'uncommitted file change'
    $r.Stderr | Should Not Match 'no upstream'
  }

  It 'uncommitted changes and unpushed commits: reports both' {
    $repo = New-TestRepoWithRemote $script:root 'both'
    Add-TestCommit $repo 'feature.txt' 'add feature'
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match '^Git guard: this repo has 1 uncommitted file change\(s\) and unpushed commit\(s\)\. '
  }

  It 'branch with no upstream (remote exists): blocks and says to push with -u' {
    $repo = New-TestRepoWithRemote $script:root 'no-upstream'
    Invoke-TestGit $repo checkout -q -b feature/x | Out-Null
    Add-TestCommit $repo 'x.txt' 'add x'
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match 'unpushed commit\(s\) \(current branch has no upstream yet - push with -u\)\. '
  }

  It 'branch with no upstream and no new commits still blocks (it counts as unpushed)' {
    $repo = New-TestRepoWithRemote $script:root 'no-upstream-empty'
    Invoke-TestGit $repo checkout -q -b feature/y | Out-Null
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match 'no upstream yet - push with -u'
  }

  It 'behind its upstream but not ahead: exit 0' {
    $repo = New-TestRepoWithRemote $script:root 'behind'
    $other = Join-Path $script:root 'behind-other'
    $bare = Join-Path $script:root 'behind-remote.git'
    Invoke-TestGit $script:root clone -q $bare $other | Out-Null
    Invoke-TestGit $other config user.name 'Test User' | Out-Null
    Invoke-TestGit $other config user.email 'test@example.invalid' | Out-Null
    Invoke-TestGit $other config commit.gpgsign false | Out-Null
    Add-TestCommit $other 'upstream.txt' 'upstream change'
    Invoke-TestGit $other push -q | Out-Null
    Invoke-TestGit $repo fetch -q | Out-Null
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 0
    $r.Stderr | Should BeNullOrEmpty
  }

  It 'no remote: clean repo passes, and only uncommitted changes count' {
    $repo = New-TestRepo $script:root 'no-remote'
    Add-TestCommit $repo 'local.txt' 'local only'
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 0
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match 'has 1 uncommitted file change\(s\)\.'
    $r.Stderr | Should Not Match 'unpushed'
  }

  It 'repo with a remote but no commits yet: only uncommitted changes count' {
    $repo = Join-Path $script:root 'no-commits'
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    Invoke-TestGit $repo init -q -b main | Out-Null
    Invoke-TestGit $repo remote add origin (Join-Path $script:root 'clean-remote.git') | Out-Null
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 0
    Set-TestFile (Join-Path $repo 'first.txt') "new`n"
    $r = Invoke-GitGuard -Dir $repo -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match 'has 1 uncommitted file change\(s\)\.'
    $r.Stderr | Should Not Match 'unpushed'
  }

  It 'a folder that is not a git repo: exit 0, no message' {
    $dir = Join-Path $script:root 'not-a-repo'
    Set-TestFile (Join-Path $dir 'file.txt') "content`n"
    $r = Invoke-GitGuard -Dir $dir -Root $script:root
    $r.ExitCode | Should Be 0
    $r.Stderr | Should BeNullOrEmpty
  }

  It 'stop_hook_active false on a dirty, unpushed repo: blocks (baseline for the next test)' {
    $repo = New-TestRepoWithRemote $script:root 'active-false'
    Add-TestCommit $repo 'feature.txt' 'add feature'
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    $r = Invoke-GitGuard -Dir $repo -StopHookActive $false -Root $script:root
    $r.ExitCode | Should Be 2
  }

  It 'stop_hook_active true on the same kind of repo: exit 0, does not block again' {
    $repo = New-TestRepoWithRemote $script:root 'active-true'
    Add-TestCommit $repo 'feature.txt' 'add feature'
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    $r = Invoke-GitGuard -Dir $repo -StopHookActive $true -Root $script:root
    $r.ExitCode | Should Be 0
    $r.Stderr | Should BeNullOrEmpty
  }

  It 'without CLAUDE_PROJECT_DIR it uses cwd from the hook input' {
    $repo = New-TestRepoWithRemote $script:root 'cwd-fallback'
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    $r = Invoke-GitGuard -Dir $repo -NoProjectDir -Root $script:root
    $r.ExitCode | Should Be 2
    $r.Stderr | Should Match 'has 1 uncommitted file change\(s\)\.'
  }

  It 'invalid JSON on stdin: exit 0' {
    $repo = New-TestRepoWithRemote $script:root 'bad-json'
    Set-TestFile (Join-Path $repo 'README.md') "changed`n"
    $r = Invoke-GitGuard -Dir $repo -RawInput '{ not json' -Root $script:root
    $r.ExitCode | Should Be 0
  }
}
