# Roadmap

## M0: Repo and release tooling (done in 0.1.1, PR `m0-repo-tooling`)
- Initialise git and create the private GitHub repo `forge-kit`. Push.
- Fill in `<owner>` in the README files with the real GitHub owner.
- Make both plugins and the marketplace pass `claude plugin validate`.
- `scripts/build-plugins.ps1`: zip each plugin into `dist/<name>.plugin`, for upload to the Claude app and to GitHub Releases.
- `installers/windows/install.ps1` reads from `plugins/code-handoff/`. Check its paths.
- Parse-check every `.ps1` file with the PowerShell parser.
- GitHub Actions CI: validate the JSON files, parse-check the PowerShell on `windows-latest`, and run the plugin validation if the CLI can run in CI.

## M1: Portability
- [x] Make the projects folder configurable in idea-forge. Ask once and remember the answer in `<projects>/_idea-forge/config.json`. Default to `C:\Projects-Windows` on Windows and `~/Projects` elsewhere. Done in 0.2.0: see `plugins/idea-forge/skills/idea-launch/references/projects-folder.md`.
- [x] Remove the author-specific wording from the skills. Keep the local context examples, such as Hausa and Sokoto, as examples only. Done in 0.2.1.
- [x] Document the two ways to install code-handoff (plugin or installer), and make sure they can't both run. Done in code-handoff 0.2.0: see "Two install paths, one active hook" in `docs/architecture.md`.
- [x] **No-context review in `/idea-launch`** (borrowed from EGM's "goldfish" reviewers). After the documents are written, spawn fresh agents that get only the finished SRS and SDD, with no chat history and no ideation files. One looks for gaps and contradictions. One checks whether Claude Code could build M0 and M1 from these documents alone. One checks traceability against the test cases. Fix what they find, or list it under Open questions, and add a short review summary to `docs/README.md`. Done in idea-forge 0.3.0: see step 6 of the idea-launch skill and `references/reviewers.md`.
- [x] **Point new projects at EGM for big features.** In `/idea-code-setup`'s CLAUDE.md template, add a rule: before building a feature that needs architecture decisions, run the EGM workflow (`/egm:egm-brainstorm`, then `/egm:egm-draft`, then `/egm:egm-review`) if the EGM plugin is installed, and save the design under `docs/04-architecture/features/`. Mention EGM as optional in the forge-kit README, with a link to github.com/google/elephant-goldfish-model. Done in idea-forge 0.3.1: see "Designing big features" in `idea-code-setup/templates/CLAUDE.md.template`.

Order: M3 (tests) comes before M2 (macOS and Linux), so the hook has tests before it's ported. Decided in the planning chat on 2026-11-10.

## M2: macOS and Linux
- [x] Choose between POSIX tools plus `jq` and a single Node script per hook, and record the choice in an ADR. Done: `docs/adr/0001-cross-platform-hooks.md` picks Node (18+, built-in modules only) for macOS and Linux and keeps PowerShell on Windows.
- [x] git-guard for macOS and Linux. Done in idea-forge 0.4.0: `idea-code-setup/templates/git-guard.mjs` and `settings.posix.json.template`. Its node:test tests (`tests/git-guard/git-guard.test.mjs`) use the same cases as the Pester tests and run in CI on `ubuntu-latest` (Node 18 and 22) and `macos-latest` (Node 22).
- [ ] handoff for macOS and Linux (`handoff.mjs`), with tests ported from `tests/handoff/handoff.Tests.ps1`.
- [ ] The code-handoff `hooks.json` picks the right script for each platform.

## M3: Tests
- [x] Fixture transcripts (synthetic) and Pester tests for the handoff parser: a normal turn, a turn with tool errors, an interrupted turn, a slash command turn and a lagging transcript. Done on branch `m3-tests`: `tests/handoff/handoff.Tests.ps1` (Pester 3.4.0) also covers duplicate runs, the lock timeout, the home-folder skip, and the leftovers and stale-hook cases from code-handoff 0.2.2. Run it with `scripts/run-tests.ps1`, which CI also runs.
- [x] Pester tests for git-guard: a clean repo, a dirty repo, unpushed commits, no upstream, not a repo, and `stop_hook_active`. Done on branch `m3-tests`: `tests/git-guard/git-guard.Tests.ps1` tests the shipped template (identical to this repo's live `.claude/hooks/git-guard.ps1`). It uses temp repos with a local bare remote, and also covers counting several changes, being behind the upstream, no remote, no commits yet, the `cwd` fallback and bad JSON.

## M4: Public release
- Polish the README with a GIF of the loop, write a CHANGELOG, tag v0.1.0, and attach the `.plugin` files to a GitHub Release.
- The user makes the repo public.

## Known issues
- The planning app can't write inside a project's `.claude/` folder unless that folder itself is connected. idea-code-setup therefore stages its files in `setup/dot-claude/`, and the kickoff moves them. Shipped in 0.1.1.
- `handoff.ps1` has been tested in one real project (Windows, Git Bash shell). `git-guard.ps1` is now live in this repo as its Stop hook. The plugin route (code-handoff 0.2.0 from the local marketplace, user scope) was tested live on Windows on 2026-11-10, including the double-install guard and `-Uninstall`: with both installed, the plugin copy stepped aside and wrote the one-time note in `hook-error.log`, and after `install.ps1 -Uninstall` the plugin copy wrote the turn on its own.
- The plugins have no icon yet, so `claude plugin validate` warns `ICON_MISSING`. It needs a square PNG (512-2048 px) at `.claude-plugin/icon.png` in each plugin.
## Changelog
- 0.4.0 (marketplace), idea-forge 0.4.0:
  - `/idea-code-setup` supports macOS and Linux. It picks the platform from the projects folder path. On macOS and Linux a new project gets `.claude/hooks/git-guard.mjs`, a Node 18+ script with no packages, and the Stop hook from `settings.posix.json.template`: `if command -v node >/dev/null 2>&1; then node "$CLAUDE_PROJECT_DIR/.claude/hooks/git-guard.mjs"; fi`. Exit 2 still blocks, and without Node the hook exits 0. Windows projects get exactly the same files as before.
  - `git-guard.mjs` has the same behaviour and messages as `git-guard.ps1`. The "Do these first" list asks macOS and Linux users to check `node --version`. The CLAUDE.md template names the platform's git guard file.
  - ADR 0001 (`docs/adr/0001-cross-platform-hooks.md`) records the choice of Node over sh plus `jq` for the macOS and Linux hooks.
  - CI has a `posix` job on `ubuntu-latest` (Node 18 and 22) and `macos-latest` (Node 22). It runs the node:test tests, which cover the same 16 cases as the Pester tests, check that the two settings templates differ only in the hook command, and check the `sh` hook command with and without Node. The `windows-latest` job is unchanged.
- 0.3.3 (marketplace), code-handoff 0.2.3:
  - Fixed a race on a project's first run, found by the M3 tests. When two runs started at the same moment in a project with no `.claude/handoff/` folder yet, both created `.gitignore` before taking the mutex. The loser logged a spurious "being used by another process" error to `hook-error.log` and exited, although the turn was still written once. Now, if that write fails and the file exists, the error is ignored. Any other failure is still logged. The test for it is no longer skipped, and it passed 10 times out of 10 in a loop. The same loop against 0.2.2 failed 1 time in 10, and 4 in 6 when the race was first found.
- 0.3.2 (marketplace), code-handoff 0.2.2:
  - The plugin copy of `handoff.ps1` also checks the project's `.claude/settings.json` and `.claude/settings.local.json`. If either has a Stop hook running a `handoff.ps1` outside the plugin, it steps aside as it does for the installer, and notes once in `hook-error.log` which file has the hook. Before, only `%USERPROFILE%\.claude\settings.json` was checked, so an old per-project hook wrote every turn twice.
  - It also notes once any leftovers from the old per-project setup (`.claude/commands/next.md`, which shows up as a second `/next (project)` command, `.claude/hooks/handoff.ps1` and `.claude/handoff-kit/`). It never deletes them and still writes the turn.
  - Before stepping aside, the plugin resolves the script path from the other hook's command. It handles quoted, absolute and forward-slash paths, `~`, `%USERPROFILE%` and `$env:USERPROFILE`, `${CLAUDE_PROJECT_DIR}` and `$CLAUDE_PROJECT_DIR`, Git Bash `/c/...` paths and paths relative to the project. If the script is missing or the path can't be resolved, it doesn't skip: it writes the turn and notes once, with a marker per settings file, which file has the stale entry and that it should be removed.
  - The code-handoff README has an "Upgrading from the per-project setup" section. The skill's troubleshooting no longer points at a per-project hook in `settings.local.json`.
- 0.3.1 (marketplace), idea-forge 0.3.1, code-handoff 0.2.1:
  - New projects point at EGM for big features. The CLAUDE.md template from `/idea-code-setup` has a "Designing big features" rule: before building a feature that needs architecture decisions, run `/egm:egm-brainstorm`, `/egm:egm-draft` and `/egm:egm-review` if the EGM plugin is installed, and save the design under `docs/04-architecture/features/`. Without EGM, write a short design note there before coding. The command names were checked against EGM's README (github.com/google/elephant-goldfish-model).
  - The root README lists EGM as optional, with its link and install commands.
  - Command name fix, found in live testing: with the code-handoff plugin the command is `/code-handoff:next`, and `/next` exists only with the installer. The READMEs, the code-handoff skill (status section, "Send it" step and setup), the idea-code-setup skill, the plugin and marketplace descriptions and `docs/architecture.md` now give both forms. The command file is unchanged.
- 0.3.0 (idea-forge and the marketplace):
  - `/idea-launch` ends with an independent review (step 6), adapted from the "goldfish" reviewers in EGM. Three fresh subagents get only file paths, never the chat or the ideation files: one reads the SRS and SDD for gaps and contradictions, one reads them to judge whether Claude Code could build M0 and M1 without guessing, and one checks traceability across the SRS, SDD, test plan and test cases. Each returns findings by severity (blocker, major, minor) with a suggested fix.
  - The skill fixes blockers and majors, puts what it can't fix under Open questions, and appends an "Independent review" summary to the project's `docs/README.md`. Without a subagent tool it runs the three reviews in turn and says they weren't independent.
  - The briefs, finding format and summary template are in `idea-launch/references/reviewers.md`. The review runs only for document sets with an SRS, SDD and test plan (software, or mixed ideas that took them). Other types skip it.
  - The reply to the user gives the review counts in one line.
- 0.2.2 (marketplace), code-handoff 0.2.0:
  - The double install is handled. When the plugin copy of `handoff.ps1` finds the installer's Stop hook in `%USERPROFILE%\.claude\settings.json`, it exits before taking the lock, so each turn is written once with no wait. It notes this once per project in `hook-error.log`.
  - `install.ps1` refuses to install while the code-handoff plugin is installed and enabled (according to `installed_plugins.json` and `enabledPlugins`), unless `-Force` is given.
  - New `install.ps1 -Uninstall` removes only the installer's hook entry and files, with a `settings.json.bak-handoff-uninstall` backup.
  - The code-handoff README has an Install section comparing the plugin (recommended) and the installer (fallback), with how to switch and what happens if both are installed. The root README links to it.
  - The code-handoff skill's dashboard example is generic, and it explains the double-install note in `hook-error.log`.
- 0.2.1 (idea-forge and the marketplace):
  - The skills no longer assume who the user is. Removed the regional idiom "yarned" from idea-council, and the assumptions that the user has a job (Cost critic) and their own company (Business Model builder). The privacy NFR now asks for the data protection law where the users and data are, with GDPR and the NDPA as examples, instead of defaulting to Nigeria's NDPA.
  - The local-context examples are framed as examples, such as "for example, a user in Sokoto, Nigeria" and "Hausa and English for users in northern Nigeria", and the critics and builders now ask about the users' languages in general.
  - The example slug `kobo-sms-bridge` is now `clinic-sms-reminders` everywhere, including all four copies of `projects-folder.md`.
  - Tested 0.2.0 in the Claude app: with the projects folder connected, `/idea-council` wrote `_idea-forge/config.json` and the verdict in the right place. In a fresh chat without the folder, it got the folder and reused the existing config without rewriting it.
- 0.2.0 (idea-forge and the marketplace):
  - The projects folder is configurable. idea-forge asks once where to keep projects, defaulting to `C:\Projects-Windows` on Windows and `~/Projects` elsewhere, and saves the answer in `<projects>/_idea-forge/config.json`. The skills and README no longer hardcode the path.
  - The config is found only when the projects folder is connected in the current chat. In a new chat, the skill either finds it in a connected folder or asks for the folder again, offering the remembered or default path first.
  - Each skill has its own copy of `references/projects-folder.md`, because the Claude app can install skills one by one, each in its own folder, so a path into a sibling skill may not exist. The source is the idea-launch copy. `scripts/check-shared-refs.ps1`, run in CI, checks that the copies are identical.
  - The marketplace version is 0.2.0. code-handoff stays at 0.1.1.
- 0.1.1:
  - handoff.ps1 serialises concurrent runs with a per-project mutex and skips a turn it has already written. Claude Code was seen firing the Stop hook twice for one turn, which wrote duplicate history entries and caused a lock error on transcript.jsonl. The mutex is released and disposed in a `finally` on every exit path, and if the 30-second wait times out the hook logs it to `hook-error.log` and continues without the lock.
  - idea-code-setup stages the `.claude/` files in `setup/dot-claude/` for the kickoff to move.
  - The install instructions name the real GitHub owner, the idea-forge README has an install line, and the stale `handoff-kit\install.ps1` references now point at `installers\windows\install.ps1`.
  - New repo tooling: `scripts/build-plugins.ps1`, `scripts/check-powershell.ps1` and GitHub Actions CI.
- 0.1.0: first version, built in a planning chat and moved into this repo.
