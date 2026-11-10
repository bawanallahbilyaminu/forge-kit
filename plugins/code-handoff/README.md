# code-handoff

This plugin stops you from screenshotting Claude Code's replies into your planning chat.

- **In Claude Code**, a Stop hook runs after every turn. It writes `.claude/handoff/last.md` with your prompt, Claude Code's reply, the files changed, the commands run and any errors. It also appends each turn to `history.md` and saves a copy of the full transcript. Typing `/code-handoff:next` (or `/next` if you used the installer) runs the prompt your planning chat left in `.claude/handoff/next.md`.
- **In the planning chat** (the Claude app), `/code-handoff` reads `last.md` and reports what Code did. It walks you through any steps only you can do, then writes the next prompt to `next.md`.

The handoff folder ignores itself in git.

## Install
Pick one way to install it on the Claude Code side. Both give you the same hook and the same command in every project: `/code-handoff:next` with the plugin, or `/next` with the installer.

| | **Plugin (recommended)** | **Installer (fallback, Windows)** |
|---|---|---|
| Use it if | you use Claude Code plugins | you don't use the plugin system |
| Install | `/plugin marketplace add bawanallahbilyaminu/forge-kit`<br>`/plugin install code-handoff@forge-kit` | From a forge-kit checkout:<br>`powershell -ExecutionPolicy Bypass -File installers\windows\install.ps1` |
| What it changes | Claude Code manages the plugin and its hook | Copies `handoff.ps1` and `next.md` into `%USERPROFILE%\.claude`, and adds a Stop hook to `%USERPROFILE%\.claude\settings.json` (backed up to `settings.json.bak-handoff`) |
| Update | `/plugin update code-handoff` | Pull the repo and run the installer again |
| Remove | `/plugin uninstall code-handoff` | `install.ps1 -Uninstall`, which removes only its own hook entry and files (backup in `settings.json.bak-handoff-uninstall`) |

**Switching from the installer to the plugin:** run `install.ps1 -Uninstall`, then install the plugin, then restart Claude Code (`claude --continue`).
**Switching from the plugin to the installer:** run `/plugin uninstall code-handoff`, then run `install.ps1`. The installer refuses to install while the plugin is enabled, unless you add `-Force`.

**If both are installed:** each turn is still written once. The plugin's copy of the hook sees the installer's Stop hook in your `settings.json` and steps aside. The first time this happens in a project, it writes one line to `.claude/handoff/hook-error.log` explaining how to remove the installer copy. Remove one of them anyway, because each turn still starts PowerShell twice.

For the planning side, install the plugin in the Claude app as well. In each planning chat, add the project's `.claude` folder with **+ → Add folder**.

## Platform support
The hook is PowerShell, so it runs on Windows only for now. A bash version for macOS and Linux is on the roadmap.
