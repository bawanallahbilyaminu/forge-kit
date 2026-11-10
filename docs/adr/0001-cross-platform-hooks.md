# ADR 0001: Hooks on macOS and Linux

- **Status:** Accepted
- **Date:** 2026-11-10
- **Milestone:** M2 (macOS and Linux)

## Context

forge-kit ships two Claude Code Stop hooks, and both are PowerShell for Windows PowerShell 5.1:
- **`git-guard`** is copied into each new project by `/idea-code-setup`. It checks `git status`, the upstream and `stop_hook_active`, and then exits 0 or blocks with exit 2.
- **`handoff`** is in the code-handoff plugin. It parses Claude Code's JSONL transcript, collects the prompt, tool uses, files and errors, and writes markdown. It also reads several `settings.json` files to detect a double install.

M2 needs both to run on macOS and Linux. The roadmap left two options open:
1. **POSIX sh or bash, plus `jq`** for JSON.
2. **A single Node script per hook**, using only Node's built-in modules.

The facts that decide it:
- **JSON is central.** git-guard reads two fields from its input. handoff parses a whole JSONL transcript, walks it backwards, matches tool uses to tool results, and reads three settings files whose hook commands can be shell strings or arrays. Without a real JSON parser, sh can only do this with fragile `grep`/`sed` matching.
- **`jq` isn't a safe assumption.** Most Linux distributions don't install it by default, and it is missing from many slim containers and CI images. Recent macOS versions ship it, but older ones don't. A missing `jq` would make the hooks silently do nothing, or fail on every turn.
- **Node is usually there, but not always.** Claude Code installed with npm needs Node 18 or later. The native installer ships a standalone binary that doesn't need Node, so some users won't have it. In practice, the people this kit targets (developers who plan with Claude and build with Claude Code) almost always have Node.
- **bash differs between platforms.** macOS ships bash 3.2 and uses BSD versions of `sed`, `date` and `stat`, while Linux uses GNU versions. A sh port has to stay inside the common subset, and testing it well needs bats plus fixtures for both.
- **Testability.** Node has a test runner built in (`node:test`, Node 18+), so the tests need no install. The same tests can run on Linux, macOS and Windows.
- **Windows stays on PowerShell either way.** The PowerShell scripts are tested (49 Pester tests), live, and need nothing beyond Windows itself. Moving Windows to Node would add a dependency for no gain now. So there will be two implementations whichever option we pick, and the question is only which second language is easier to keep in step with the first.

## Decision

Use **one Node script per hook for macOS and Linux** (`git-guard.mjs`, later `handoff.mjs`). Each script:
- runs on Node 18 or later
- uses only built-in modules (`node:fs`, `node:child_process`, `node:path`, `node:os`), with no `package.json` and no `npm install`
- keeps the same behaviour and messages as the PowerShell version
- follows the same rule as before: always exit 0 unless it intentionally blocks with exit 2

The hook command guards against a missing Node, so a missing runtime never breaks a session:

```sh
if command -v node >/dev/null 2>&1; then node "$CLAUDE_PROJECT_DIR/.claude/hooks/git-guard.mjs"; fi
```

Node's exit code passes through, so exit 2 still blocks. Without Node, the hook exits 0 and does nothing.

Windows keeps the PowerShell scripts unchanged.

## Consequences

- **Two implementations per hook**, PowerShell and Node. The same expected-behaviour table keeps them in step:
  - It is listed at the top of `tests/git-guard/git-guard.Tests.ps1`.
  - The Node tests in `tests/git-guard/git-guard.test.mjs` use the same cases.
  - A behaviour change must update both scripts and both test files in the same commit.
- **CI** runs the Node tests on `ubuntu-latest` and `macos-latest`. The `windows-latest` job is unchanged and keeps running the Pester tests.
- **No Node, no guard.** Users without Node on macOS or Linux get no git guard. The CLAUDE.md template and the code-setup skill say that Node 18 or later is needed there.
- **The handoff port** (next) follows the same pattern. The code-handoff plugin's `hooks.json` will then need to pick PowerShell on Windows and Node elsewhere. That is a separate roadmap item.
- **Revisit** if Node turns out to be missing for a meaningful share of users, or if a single cross-platform runtime for all three OSes becomes worth the Windows dependency.

## Options not chosen

- **sh plus `jq`:** smallest scripts for git-guard, but it adds a dependency many Linux users don't have. It also makes the handoff transcript parser hard to write and test robustly, and it needs bats for tests.
- **sh without `jq`:** fine for git-guard alone, but not workable for handoff's transcript and settings parsing.
- **Python 3:** not guaranteed on macOS (only a stub until Xcode command line tools are installed), and it's no more common than Node for this audience.
