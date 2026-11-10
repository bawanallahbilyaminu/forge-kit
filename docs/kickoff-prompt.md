# Kickoff: forge-kit

This repo already contains two working plugins (idea-forge and code-handoff), built in a planning chat. Your job in this session is **set-up and milestone M0 only**.

0. **Finish the Claude Code setup first.** The planning chat can't write inside `.claude/`, so it left the files in `setup/dot-claude/`:
   - Move `setup/dot-claude/settings.json` to `.claude/settings.json`.
   - Move `setup/dot-claude/hooks/git-guard.ps1` to `.claude/hooks/git-guard.ps1`.
   - Move `setup/dot-claude/handoff/gitignore.txt` to `.claude/handoff/.gitignore`.
   - Then delete the `setup/` folder and the stray empty file `.claude/x`.
   - Tell me if Claude Code asks me to approve the settings or hook change.
1. **Read first:** `CLAUDE.md`, `README.md`, `docs/architecture.md`, `docs/roadmap.md`, and skim each plugin's files. Follow CLAUDE.md, especially the Git workflow and the PowerShell 5.1 rules.
2. **Check before doing anything:** run `gh auth status`. If GitHub CLI isn't signed in, stop and tell me to run `gh auth login`.
3. **Git and GitHub:**
   - Run `git init -b main` if this folder isn't a repo yet.
   - Create the repo with `gh repo create forge-kit --private --source . --remote origin --description "Claude plugins: idea-forge (idea to project pipeline) and code-handoff (planning chat <-> Claude Code handoff)"`. If a repo with that name already exists on my account, stop and ask me.
   - Commit everything as `chore: import forge-kit v0.1.0 plugins`, then run `git push -u origin main`.
4. **M0** (see `docs/roadmap.md`): work on the branch `m0-repo-tooling`.
   - Replace `<owner>` in the README files with the real GitHub owner from `gh repo view --json owner`.
   - Run `claude plugin validate` on both plugins and on the marketplace, and fix what it reports.
   - Parse-check every `.ps1` file with the PowerShell parser, and fix any errors.
   - Write `scripts/build-plugins.ps1`, which zips each plugin folder's contents into `dist/<name>.plugin` (`dist/` is gitignored), and run it.
   - Check that `installers/windows/install.ps1` points at `plugins/code-handoff/scripts/handoff.ps1` and `plugins/code-handoff/commands/next.md`. **Don't run the installer.**
   - Add a GitHub Actions workflow that validates the JSON and parse-checks the PowerShell on `windows-latest`.
   - Commit after each step and push after each commit. Then open a PR with `gh pr create`. Don't merge it.
5. **Report back:**
   - the repo URL
   - what was fixed
   - the validation, parse and CI results
   - the PR link
   - the paths of the built `.plugin` files
   - a **Your steps** list of anything only I can do
