# code-handoff

This plugin stops you from screenshotting Claude Code's replies into your planning chat.

- **In Claude Code**, a Stop hook runs after every turn. It writes `.claude/handoff/last.md` with your prompt, Claude Code's reply, the files changed, the commands run and any errors. It also appends each turn to `history.md` and saves a copy of the full transcript. The `/next` command runs the prompt your planning chat left in `.claude/handoff/next.md`.
- **In the planning chat** (the Claude app), `/code-handoff` reads `last.md` and reports what Code did. It walks you through any steps only you can do, then writes the next prompt to `next.md`.

The handoff folder ignores itself in git.

## Install
Install it in one of two ways. Don't do both, or every turn gets written twice.
- **As a Claude Code plugin:** run `/plugin marketplace add bawanallahbilyaminu/forge-kit`, then `/plugin install code-handoff@forge-kit`. The hook and `/next` then work in every project.
- **Without plugins (Windows):** run `powershell -ExecutionPolicy Bypass -File installers\windows\install.ps1` from the repo. This copies the hook and `/next` into `%USERPROFILE%\.claude`.

For the planning side, install the plugin in the Claude app as well. In each planning chat, add the project's `.claude` folder with **+ → Add folder**.

## Platform support
The hook is PowerShell, so it runs on Windows only for now. A bash version for macOS and Linux is on the roadmap.
