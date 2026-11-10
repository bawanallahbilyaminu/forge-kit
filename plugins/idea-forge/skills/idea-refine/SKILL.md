---
name: idea-refine
description: >
  This skill should be used when the user types /idea-refine, or asks to "refine the idea",
  "brainstorm how to build this", "improve the idea after the council" or "shape this into a plan".
  It runs a council of builder agents that turn a judged idea into one refined concept, works in the
  critics' points, and iterates with the user until they approve it.
metadata:
  version: "0.1.0"
---

# Idea Refine: builders' council

Turn the idea into the strongest buildable concept. Fix the problems the critics raised, and cut anything that doesn't serve the first real users. The output is a **Refined Concept** that the user approves.

## 1. Load the idea

Find the idea's folder at `C:\Projects-Windows\_idea-forge\<slug>\`. Access it with device_bash on `$HOME/mnt/Projects-Windows`, or the local file tools, as described in /idea-council.
- If the user named the idea, or it was just judged in this chat, use that one.
- Otherwise, list the folders in `_idea-forge` and ask which idea to use.
- Read `01-council-verdict.md`.
- If there's no verdict file but the idea was discussed in this chat, build an Idea Brief from the chat and say that the council was skipped.
- If the verdict was **Don't build**, say so in one line and ask whether the user wants to refine anyway as a pivot. Then continue on their answer.

## 2. Five builders, in parallel

Read `references/builders.md`. Spawn the **five builder agents in a single message** with the Agent tool (general-purpose). Give each one:
- the Idea Brief
- the judge's verdict, the attacks that survived, and the conditions to build
- the advocate's "strongest version of this idea"
- any new notes the user added after the command
- its persona and the shared builder instructions from `references/builders.md`

Builders may search the web for tools, prices, APIs and comparable products. If the Agent tool isn't available, run the personas in turn and tell the user.

## 3. Merge them into one concept

Spawn a **Synthesizer** agent with all five proposals and the verdict. It resolves conflicts between them, preferring the simplest option that meets the conditions to build. It writes the Refined Concept in the format in `references/builders.md`.

Then spawn a quick **Red-team check** agent. Give it the Refined Concept and the list of attacks that survived. It returns a table showing, for each attack, whether it is now Addressed, Partly addressed or Open, with one line each. Put any Open items in the concept's "Open risks" section. Don't hide them.

## 4. Present it and iterate

Write `C:\Projects-Windows\_idea-forge\<slug>\02-refined-concept.md`. Give it front matter with `slug`, `name`, `type`, `date`, `status: draft` and `version: 1`, followed by the Refined Concept and the red-team table.

Show the user:
- the one-line pitch
- the MVP scope (in and out)
- the recommended approach or stack
- the business model
- the milestones
- the open risks
- any decisions only the user can make, such as a name, a budget ceiling or a target first client. Ask about these with AskUserQuestion, with at most 4 questions and a recommendation for each.

The user will push back or change things. Apply each round of changes directly to the concept, without re-running the whole council unless a change is fundamental. Bump `version` each round and keep a short changelog at the bottom. Re-run the red-team check if the scope changed a lot.

When the user approves (they say "approve", "looks good, lock it", or similar), set `status: approved` and record the date. Tell them the next step is `/idea-launch`.
