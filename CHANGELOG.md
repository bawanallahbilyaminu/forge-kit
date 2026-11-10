# Changelog

All notable changes to forge-kit are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Version numbers:**
- A release is named after the marketplace version in `.claude-plugin/marketplace.json`.
- Each plugin also has its own version, in its `plugin.json`.
- Versions before 0.5.0 were never released publicly and have no tags. They are kept below as the project's history.

## [Unreleased]

## [0.5.0] - 2026-11-10

First public release: marketplace 0.5.0, idea-forge 0.4.0, code-handoff 0.4.0.

### idea-forge 0.4.0
- **Added:**
  - **`/idea-council`:** independent critic agents attack an idea, an advocate answers them, and a judge gives a Build / Build with changes / Don't build verdict.
  - **`/idea-refine`:** builder agents turn a judged idea into one refined concept that the user approves.
  - **`/idea-launch`:**
    - creates the project folder and the documentation set for the idea's type (the full software engineering set for software: URS, SRS, BRD, PRD, SDD, data design, wireframes, test plan, WBS and more)
    - writes the documents in dependency layers, so requirement IDs trace from `UR` to `FR` to design to `TC`
    - for software, ends with an independent review by three fresh agents that see only the SRS, SDD and test plan
  - **`/idea-code-setup`:** writes CLAUDE.md, Claude Code settings, a git guard Stop hook and a kickoff prompt that has Claude Code create a private GitHub repo and start M0.
  - New projects are pointed at EGM (optional) for features that need architecture decisions.
- **Changed:**
  - The projects folder is configurable and remembered in `<projects>/_idea-forge/config.json`. The default is `C:\Projects-Windows` on Windows and `~/Projects` elsewhere.
  - The skills no longer assume who the user is. Local context such as Hausa or Sokoto appears only as examples.
  - The git guard works on macOS and Linux as `git-guard.mjs` (Node 18+), alongside `git-guard.ps1` on Windows. `/idea-code-setup` picks the right one from the projects folder path.

### code-handoff 0.4.0
- **Added:**
  - A Stop hook that writes each Claude Code turn to `.claude/handoff/`: `last.md` (prompt, progress notes, final reply, tool counts, files changed, commands run, errors), `history.md` and a copy of the transcript.
  - The `/code-handoff:next` command, which runs the prompt the planning chat left in `.claude/handoff/next.md`.
  - The planning-side `/code-handoff` skill, which reads the handoff, walks the user through steps only they can do, and writes the next prompt.
  - **macOS, Linux and WSL support:**
    - `scripts/handoff.mjs` (Node 18+, no packages) writes the same `last.md` as `scripts/handoff.ps1`.
    - The plugin has one hook command, valid as both sh and PowerShell. It runs `handoff.ps1` on Windows (Git Bash or PowerShell) and `handoff.mjs` elsewhere, and exits quietly without Node.
  - A Windows installer, `installers/windows/install.ps1`, for use without the plugin system, with `-Uninstall`.
- **Fixed:**
  - **Duplicate turns:** the hook can fire twice for one turn. A per-project lock and a `.last-turn` check stop duplicates.
  - **Double installs:** with both the plugin and the installer, or an old per-project copy, each turn is written once. A copy whose script is missing is noticed and skipped.
  - **Leftovers:** files from the old per-project setup are noted once in `hook-error.log`.
  - **First-run race:** two simultaneous first runs in a new project no longer log a spurious error.
  - The docs name the plugin's real command, `/code-handoff:next`. `/next` exists only with the installer.

### Marketplace and repo 0.5.0
- **Added:**
  - plugin icons, drawn by `scripts/make-icons.ps1`
  - `scripts/build-plugins.ps1`, which builds `dist/*.plugin` for the Claude app and GitHub Releases
  - **Tests:**
    - Pester 3.4.0 tests for both PowerShell hooks (49 tests)
    - node:test tests for both Node hooks, the parity of `handoff.mjs` with `handoff.ps1`, and the exact hook command
  - **CI:** `windows-latest`, `ubuntu-latest` (Node 18 and 22) and `macos-latest` (Node 22)
  - ADR 0001 (`docs/adr/0001-cross-platform-hooks.md`): Node for the macOS and Linux hooks, PowerShell kept on Windows
  - this CHANGELOG, a public README, and release notes in `docs/release-notes/`

### Details of the last pre-release change (marketplace 0.5.0, code-handoff 0.4.0)

