# Idea Forge

Four commands that take an idea from a conversation to a ready-to-build project.

| Command | What it does | Saves |
|---|---|---|
| `/idea-council` | Five critics attack the idea separately, an advocate answers them, and a judge gives a verdict: Build, Build with changes, or Don't build. | `C:\Projects-Windows\_idea-forge\<slug>\01-council-verdict.md` |
| `/idea-refine` | Five builders improve the idea and work in the critics' points. You approve the refined concept. | `...\<slug>\02-refined-concept.md` |
| `/idea-launch` | Creates `C:\Projects-Windows\<slug>\` and writes the documentation set for the idea's type: the full SE set for software, or a fitting set for content, services, research, hardware or programmes. | `C:\Projects-Windows\<slug>\docs\` |
| `/idea-code-setup` | Adds CLAUDE.md, Claude Code settings, a git guard hook and a kickoff prompt. On its first run, Claude Code creates a private GitHub repo and then commits and pushes after every meaningful change. | `C:\Projects-Windows\<slug>\` |

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

Each stage reads the previous stage's file, so you can continue in a different chat. Name the idea, or the chat will list the ideas in `_idea-forge`.

## Requirements
- The Claude desktop app, with `C:\Projects-Windows` connected. The first command asks for access.
- GitHub CLI (`gh`) signed in on your computer. Claude Code uses it to create the repo.
- The handoff kit installed once (`handoff-kit\install.ps1`). It gives `/next` and `/code-handoff`.
