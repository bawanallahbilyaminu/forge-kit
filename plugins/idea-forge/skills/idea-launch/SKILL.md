---
name: idea-launch
description: >
  This skill should be used when the user types /idea-launch, or asks to "launch the idea",
  "create the project folder", "set up the project in Projects-Windows" or "write all the
  documentation for this idea". It creates the project folder in C:\Projects-Windows with a folder
  structure, and writes the full documentation set for the idea's type (URS, SRS, BRD, PRD, SDD,
  data design, wireframes, test plan, WBS and more for software).
metadata:
  version: "0.1.1"
---

# Idea Launch: project folder and documentation

Turn the approved Refined Concept into a real project folder with a complete, consistent documentation set. Every document must be specific to this idea. Never ship a template with blanks. Where a fact is unknown, write it under **Open questions** in that document instead of inventing it.

## 1. Load and check

Get access to `C:\Projects-Windows` (device_bash on `$HOME/mnt/Projects-Windows`, or the local file tools). If it isn't connected, request access with device_request_folder_access, giving the reason "to create your new project folder".

Read `_idea-forge\<slug>\02-refined-concept.md` and `01-council-verdict.md`.
- If the concept's `status` isn't `approved`, tell the user and ask whether to approve it now or go back to `/idea-refine`.
- If there are no files but the idea was refined in this chat, use the chat. First save the concept file with `status: approved`, after the user confirms.

## 2. Confirm the name and type, once

With one AskUserQuestion call, confirm:
- the **folder name**: the slug by default, for example `C:\Projects-Windows\kobo-sms-bridge`
- the **idea type** from the concept, which selects the document set in `references/idea-types.md`

If the folder already exists and isn't empty, stop and ask whether to use a different name or add into it. Never overwrite existing files.

## 3. Create the folder structure

Create the folder tree for the idea type from `references/idea-types.md`. Put a `.gitkeep` in folders that start empty. Write the root `README.md` with:
- the pitch
- the status ("Docs written, build not started")
- a short map of the folders
- a "Start here" list linking the key documents

Copy the two ideation files into `docs/00-ideation/`.

## 4. Write the documents in dependency order

Use the document set for the type in `references/idea-types.md`, and for software use the section outlines in `references/doc-templates.md`. Write in layers, so that later documents build on earlier ones and the IDs stay consistent:

| Layer | Software documents |
|---|---|
| 1 | Project Brief, Project Charter |
| 2 | BRD, stakeholder register |
| 3 | PRD (with personas and user stories `US-xx`), URS (`UR-xx`) |
| 4 | SRS (functional `FR-xx`, each tracing to `UR-xx` and `US-xx`; non-functional `NFR-xx`) |
| 5 | SDD / technical specification, data design, API specification, ADR-0001 (stack choice), UI/UX wireframes and flows |
| 6 | Test plan, system test cases (`TC-xx`, each tracing to `FR-xx` or `NFR-xx`) |
| 7 | Scope statement, WBS, roadmap and milestones, risk register |
| 8 | Requirements traceability matrix (`UR` → `FR` → design section → `TC`), glossary, docs index |

Speed it up with parallel agents within a layer. Once layer N is written, spawn one Agent per document in layer N+1, in a single message. Give each agent:
- the paths of every earlier document, and tell it to read them
- that document's outline from the reference file
- the ID conventions above
- the rule: specific content only, with unknowns listed under Open questions

Agents return the document text, and the coordinator writes the files. This keeps file access in one place. After each layer, check the IDs:
- every `FR` traces to a `UR`
- every `UR` has at least one `FR`
- every `FR` has at least one `TC`

Fix any gaps before moving to the next layer.

Format rules:
- Markdown throughout.
- Wireframes are ASCII, or Mermaid for flows, stored in the `docs/05-ux/` folder.
- Diagrams such as architecture, ERD and sequence diagrams are Mermaid code blocks.
- Every document starts with a header block (title, project, version 0.1, date, status Draft, author "Idea Forge (drafted with Claude)") and ends with **Open questions** and **Revision history**.
- Size each document to what's useful. The SRS and SDD can be long. The charter is 1–2 pages.

## 5. Verify and report

When everything is written:
- List the tree to confirm every planned file exists and isn't empty.
- Grep for leftovers: `TODO`, `TBD`, `Lorem`, `<placeholder>`, `XX`. Replace them, or move each to Open questions.
- Re-check the traceability matrix against the SRS and test cases.
- Update `_idea-forge\<slug>\02-refined-concept.md` front matter to `stage: launched` with the folder path.

Reply to the user with:
- where the project is
- a compact table of the documents created, grouped by category
- the 3–5 most important open questions collected from all the documents
- the next step: for software or anything with a code repo, `/idea-code-setup`; otherwise, the first action from the roadmap

Don't paste the documents into the reply.