- code-handoff now works on macOS, Linux and WSL. `hooks/hooks.json` has one shell-form Stop hook, still `async: true`, whose command is valid as both sh and PowerShell:
  - In sh, bash or Git Bash, `${env:-eval "..."}` runs a `uname -s` branch. MINGW, MSYS or CYGWIN `exec`s `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".../handoff.ps1"`, the same program and arguments as before. Anything else `exec`s `node .../handoff.mjs` if Node is on the PATH, or exits 0 silently. WSL therefore counts as Linux, even though `powershell.exe` is on its PATH.
  - Under PowerShell (Claude Code on Windows without Git Bash), the `${env:-...}` part is a silent read of a missing variable, and the old `powershell.exe ... handoff.ps1` command runs.
  - Both branches take the plugin path from the `CLAUDE_PLUGIN_ROOT` environment variable.
- I checked this against the Claude Code hooks reference, which says `sh -c` on macOS and Linux, Git Bash on Windows, and PowerShell when Git Bash isn't installed. I also checked it live in Claude Code 2.1.322 on Windows with a probe plugin loaded by `--plugin-dir`.
- **Timeout:** raised from 30 to 60 seconds in `hooks.json` and in `install.ps1`'s hook entry, so it covers the 30-second lock wait plus the 2-second transcript wait. The lock wait in `handoff.ps1` and `handoff.mjs` is unchanged, so Windows behaves as before and the lock tests stay valid. The hooks reference says the timeout isn't enforced for `async: true` hooks anyway, so 60 is the correct value on paper and harmless in practice.
- **New `tests/handoff/hook-command.test.mjs`** reads the command from `hooks.json`. It checks:
  - on Windows, that it writes the turn through `handoff.ps1` from Git Bash, Windows PowerShell 5.1 and pwsh (CRLF output proves which script ran)
  - on macOS and Linux, that it writes the turn through `handoff.mjs` from `/bin/sh` (LF output), and exits 0 with no output and nothing written when Node isn't on the PATH
  - the `uname` branch for Linux, Darwin, MINGW64, MINGW32, MSYS and CYGWIN
- The code-handoff README's platform support section covers Windows with and without Git Bash, macOS, Linux and WSL, and their requirements. The Windows installer stays Windows-only.

## [0.4.1] - 2026-11-10

Marketplace 0.4.1, code-handoff 0.3.0.

- New `plugins/code-handoff/scripts/handoff.mjs`, the Node 18+ port of `handoff.ps1` for macOS and Linux, using built-in modules only. It isn't used yet: `hooks.json` still runs `handoff.ps1`, and the platform switch is the next M2 item.
- **Ported:**
  - the transcript parser (prompt, progress notes, final reply, tool counts, files changed, commands and errors)
  - the same `last.md` layout, the `history.md` append and trim, the `transcript.jsonl` copy and `.gitignore`
  - the home-folder skip, the 2-second wait and tolerance of a missing or half-written transcript
  - the `.last-turn` duplicate skip, with the same key as `handoff.ps1`
  - the `.gitignore` race fix
  - the plugin-copy guard for live and stale hooks in `~/.claude/settings.json` and the project's settings files, and the leftovers note
  - every failure logged to `hook-error.log`, with exit 0
- **Lock:** the named mutex is replaced by an atomic `mkdir` lock, `.claude/handoff/.lock`, which holds an owner file with the pid and a token. Waiters poll for up to 30 seconds. A lock whose owner process has exited, that was never claimed for 5 seconds, or that is older than 60 seconds is renamed away and taken over. The owner removes it in `finally`. A timeout is logged and the run continues, as in `handoff.ps1`.
- **Differences on purpose:**
  - LF line endings.
  - Tools with equal counts are listed by name. `handoff.ps1` leaves ties in hash order.
  - The user-level double-install note doesn't mention `install.ps1`, because the installer is Windows-only.
  - Other hooks are recognised by `handoff.ps1`, `handoff.mjs` or `handoff.sh`.
  - Error lines in `hook-error.log` carry the message without a PowerShell line number.
- **Tests:**
  - `tests/handoff/handoff.test.mjs` (node:test, 36 tests, run concurrently) mirrors the Pester cases that apply outside Windows. That includes the POSIX path forms `~`, `$HOME`, `${HOME}`, `${CLAUDE_PROJECT_DIR}`, `$CLAUDE_PROJECT_DIR`, relative and absolute paths, plus dead-owner and unclaimed locks.
  - `tests/handoff/parity.test.mjs` (Windows) checks that both implementations write the same `last.md` for the shared fixtures, apart from the timestamp line, line endings and the order of tied tools. `tests/fixtures/handoff/expected/` holds that output, made from `handoff.ps1` by `update-expected.mjs`, for macOS and Linux.
  - CI runs the Node tests on all three posix jobs and now also in the Windows job, where the parity test can run.

