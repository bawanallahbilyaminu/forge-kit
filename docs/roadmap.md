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
- [x] handoff for macOS and Linux (`handoff.mjs`), with tests ported from `tests/handoff/handoff.Tests.ps1`. Done in code-handoff 0.3.0: `plugins/code-handoff/scripts/handoff.mjs`, with `tests/handoff/handoff.test.mjs` (36 tests) and `parity.test.mjs` (`last.md` matches `handoff.ps1`'s output for the shared fixtures).
- [x] The code-handoff `hooks.json` picks the right script for each platform. Done in code-handoff 0.4.0: one shell-form hook that is valid as sh and as PowerShell. It runs `handoff.ps1` under Git Bash and under PowerShell on Windows, and `handoff.mjs` under `sh` on macOS, Linux and WSL (exiting 0 without Node). See "One hook command for every platform" in `docs/architecture.md`. Tested by `tests/handoff/hook-command.test.mjs` on all three OSes.

## M3: Tests
- [x] Fixture transcripts (synthetic) and Pester tests for the handoff parser: a normal turn, a turn with tool errors, an interrupted turn, a slash command turn and a lagging transcript. Done on branch `m3-tests`: `tests/handoff/handoff.Tests.ps1` (Pester 3.4.0) also covers duplicate runs, the lock timeout, the home-folder skip, and the leftovers and stale-hook cases from code-handoff 0.2.2. Run it with `scripts/run-tests.ps1`, which CI also runs.
- [x] Pester tests for git-guard: a clean repo, a dirty repo, unpushed commits, no upstream, not a repo, and `stop_hook_active`. Done on branch `m3-tests`: `tests/git-guard/git-guard.Tests.ps1` tests the shipped template (identical to this repo's live `.claude/hooks/git-guard.ps1`). It uses temp repos with a local bare remote, and also covers counting several changes, being behind the upstream, no remote, no commits yet, the `cwd` fallback and bad JSON.

## M4: Public release
The user decided these in the planning chat on 2026-11-10:
- The first public release is **v0.5.0**, matching the marketplace version.
- Claude Code draws simple plugin icons for the user to approve.
- The README gets a diagram of the loop now, and a GIF later.

The checklist:
- [x] Plugin icons (`scripts/make-icons.ps1`, `plugins/*/.claude-plugin/icon.png`). `claude plugin validate` no longer warns `ICON_MISSING`.
- [x] A public README with diagrams of the handoff loop and the idea-forge pipeline, a quick start, platform support, contributing and a license section.
- [x] `CHANGELOG.md` in Keep a Changelog format.
- [x] Draft release notes: `docs/release-notes/v0.5.0.md`.
- [x] Pre-release scan of the tree and the git history for personal data and secrets (reported in the M4 PR).
- [x] The user approves the icons. They were approved as drawn on 2026-11-10.
- [x] Tag `v0.5.0`: annotated, on main at `75c0b9f` (the PR #6 merge), pushed on 2026-11-10.
- [x] A draft GitHub Release "forge-kit v0.5.0", with `dist/code-handoff.plugin` and `dist/idea-forge.plugin` built from that commit.
- [ ] The user publishes the release.
- [ ] A GIF of the loop in the README.
- [ ] The user makes the repo public.

## Known issues
- The planning app can't write inside a project's `.claude/` folder unless that folder itself is connected. idea-code-setup therefore stages its files in `setup/dot-claude/`, and the kickoff moves them. Shipped in 0.1.1.
- `handoff.ps1` has been tested in one real project (Windows, Git Bash shell). `git-guard.ps1` is now live in this repo as its Stop hook. The plugin route (code-handoff 0.2.0 from the local marketplace, user scope) was tested live on Windows on 2026-11-10, including the double-install guard and `-Uninstall`: with both installed, the plugin copy stepped aside and wrote the one-time note in `hook-error.log`, and after `install.ps1 -Uninstall` the plugin copy wrote the turn on its own.

## Changelog
See [CHANGELOG.md](../CHANGELOG.md) at the repo root.
