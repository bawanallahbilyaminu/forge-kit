# forge-kit

This repo is a plugin marketplace with two plugins for people who plan with Claude in the app and build with Claude Code:
- **idea-forge** takes an idea through council, refine, launch and code setup.
- **code-handoff** is a two-way handoff between a planning chat and Claude Code.

See `README.md` for the user view, `docs/architecture.md` for how the pieces fit, and `docs/roadmap.md` for milestones and known issues, and `CHANGELOG.md` for changes.

## Layout
- `.claude-plugin/marketplace.json`: lists the plugins. Keep versions in sync with each `plugin.json`.
- `plugins/idea-forge/skills/<skill>/SKILL.md`, plus `references/` and `templates/`
- `plugins/code-handoff/`: `hooks/hooks.json`, `scripts/handoff.ps1`, `commands/next.md`, `skills/code-handoff/SKILL.md`
- `installers/windows/install.ps1`: installs the handoff without the plugin system, using files from `plugins/code-handoff/`
- `tests/`: Pester tests (`tests/<area>/*.Tests.ps1`) and synthetic fixtures (`tests/fixtures/`). No real transcripts, paths or personal data in fixtures.
- `.claude/`: this repo's own Claude Code settings, the git guard hook and the handoff folder (gitignored)

## Commands
| Task | Command |
|---|---|
| Validate a plugin | `claude plugin validate plugins/<name>/.claude-plugin/plugin.json` |
| Validate the marketplace | `claude plugin validate .claude-plugin/marketplace.json` |
| Build `.plugin` files | `powershell -File scripts/build-plugins.ps1` (writes `dist/`) |
| Redraw the plugin icons | `powershell -NoProfile -File scripts/make-icons.ps1` (writes `plugins/*/.claude-plugin/icon.png`, 1024x1024) |
| Parse-check and ASCII-check every .ps1 | `powershell -NoProfile -File scripts/check-powershell.ps1` |
| Check shared skill files are identical copies | `powershell -NoProfile -File scripts/check-shared-refs.ps1` (the list of shared files is at the top of the script) |
| Run the Pester tests | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-tests.ps1` (add `-Path tests/handoff` for one folder). Uses Pester 3.4.0, which ships with Windows PowerShell 5.1, so there's nothing to install. Takes about 2 minutes, because each hook run waits 2 seconds and the lock test waits 30. |
| Run the Node hook tests (macOS/Linux hooks, any OS) | `node --test tests/git-guard/git-guard.test.mjs tests/handoff/handoff.test.mjs tests/handoff/parity.test.mjs tests/handoff/hook-command.test.mjs` (Node 18+, nothing to install). Takes about 40 seconds. On Windows the two `sh` hook-command tests are skipped, and `parity.test.mjs` compares `handoff.mjs` with `handoff.ps1`. Elsewhere it's skipped. |
| Regenerate the expected `last.md` files | `node tests/handoff/update-expected.mjs` (Windows only: `handoff.ps1` is the reference). Run it only after an intended change to the `last.md` layout, and review the diff in `tests/fixtures/handoff/expected/`. |
| Parse-check one .ps1 | `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile('<file>', [ref]$null, [ref]$e); $e"` |

CI (`.github/workflows/ci.yml`) has two jobs:
- **`check`** (`windows-latest`) runs the JSON check, the version-sync check, the PowerShell check, the shared-file check, the Pester tests, the Node hook tests (including parity with `handoff.ps1`), `claude plugin validate` and the build.
- **`posix`** (`ubuntu-latest` with Node 18 and 22, and `macos-latest` with Node 22) runs the Node hook tests.

## Hooks on each platform
Each hook has a PowerShell version for Windows and a Node version for macOS and Linux (`docs/adr/0001-cross-platform-hooks.md`). Both must behave the same and print the same messages. A behaviour change updates both scripts and both test files (`*.Tests.ps1` and `*.test.mjs`) in the same commit.

The code-handoff `hooks/hooks.json` command must stay valid as both sh and PowerShell. Claude Code runs it with `sh -c` on macOS and Linux, Git Bash on Windows, and PowerShell when Git Bash is missing. Don't put a `}` inside its `${env:-eval "..."}` part. Run `tests/handoff/hook-command.test.mjs` after any change to it. See "One hook command for every platform" in `docs/architecture.md`.

## Rules for this repo
- **Skills are instructions for Claude.** Write them in the imperative ("Read the file", not "You should read"). Keep each SKILL.md under about 3,000 words and move detail into `references/`. Frontmatter descriptions say when the skill is used, with trigger phrases.
- **PowerShell must run on Windows PowerShell 5.1:**
  - Don't use `??`, the ternary operator or `-Parallel`.
  - Keep `.ps1` files ASCII-only, because 5.1 misreads UTF-8 files without a BOM.
  - Around native commands like `git`, use `$ErrorActionPreference = 'SilentlyContinue'`.
  - Hooks must always exit 0 unless they intentionally block with exit code 2.
- **Hooks must never break a user's session.** Wrap everything in try/catch and log failures to the handoff folder, not to the console.
- **Paths:** use `${CLAUDE_PLUGIN_ROOT}` in plugin hooks. Never hardcode a user's path. idea-forge resolves the projects folder through `references/projects-folder.md` in each skill. The source is the copy in `idea-launch`; edit it there, copy it to the other skills, and run `scripts/check-shared-refs.ps1`. A skill never reads files from a sibling skill. `C:\Projects-Windows` appears only as the stated Windows default.
- **Bump versions** in `plugin.json` and `marketplace.json` for any user-visible change, and note the change in `CHANGELOG.md` under `[Unreleased]` (Keep a Changelog format).
- **No personal data** in the repo, such as emails, tokens, client names or real project data.

## Git workflow (always)
- **Commit after every meaningful change**: a working step, a doc update or a config change. Don't leave a turn with meaningful uncommitted work.
- **Push immediately after every commit.**
- Use Conventional Commits: `feat(idea-forge): ...`, `fix(code-handoff): ...`, `docs: ...`, `chore: ...`, `ci: ...`.
- Work on a branch per milestone (`m1-portability`), and open one PR per milestone with `gh pr create`. Never merge PRs yourself.
- Never force-push, `reset --hard` or rewrite published history.
- The repo is private on GitHub until M4 (release). Making it public is the user's decision.
- `.claude/hooks/git-guard.ps1` checks for uncommitted or unpushed work at the end of each turn.

## Reporting back
End each turn with:
- what changed
- the validation and test results
- the commits and pushes made
- anything blocked
- a **Your steps** list of anything only the user can do

The planning chat reads this through `.claude/handoff/`.
