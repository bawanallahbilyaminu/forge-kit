# forge-kit

Two plugins for people who plan with Claude in the app and build with Claude Code.

| Plugin | What it does |
|---|---|
| **idea-forge** | Takes an idea from a chat to a project ready to build:<br>• `/idea-council`: five critics attack the idea, an advocate answers them, and a judge gives a verdict.<br>• `/idea-refine`: five builders improve the idea into an approved concept.<br>• `/idea-launch`: creates the project folder and the full documentation set (BRD, PRD, URS, SRS, SDD, data design, wireframes, test plan, WBS and more).<br>• `/idea-code-setup`: writes CLAUDE.md, settings, a commit-and-push guard and a kickoff prompt for Claude Code. |
| **code-handoff** | Connects a planning chat to Claude Code. Claude Code writes every turn to `.claude/handoff/`. The planning chat reads it with `/code-handoff` and writes the next prompt, which Claude Code runs with `/next`. |

## Install

**Claude Code**
```
/plugin marketplace add <owner>/forge-kit
/plugin install code-handoff@forge-kit
/plugin install idea-forge@forge-kit
```

**Claude app (planning side):** install the same plugins from the `.plugin` files on the Releases page.

## Requirements
- Windows for the code-handoff hook, because it's PowerShell. macOS and Linux support is on the roadmap.
- The Claude desktop app with your projects folder connected, so idea-forge can create project folders.
- GitHub CLI (`gh`), signed in, if you want Claude Code to create repos.

## Repo layout
```
.claude-plugin/marketplace.json   marketplace listing both plugins
plugins/idea-forge/               idea pipeline (skills + references + templates)
plugins/code-handoff/             handoff hook, /next command, planning-side skill
installers/windows/install.ps1    install the handoff without the plugin system
docs/                             architecture, roadmap
```

## Status
This is version 0.1, an early build that its author uses every day. Issues and pull requests are welcome.

## License
MIT
