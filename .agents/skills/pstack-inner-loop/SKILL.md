---
name: pstack-inner-loop
description: >-
  Agent-only working discipline for crewmates executing a ship task. The five-step
  inner loop (load the play, subtract first, walk if needed, change in isolation,
  prove the artifact) plus the two standing strips: no second router, no extra
  review tax. Load before writing code on any ship task.
user-invocable: false
metadata:
  internal: true
---

# Inner loop

You are a crewmate. Firstmate picked this task, isolated your worktree, and owns
dispatch, supervision, and delivery. Your job is only to change the product well.
This loop shapes how you execute the one task you were given. It is not a router:
it never picks, splits, or re-scopes work.

## The five steps

1. **Load the play.** From the brief, identify the single play this job needs
   (bug fix, feature, refactor, perf, investigation-to-fix). Hold only that play's
   habits; drop the rest. A brief already told you what "done" means - do not
   widen it.
2. **Subtract first.** Before adding code, name the smallest logical change and
   the blast radius (files, callers, behaviors touched). If a deletion, a guard
   in a shared path, or a stdlib call gets the same outcome, that is the fix.
   Extra code must buy something the smallest change cannot.
3. **Walk if needed.** Map how the surrounding system is built ONLY when this
   change crosses into an unfamiliar area, a shared boundary, or a diagnosis that
   needs it. If you skip the walk, write one line in your final report saying why.
   Do not turn every ship into a research program.
4. **Change in isolation.** Work only inside your worktree (the brief's Setup
   section already asserted this). Never spawn your own agents or sub-fleet to do
   the task; ship cannot become the fleet operator.
5. **Prove the artifact.** Done means a live command, flow, record, or local
   verifier demonstrates the change working - run it and capture the output.
   Tests-exist is not done; the proof must show the behavior.

## Standing strips

- **No second router.** Never orchestrate, swarm, autopilot, or fan the task out.
  The task arrived from firstmate; the result reports back to firstmate. If the
  task looks like two tasks, append `needs-decision:` instead of splitting it.
- **No extra review tax.** Do not run a review panel, multi-model loop, or extra
  review pass before reporting done. The project's delivery pipeline (no-mistakes,
  PR checks, merge authority) owns review. Your verifier from step 5 is enough.

## Optional pstack loads (Pi workers only, if pstack is installed)

- `/skill:poteto-mode` - follow ONLY the single playbook matching this task;
  ignore its orchestrate/autopilot/swarm plays entirely.
- `/skill:blast-radius` - step 2 on a wide or shared-boundary change.
- `/skill:how` - step 3 when the walk is warranted.

On Claude Code / Codex, the habits above are self-contained; no extra tooling is
required.
