# forge-kit

Two plugins for people who plan with Claude in the app and build with Claude Code.

| Plugin | What it does |
|---|---|
| **idea-forge** | Takes an idea from a chat to a project ready to build:<br>• `/idea-council`: five critics attack the idea, an advocate answers them, and a judge gives a verdict.<br>• `/idea-refine`: five builders improve the idea into an approved concept.<br>• `/idea-launch`: creates the project folder and the full documentation set (BRD, PRD, URS, SRS, SDD, data design, wireframes, test plan, WBS and more), then has fresh agents with no context review the SRS and SDD.<br>• `/idea-code-setup`: writes CLAUDE.md, settings, a commit-and-push guard and a kickoff prompt for Claude Code. |
| **code-handoff** | Connects a planning chat to Claude Code. Claude Code writes every turn to `.claude/handoff/`. The planning chat reads it with `/code-handoff` and writes the next prompt, which Claude Code runs with `/code-handoff:next` (or `/next` if you used the installer). |

## Install

**Claude Code**
```
/plugin marketplace add bawanallahbilyaminu/forge-kit
/plugin install code-handoff@forge-kit
/plugin install idea-forge@forge-kit
```

**Claude app (planning side):** install the same plugins from the `.plugin` files on the Releases page.

code-handoff can also be installed without the plugin system, with a Windows installer. See [code-handoff's Install section](plugins/code-handoff/README.md#install) for both options, how to switch between them, and what happens if both are installed.

## Requirements
- Windows for the code-handoff hook, because it's PowerShell. macOS and Linux support is on the roadmap.
- The Claude desktop app with your projects folder connected, so idea-forge can create project folders.
- GitHub CLI (`gh`), signed in, if you want Claude Code to create repos.
- Optional: [EGM](https://github.com/google/elephant-goldfish-model) (Elephant-Goldfish Model), a plugin for designing and reviewing features with fresh agents. Projects set up by `/idea-code-setup` use it for features that need architecture decisions when it's installed (`claude plugin marketplace add google/elephant-goldfish-model`, then `claude plugin install egm@egm`), and fall back to a short design note when it isn't.

## Repo layout
```
.claude-plugin/marketplace.json   marketplace listing both plugins
plugins/idea-forge/               idea pipeline (skills + references + templates)
plugins/code-handoff/             handoff hook, /code-handoff:next command, planning-side skill
installers/windows/install.ps1    install the handoff without the plugin system
docs/                             architecture, roadmap
```

## Status
This is version 0.1, an early build that its author uses every day. Issues and pull requests are welcome.

## License
MIT
