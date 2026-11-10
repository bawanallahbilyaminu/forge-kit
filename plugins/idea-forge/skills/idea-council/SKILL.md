---
name: idea-council
description: >
  This skill should be used when the user types /idea-council, or asks to "critique my idea",
  "put this idea before the council", "is this a good idea", "tear this idea apart" or
  "give me a verdict on this idea". It runs a council of independent critic agents that attack the
  idea, an advocate who answers them, and a judge who gives a Build / Build with changes /
  Don't build verdict.
metadata:
  version: "0.1.0"
---

# Idea Council: brutal critique and verdict

The user has usually described ("yarned") the idea earlier in this conversation, then invoked this command, sometimes with extra notes after it. The job is to decide honestly whether the idea is worth building. Don't cheerlead. A "Don't build" that saves the user months is a good outcome.

Stance: **brutal but fair.** Critics try hard to kill the idea, but every attack needs a reason, evidence where it can be found, and a severity rating. The judge can still say Build.

## 1. Write the idea brief

Pull together everything the user said about the idea in this conversation, plus any notes after the command. Write a one-page **Idea Brief**:
- working name
- one-line pitch
- the problem, and who has it
- the proposed solution
- target users and market (the location, for example Sokoto, Nigeria or the world)
- how it makes money or creates value
- the user's own advantages (skills, access, existing projects)
- known constraints (budget, time, team)
- the idea type: software, content, service, research, hardware, programme or other

Fill gaps only from what the user said or from facts that are reasonable to look up. Label anything assumed as **Assumption**. If a gap would change the verdict (for example, no idea who the user is), ask at most 2 short questions with AskUserQuestion. Otherwise proceed and list the assumptions.

Pick a kebab-case **slug** for the idea, such as `kobo-sms-bridge`.

## 2. Round 1: five critics, in parallel

Read `references/personas.md`. Spawn the **five critic agents in a single message** with the Agent tool (general-purpose), so they work independently and in parallel. Give each one:
- the full Idea Brief
- its persona section from `references/personas.md`
- the shared critic instructions and output format from that file

Critics may use web search. The Competition critic **must** search for existing products, and the Market critic should look for demand signals. Wait for all five to finish. Don't summarise them while they run.

If the Agent tool isn't available, play each persona in turn in separate, clearly headed passes, and tell the user the council ran without independent agents.

## 3. Round 2: the advocate answers

Spawn one **Advocate** agent (persona in `references/personas.md`). Give it the brief and all five critiques. It must answer the strongest attacks with arguments, evidence or design changes, and concede the ones it can't answer. Conceding is allowed and expected.

## 4. Round 3: the judge rules

Spawn one **Judge** agent, a fresh agent that hasn't written anything yet. Give it the brief, the five critiques and the advocate's reply, plus the judge instructions from `references/personas.md`. The judge returns the verdict in the exact format given there:
- **Verdict:** Build / Build with changes / Don't build
- a confidence level
- a scorecard
- the attacks that survived
- the conditions to build
- the cheapest way to test the idea in 1–2 weeks

## 5. Save and present

Get access to the user's `C:\Projects-Windows` folder:
- If it's connected, use device_bash on `$HOME/mnt/Projects-Windows`, or the local file tools if this session runs on the computer.
- If it isn't, request access with device_request_folder_access (reason: "to save your idea's council verdict"), or ask the user to add it with + → Add folder.
- If access isn't possible, keep everything in the chat and say so.

Write `C:\Projects-Windows\_idea-forge\<slug>\01-council-verdict.md` containing the Idea Brief, the full critiques under a heading for each critic, the advocate's reply and the judge's verdict. Start the file with front matter: `slug`, `name`, `type`, `date`, `verdict`, `stage: council`.

Reply to the user in this order:
1. The verdict and confidence level, stated plainly in the first line.
2. The scorecard as a compact table.
3. The 3 most damaging attacks that survived, with one line each.
4. The conditions to build.
5. The cheapest validation test.
6. The next step: `/idea-refine` if the verdict is Build or Build with changes. If it's Don't build, say what would have to change for a Build verdict, and offer `/idea-refine` anyway in case the user wants to pivot.

Don't paste the full critiques into the reply. They're in the file.

## Re-running

If the user changes the idea and runs the command again, overwrite the file. Keep the old verdict in a `## Previous verdicts` section at the bottom with its date and a one-line summary.
