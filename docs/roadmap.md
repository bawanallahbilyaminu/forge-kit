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
- Make the projects folder configurable in idea-forge. Ask once and remember the answer in `<projects>/_idea-forge/config.json`. Default to `C:\Projects-Windows` on Windows and `~/Projects` elsewhere.
- Remove the author-specific wording from the skills. Keep the local context examples, such as Hausa and Sokoto, as examples only.
- Document the two ways to install code-handoff (plugin or installer), and make sure they can't both run.

## M2: macOS and Linux
- A bash version of `handoff.sh` and `git-guard.sh` that needs only POSIX tools plus `jq`, or a single Node script if that's simpler. Record the choice in an ADR.
- `hooks.json` picks the right script for each platform.

## M3: Tests
- Fixture transcripts (synthetic) and Pester tests for the handoff parser: a normal turn, a turn with tool errors, an interrupted turn, a slash command turn and a lagging transcript.
- Pester tests for git-guard: a clean repo, a dirty repo, unpushed commits, no upstream, not a repo, and `stop_hook_active`.

## M4: Public release
- Polish the README with a GIF of the loop, write a CHANGELOG, tag v0.1.0, and attach the `.plugin` files to a GitHub Release.
- The user makes the repo public.

## Known issues
- The planning app can't write inside a project's `.claude/` folder unless that folder itself is connected. idea-code-setup therefore stages its files in `setup/dot-claude/`, and the kickoff moves them. Shipped in 0.1.1.
- `handoff.ps1` has been tested in one real project (Windows, Git Bash shell). `git-guard.ps1` is now live in this repo as its Stop hook. `install.ps1` hasn't run yet (its source paths were checked in M0).
- The plugins have no icon yet, so `claude plugin validate` warns `ICON_MISSING`. It needs a square PNG (512-2048 px) at `.claude-plugin/icon.png` in each plugin.
- The handoff hook can be installed twice (plugin and installer), and then every turn is written twice.

## Changelog
- 0.1.1:
  - handoff.ps1 serialises concurrent runs with a per-project mutex and skips a turn it has already written. Claude Code was seen firing the Stop hook twice for one turn, which wrote duplicate history entries and caused a lock error on transcript.jsonl. The mutex is released and disposed in a `finally` on every exit path, and if the 30-second wait times out the hook logs it to `hook-error.log` and continues without the lock.
  - idea-code-setup stages the `.claude/` files in `setup/dot-claude/` for the kickoff to move.
  - The install instructions name the real GitHub owner, the idea-forge README has an install line, and the stale `handoff-kit\install.ps1` references now point at `installers\windows\install.ps1`.
  - New repo tooling: `scripts/build-plugins.ps1`, `scripts/check-powershell.ps1` and GitHub Actions CI.
- 0.1.0: first version, built in a planning chat and moved into this repo.
