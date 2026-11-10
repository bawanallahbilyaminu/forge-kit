# Independent reviewer briefs

Adapted from the "goldfish" reviewers in EGM (github.com/google/elephant-goldfish-model): a reviewer that remembers nothing of how the documents were made reads them the way Claude Code will, with only what is on the page.

## How to use these briefs

- Send each brief below as the whole prompt of a fresh subagent. Replace `<project>` with the project folder's real path, and fill in the M1 scope line in brief B (see below).
- Send the three in a single message so they run in parallel.
- Add nothing else to the prompt: no chat history, no summary of the idea, no refined concept or council verdict, and no paths into `_idea-forge/` or `docs/00-ideation/`.
- Each reviewer only reads and reports. The coordinator makes every fix.

**Brief B's scope line.** Before spawning, read `docs/07-project/roadmap.md` and copy two facts into brief B: M0's goal, and the list of `FR-xx` IDs that M1 delivers. Copy the IDs only, not the roadmap text. This gives the reviewer a scope without giving it another document to lean on.

## Shared rules (included in every brief)

Every brief below ends with these rules. Keep them in the prompt word for word.

```
Rules:
- Read only the files listed above. Do not open any other file in the project, and do not search the web.
- Do not edit or create any file. Report only.
- Judge the documents as written. If something is not on the page, it does not exist.
- Return at most 15 findings, most severe first, as a Markdown table with these columns:
  | Severity | Document and section | Problem | Suggested fix |
  Severity is one of:
  - blocker: the build cannot proceed, or would build the wrong thing, without an answer.
  - major: a builder would have to guess something important, or two statements conflict.
  - minor: wording, a small gap, or an inconsistency a builder could work around.
- "Document and section" names the file and the heading, for example "srs.md, 3.2 FR-04".
- Keep each problem and fix to one or two sentences. Suggest a concrete fix, not "clarify this".
- If you find nothing at a severity level, say so in one line after the table.
```

## Brief A: gaps and contradictions

```
You are reviewing two planning documents for a software project, with no other context.

Read:
- <project>/docs/03-requirements/srs.md
- <project>/docs/04-architecture/sdd.md

Find:
- Contradictions: the SRS and SDD disagree, or a document disagrees with itself (numbers, limits, names, behaviour, data fields, roles).
- Gaps: a requirement with no acceptance criterion, a behaviour that is mentioned but never specified (error cases, empty states, limits, permissions, time zones, offline, retries), or an SDD component that no requirement asks for.
- Ambiguity: words like "fast", "secure", "user-friendly" or "etc." with no measurable meaning, and terms used in more than one sense.

<shared rules>
```

## Brief B: buildability

```
You are a senior engineer about to build a software project with Claude Code. You have only two documents and no one to ask.

Read:
- <project>/docs/03-requirements/srs.md
- <project>/docs/04-architecture/sdd.md

Scope: M0 is "<M0 goal from the roadmap>". M1 delivers <FR-xx list from the roadmap>.

Answer one question: could Claude Code build M0 and M1 from these documents alone? List what it would have to guess. Check for:
- the stack, versions, hosting and tooling M0 needs to scaffold the repo, CI and tests
- data models: entities, fields, types, keys and constraints for everything M1 stores
- interfaces: endpoints, messages, file formats or screens M1 needs, with inputs, outputs and errors
- external services: which ones, how they are called and authenticated, and what happens when they fail
- configuration and secrets: what is configurable and where it comes from
- anything an M1 requirement depends on that the SDD never designs

For each guess, say what Claude Code would most likely assume, and why that could be wrong.

<shared rules>
```

## Brief C: traceability

```
You are checking traceability across three planning documents for a software project, with no other context.

Read:
- <project>/docs/03-requirements/srs.md
- <project>/docs/04-architecture/sdd.md
- <project>/docs/06-quality/test-plan.md
- <project>/docs/06-quality/test-cases.md

Check both directions:
- Every FR-xx and NFR-xx in the SRS maps to at least one SDD element (a component, module, data entity, interface or section) and at least one TC-xx.
- Every TC-xx traces to an FR-xx or NFR-xx that exists in the SRS, and actually tests what that requirement says.
- Every SDD component traces back to at least one requirement.
- IDs are unique and referenced consistently: no missing, duplicated or renamed IDs.
- NFRs have tests that can measure them (a number, a tool, a pass condition).

Also return, after the findings table, a short list of the requirement IDs with no design element and the requirement IDs with no test case.

<shared rules>
```

When sending a brief, replace the `<shared rules>` line with the shared rules block above.

## Fixing and recording

- Merge duplicate findings across the three reviews, keeping the higher severity.
- Fix every blocker and major in the documents themselves. If a fix changes an ID or a requirement, update the traceability matrix, the test cases and any document that cites it.
- Fix a minor when the fix is quick and certain. Otherwise leave it.
- If a blocker or major can't be fixed without a decision only the user can make, don't invent an answer. Add it under **Open questions** in the document it belongs to, marked "(from independent review)".
- Add an entry to the Revision history of each document you changed: version 0.2, "Fixes from independent review".

## Summary for docs/README.md

Append this section to the project's `docs/README.md`:

```markdown
## Independent review

Date: <YYYY-MM-DD>. Reviewers: <three fresh subagents that saw only the listed files | one agent, run three times in turn (not independent; see below)>.

| Review | Files read | Blockers | Majors | Minors |
|---|---|---|---|---|
| Gaps and contradictions | srs.md, sdd.md | n | n | n |
| Buildability (M0 and M1) | srs.md, sdd.md | n | n | n |
| Traceability | srs.md, sdd.md, test-plan.md, test-cases.md | n | n | n |

Fixed: <one line per fix, naming the document and section>.
Deferred to Open questions: <one line per item, naming the document>.
Left as is: <count> minors.
```

If the reviews were not independent, add one sentence after the table: "No subagent tool was available, so the same agent ran the three reviews one after another, reading only the listed files. It had already written the documents, so these reviews are not independent."