## [0.4.0] - 2026-11-10

Marketplace 0.4.0, idea-forge 0.4.0.

- `/idea-code-setup` supports macOS and Linux. It picks the platform from the projects folder path. On macOS and Linux a new project gets `.claude/hooks/git-guard.mjs`, a Node 18+ script with no packages, and the Stop hook from `settings.posix.json.template`: `if command -v node >/dev/null 2>&1; then node "$CLAUDE_PROJECT_DIR/.claude/hooks/git-guard.mjs"; fi`. Exit 2 still blocks, and without Node the hook exits 0. Windows projects get exactly the same files as before.
- `git-guard.mjs` has the same behaviour and messages as `git-guard.ps1`. The "Do these first" list asks macOS and Linux users to check `node --version`. The CLAUDE.md template names the platform's git guard file.
- ADR 0001 (`docs/adr/0001-cross-platform-hooks.md`) records the choice of Node over sh plus `jq` for the macOS and Linux hooks.
- CI has a `posix` job on `ubuntu-latest` (Node 18 and 22) and `macos-latest` (Node 22). It runs the node:test tests, which cover the same 16 cases as the Pester tests, check that the two settings templates differ only in the hook command, and check the `sh` hook command with and without Node. The `windows-latest` job is unchanged.

## [0.3.3] - 2026-11-10

Marketplace 0.3.3, code-handoff 0.2.3.

- Fixed a race on a project's first run, found by the M3 tests. When two runs started at the same moment in a project with no `.claude/handoff/` folder yet, both created `.gitignore` before taking the mutex. The loser logged a spurious "being used by another process" error to `hook-error.log` and exited, although the turn was still written once. Now, if that write fails and the file exists, the error is ignored. Any other failure is still logged. The test for it is no longer skipped, and it passed 10 times out of 10 in a loop. The same loop against 0.2.2 failed 1 time in 10, and 4 in 6 when the race was first found.

## [0.3.2] - 2026-11-10

Marketplace 0.3.2, code-handoff 0.2.2.

- The plugin copy of `handoff.ps1` also checks the project's `.claude/settings.json` and `.claude/settings.local.json`. If either has a Stop hook running a `handoff.ps1` outside the plugin, it steps aside as it does for the installer, and notes once in `hook-error.log` which file has the hook. Before, only `%USERPROFILE%\.claude\settings.json` was checked, so an old per-project hook wrote every turn twice.
- It also notes once any leftovers from the old per-project setup (`.claude/commands/next.md`, which shows up as a second `/next (project)` command, `.claude/hooks/handoff.ps1` and `.claude/handoff-kit/`). It never deletes them and still writes the turn.
- Before stepping aside, the plugin resolves the script path from the other hook's command. It handles quoted, absolute and forward-slash paths, `~`, `%USERPROFILE%` and `$env:USERPROFILE`, `${CLAUDE_PROJECT_DIR}` and `$CLAUDE_PROJECT_DIR`, Git Bash `/c/...` paths and paths relative to the project. If the script is missing or the path can't be resolved, it doesn't skip: it writes the turn and notes once, with a marker per settings file, which file has the stale entry and that it should be removed.
- The code-handoff README has an "Upgrading from the per-project setup" section. The skill's troubleshooting no longer points at a per-project hook in `settings.local.json`.

## [0.3.1] - 2026-11-10

Marketplace 0.3.1, idea-forge 0.3.1, code-handoff 0.2.1.

- New projects point at EGM for big features. The CLAUDE.md template from `/idea-code-setup` has a "Designing big features" rule: before building a feature that needs architecture decisions, run `/egm:egm-brainstorm`, `/egm:egm-draft` and `/egm:egm-review` if the EGM plugin is installed, and save the design under `docs/04-architecture/features/`. Without EGM, write a short design note there before coding. The command names were checked against EGM's README (github.com/google/elephant-goldfish-model).
- The root README lists EGM as optional, with its link and install commands.
- Command name fix, found in live testing: with the code-handoff plugin the command is `/code-handoff:next`, and `/next` exists only with the installer. The READMEs, the code-handoff skill (status section, "Send it" step and setup), the idea-code-setup skill, the plugin and marketplace descriptions and `docs/architecture.md` now give both forms. The command file is unchanged.

## [0.3.0] - 2026-11-10

Marketplace 0.3.0 and idea-forge 0.3.0.

