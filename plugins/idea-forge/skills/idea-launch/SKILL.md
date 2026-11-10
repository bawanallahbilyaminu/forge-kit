---
name: idea-launch
description: >
  This skill should be used when the user types /idea-launch, or asks to "launch the idea",
  "create the project folder", "set up the project in my projects folder" or "write all the
  documentation for this idea". It creates the project folder in the user's projects folder with a
  folder structure, and writes the full documentation set for the idea's type (URS, SRS, BRD, PRD, SDD,
  data design, wireframes, test plan, WBS and more for software).
metadata:
  version: "0.3.0"
---

# Idea Launch: project folder and documentation

Turn the approved Refined Concept into a real project folder with a complete, consistent documentation set. Every document must be specific to this idea. Never ship a template with blanks. Where a fact is unknown, write it under **Open questions** in that document instead of inventing it.

## 1. Load and check

Resolve the projects folder as described in `references/projects-folder.md`. Use the reason "to create your new project folder" if you need to request access.

Read `<projects>/_idea-forge/<slug>/02-refined-concept.md` and `01-council-verdict.md`.
- If the concept's `status` isn't `approved`, tell the user and ask whether to approve it now or go back to `/idea-refine`.
- If there are no files but the idea was refined in this chat, use the chat. First save the concept file with `status: approved`, after the user confirms.

## 2. Confirm the name and type, once

With one AskUserQuestion call, confirm:
- the **folder name**: the slug by default, for example `<projects>/clinic-sms-reminders`, shown to the user as the real path on their computer
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

## 5. Verify

When everything is written:
- List the tree to confirm every planned file exists and isn't empty.
- Grep for leftovers: `TODO`, `TBD`, `Lorem`, `<placeholder>`, `XX`. Replace them, or move each to Open questions.
- Re-check the traceability matrix against the SRS and test cases.

## 6. Independent review

Have reviewers with no context check the finished documents, the way Claude Code will read them. The briefs, the finding format and the summary template are in `references/reviewers.md`. Read it before starting this stage.

Run this stage only when the document set has an SRS, an SDD and a test plan: software ideas, or mixed ideas that took those documents. For every other type, skip it and add one line to the reply saying the independent review applies to software document sets only.

1. Read `docs/07-project/roadmap.md` and note M0's goal and the `FR-xx` IDs that M1 delivers, for brief B.
2. Spawn three fresh subagents with the Agent (or Task) tool, in a single message, one per brief:
   - A, gaps and contradictions: reads the SRS and SDD.
   - B, buildability: reads the SRS and SDD, and answers "Could Claude Code build M0 and M1 from these documents alone? List what it would have to guess."
   - C, traceability: reads the SRS, SDD, test plan and test cases, and checks that every requirement maps to a design element and at least one test case, and the reverse.
   Give each one only its brief and the file paths it names. Never pass the chat history, a summary of the idea, or any file from `_idea-forge/` or `docs/00-ideation/`.
3. Collect the findings. Each is a severity (blocker, major or minor), a document and section, the problem and a suggested fix.
4. Fix every blocker and major in the documents. Put each one you can't fix without the user under **Open questions** in the document it belongs to. Follow "Fixing and recording" in `references/reviewers.md`.
5. Re-run the step 5 checks on the documents you changed.
6. Append the "Independent review" summary to `docs/README.md`: the date, the three reviews, counts by severity, and what was fixed or deferred.

If no subagent tool is available, run the three reviews yourself one after another. For each, read only the files its brief names and follow the brief as written. Say in the summary that the reviews were not independent.

## 7. Report

Update `<projects>/_idea-forge/<slug>/02-refined-concept.md` front matter to `stage: launched` with the folder path.

Reply to the user with:
- where the project is
- a compact table of the documents created, grouped by category
- the independent review in one line: counts by severity, how many were fixed and how many were deferred (or that it was skipped for this idea type)
- the 3–5 most important open questions collected from all the documents, including any deferred from the review
- the next step: for software or anything with a code repo, `/idea-code-setup`; otherwise, the first action from the roadmap

Don't paste the documents into the reply.
