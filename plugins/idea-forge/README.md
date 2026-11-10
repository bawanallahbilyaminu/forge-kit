# Idea Forge

Four commands that take an idea from a conversation to a ready-to-build project. Below, `<projects>` is your projects folder (see Requirements).

| Command | What it does | Saves |
|---|---|---|
| `/idea-council` | Five critics attack the idea separately, an advocate answers them, and a judge gives a verdict: Build, Build with changes, or Don't build. | `<projects>\_idea-forge\<slug>\01-council-verdict.md` |
| `/idea-refine` | Five builders improve the idea and work in the critics' points. You approve the refined concept. | `...\<slug>\02-refined-concept.md` |
| `/idea-launch` | Creates `<projects>\<slug>\` and writes the documentation set for the idea's type: the full SE set for software, or a fitting set for content, services, research, hardware or programmes. | `<projects>\<slug>\docs\` |
| `/idea-code-setup` | Adds CLAUDE.md, Claude Code settings, a git guard hook and a kickoff prompt. On its first run, Claude Code creates a private GitHub repo and then commits and pushes after every meaningful change. | `<projects>\<slug>\` |

## Install
In Claude Code (2.1.275 or later):
```
/plugin install idea-forge --marketplace bawanallahbilyaminu/forge-kit
```
On older versions, run `/plugin marketplace add bawanallahbilyaminu/forge-kit` and then `/plugin install idea-forge@forge-kit`. In the Claude app, install it from the `.plugin` file on the Releases page.

## How to use it
1. Describe your idea in a chat, then type `/idea-council`.
2. If the verdict is Build or Build with changes, type `/idea-refine`. Push back until you're happy, then say "approve".
3. Type `/idea-launch`.
4. For software, type `/idea-code-setup`. Then open Claude Code in the new folder and type `/next`, which runs the kickoff prompt.

Each stage reads the previous stage's file, so you can continue in a different chat. Name the idea, or the chat will list the ideas in `<projects>\_idea-forge`.

## Requirements
- The Claude desktop app, with your projects folder connected. The default is `C:\Projects-Windows` on Windows and `~/Projects` on macOS and Linux. The first command asks once where to keep your projects, saves the answer in `<projects>\_idea-forge\config.json`, and asks for access to that folder. To move it later, tell any idea-forge command to use a different folder, or edit `projectsDir` in that file.
- GitHub CLI (`gh`) signed in on your computer. Claude Code uses it to create the repo.
- code-handoff installed once, either as the plugin or with the Windows installer (`installers\windows\install.ps1` in forge-kit), but not both. It gives `/next` and `/code-handoff`.
