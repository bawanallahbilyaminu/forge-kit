---
name: idea-code-setup
description: >
  This skill should be used when the user types /idea-code-setup, or asks to "set up Claude Code for
  this project", "create CLAUDE.md and the kickoff prompt", "get this idea ready to code" or
  "prepare the repo for Claude Code". It writes CLAUDE.md, the Claude Code settings, a git guard hook
  that enforces commit-and-push, a .gitignore and a kickoff prompt that has Claude Code create a
  private GitHub repo and start milestone M0.
metadata:
  version: "0.1.1"
---

# Idea Code Setup: ready for Claude Code

Prepare a launched project so that Claude Code can start building with one command (`/next`). It must:
- follow the documentation
- create a private GitHub repo
- commit and push after every meaningful change

## 1. Load the project

Get access to `C:\Projects-Windows` (device_bash on `$HOME/mnt/Projects-Windows`, or the local file tools). Request access if it isn't connected. Find the project folder, either the one just launched in this chat or the one the user names, and check that it has a `docs/` folder. If it doesn't, suggest `/idea-launch` first.

Read:
- `README.md`
- `docs/00-ideation/refined-concept.md`
- `docs/04-architecture/sdd.md` and the stack ADR
- `docs/06-quality/test-plan.md`
- `docs/07-project/roadmap.md`

From these, work out:
- the stack
- the package manager
- the commands for test, lint, build and run
- the repo name (the folder slug)
- the milestones

If an existing `.claude/` folder, `CLAUDE.md` or `.git` folder is present, read it and merge into it. Never overwrite the user's files blindly.

## 2. Write the files

All of these go in the project folder. Templates are in `templates/`.

**This app can't write inside a project's `.claude/` folder.** Write the Claude Code files to `setup/dot-claude/` instead. The kickoff prompt's first step has Claude Code move them into `.claude/` and delete `setup/`.

1. **`CLAUDE.md`**: fill in `templates/CLAUDE.md.template` with this project's real facts: the pitch, the docs map, the stack, the exact commands and the milestone list. Keep the Git workflow section word for word. It's the user's standing rule. Keep the file under about 150 lines, and link to the docs instead of copying them.
2. **`setup/dot-claude/settings.json`** (becomes `.claude/settings.json`): start from `templates/settings.json.template`, and add the stack's tool permissions to `allow` (for example `Bash(npm:*)`, `Bash(npx:*)`, `Bash(composer:*)`, `Bash(php:*)`, `Bash(python -m pytest:*)` or `Bash(pip install:*)`). Keep the `deny` list and the Stop hook as they are.
3. **`setup/dot-claude/hooks/git-guard.ps1`** (becomes `.claude/hooks/git-guard.ps1`): copy `templates/git-guard.ps1` unchanged. When Claude Code tries to finish a turn with uncommitted or unpushed work, the hook sends it back once to commit and push, or to explain why it didn't.
4. **`.gitignore`**: write the usual ignores for the stack, plus `.env`, `.env.*` (but not `.env.example`), `.claude/settings.local.json` and `.claude/handoff/`. If the SDD uses environment variables, also write a `.env.example` with the variable names and no values.
5. **`docs/kickoff-prompt.md`**: fill in `templates/kickoff-prompt.md.template` with the real repo name, pitch, stack and M0 deliverables from the roadmap.
6. **`setup/dot-claude/handoff/gitignore.txt`** containing `*` (becomes `.claude/handoff/.gitignore`). Add the setup step to the top of the kickoff prompt: move `setup/dot-claude/settings.json` to `.claude/settings.json`, `setup/dot-claude/hooks/git-guard.ps1` to `.claude/hooks/git-guard.ps1`, and `setup/dot-claude/handoff/gitignore.txt` to `.claude/handoff/.gitignore`, then delete `setup/`.

Check:
- `setup/dot-claude/settings.json` parses as JSON. Run `jq .` or `python -m json.tool` on it.
- No `{{...}}` placeholders are left in any of the files.

## 3. What the user does

Finish with a short **Do these first** checklist:
1. **GitHub CLI signed in.** In PowerShell, run `gh auth status`. If it says "not logged in", run `gh auth login`, choose GitHub.com, HTTPS, and sign in with the browser.
2. **Handoff installed.** For later turns, the user needs the code-handoff plugin or the one-time handoff installer, which provide `/next` and the turn summaries.
3. **Open Claude Code in the project.** In PowerShell, run `cd C:\Projects-Windows\<slug>` and then `claude`.
4. **Start it.** Paste this into Claude Code: `Read docs/kickoff-prompt.md and carry it out.` Claude Code moves its settings into place, reads the docs, creates the private repo `<slug>`, pushes the docs, and builds M0 on a branch with a pull request. After this first run, `/next` works as usual.

Then tell them: when Code finishes, run `/code-handoff` in the planning chat to review M0 and plan M1. Add the project's `.claude` folder to that chat first.

Update `_idea-forge\<slug>\02-refined-concept.md` front matter to `stage: ready-to-code`.
