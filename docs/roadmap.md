# Roadmap

## M0: Repo and release tooling (current)
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
- The planning app can't write inside a project's `.claude/` folder unless that folder itself is connected. idea-code-setup therefore stages its files in `setup/dot-claude/`, and the kickoff moves them. Fixed in the repo after 0.1.0; bump to 0.1.1 in M0.
- `handoff.ps1` has been tested in one real project (Windows, Git Bash shell). `git-guard.ps1` and `install.ps1` haven't run yet.
- The handoff hook can be installed twice (plugin and installer), and then every turn is written twice.

## Changelog
- 0.1.0: first version, built in a planning chat and moved into this repo.