- `/idea-launch` ends with an independent review (step 6), adapted from the "goldfish" reviewers in EGM. Three fresh subagents get only file paths, never the chat or the ideation files: one reads the SRS and SDD for gaps and contradictions, one reads them to judge whether Claude Code could build M0 and M1 without guessing, and one checks traceability across the SRS, SDD, test plan and test cases. Each returns findings by severity (blocker, major, minor) with a suggested fix.
- The skill fixes blockers and majors, puts what it can't fix under Open questions, and appends an "Independent review" summary to the project's `docs/README.md`. Without a subagent tool it runs the three reviews in turn and says they weren't independent.
- The briefs, finding format and summary template are in `idea-launch/references/reviewers.md`. The review runs only for document sets with an SRS, SDD and test plan (software, or mixed ideas that took them). Other types skip it.
- The reply to the user gives the review counts in one line.

## [0.2.2] - 2026-11-10

Marketplace 0.2.2, code-handoff 0.2.0.

- The double install is handled. When the plugin copy of `handoff.ps1` finds the installer's Stop hook in `%USERPROFILE%\.claude\settings.json`, it exits before taking the lock, so each turn is written once with no wait. It notes this once per project in `hook-error.log`.
- `install.ps1` refuses to install while the code-handoff plugin is installed and enabled (according to `installed_plugins.json` and `enabledPlugins`), unless `-Force` is given.
- New `install.ps1 -Uninstall` removes only the installer's hook entry and files, with a `settings.json.bak-handoff-uninstall` backup.
- The code-handoff README has an Install section comparing the plugin (recommended) and the installer (fallback), with how to switch and what happens if both are installed. The root README links to it.
- The code-handoff skill's dashboard example is generic, and it explains the double-install note in `hook-error.log`.

## [0.2.1] - 2026-11-10

Marketplace 0.2.1 and idea-forge 0.2.1.

- The skills no longer assume who the user is. Removed the regional idiom "yarned" from idea-council, and the assumptions that the user has a job (Cost critic) and their own company (Business Model builder). The privacy NFR now asks for the data protection law where the users and data are, with GDPR and the NDPA as examples, instead of defaulting to Nigeria's NDPA.
- The local-context examples are framed as examples, such as "for example, a user in Sokoto, Nigeria" and "Hausa and English for users in northern Nigeria", and the critics and builders now ask about the users' languages in general.
- The example slug `kobo-sms-bridge` is now `clinic-sms-reminders` everywhere, including all four copies of `projects-folder.md`.
- Tested 0.2.0 in the Claude app: with the projects folder connected, `/idea-council` wrote `_idea-forge/config.json` and the verdict in the right place. In a fresh chat without the folder, it got the folder and reused the existing config without rewriting it.

## [0.2.0] - 2026-11-10

Marketplace 0.2.0 and idea-forge 0.2.0.

- The projects folder is configurable. idea-forge asks once where to keep projects, defaulting to `C:\Projects-Windows` on Windows and `~/Projects` elsewhere, and saves the answer in `<projects>/_idea-forge/config.json`. The skills and README no longer hardcode the path.
- The config is found only when the projects folder is connected in the current chat. In a new chat, the skill either finds it in a connected folder or asks for the folder again, offering the remembered or default path first.
- Each skill has its own copy of `references/projects-folder.md`, because the Claude app can install skills one by one, each in its own folder, so a path into a sibling skill may not exist. The source is the idea-launch copy. `scripts/check-shared-refs.ps1`, run in CI, checks that the copies are identical.
- The marketplace version is 0.2.0. code-handoff stays at 0.1.1.

## [0.1.1] - 2026-11-10

Marketplace 0.1.1 and both plugins 0.1.1.

- handoff.ps1 serialises concurrent runs with a per-project mutex and skips a turn it has already written. Claude Code was seen firing the Stop hook twice for one turn, which wrote duplicate history entries and caused a lock error on transcript.jsonl. The mutex is released and disposed in a `finally` on every exit path, and if the 30-second wait times out the hook logs it to `hook-error.log` and continues without the lock.
- idea-code-setup stages the `.claude/` files in `setup/dot-claude/` for the kickoff to move.
- The install instructions name the real GitHub owner, the idea-forge README has an install line, and the stale `handoff-kit\install.ps1` references now point at `installers\windows\install.ps1`.
- New repo tooling: `scripts/build-plugins.ps1`, `scripts/check-powershell.ps1` and GitHub Actions CI.

## [0.1.0] - 2026-11-10

First version, built in a planning chat and moved into this repo.

[Unreleased]: https://github.com/bawanallahbilyaminu/forge-kit/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/bawanallahbilyaminu/forge-kit/releases/tag/v0.5.0
