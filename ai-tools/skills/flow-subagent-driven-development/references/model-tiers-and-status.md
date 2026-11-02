# Model Selection

Pick a capability **tier** for each role — `high`, `mid`, or `low` — then
resolve the tier to your harness's model via
`~/.config/instructions/agent-reference.md` § Model Tiers (Claude Code:
tier aliases; Copilot CLI: the current sol/terra/luna slugs). Never write a
versioned model ID. Use the lowest tier that can handle the role to
conserve cost and increase speed.

**Mechanical implementation tasks** (isolated functions, clear specs, 1-2 files): **low** tier. Most implementation tasks are mechanical when the plan is well-specified.

**Integration and judgment tasks** (multi-file coordination, pattern matching, debugging): **mid** tier.

**Architecture and design tasks**: **high** tier.

**Review tasks — iterate cheap, confirm once on high.** A review loop is the
most expensive shape in this workflow: every round of findings costs a fix
plus another full read of the diff. Never iterate on the high tier.

- **Per-task reviews stay on the cheap tier throughout** — **mid**, or **low**
  for a small mechanical diff. Review → fix → re-review all run at the same
  tier; do not escalate a task review to high because it returned findings.
- **The final whole-branch review is the single high-tier gate**, and you
  enter it only from a clean cheap round: dispatch it on **mid** first, and
  spend the high tier only once that round comes back with no Critical or
  Important findings. Dispatch it as a subagent either way — reviewing inline
  drains your own context on a fresh read.
- If the high-tier pass returns findings, fix them and drop back to **mid**
  for the re-review. Return to high only from another clean mid round.
- **Two high-tier passes per branch is the ceiling.** If the second still
  returns Critical findings, stop and bring it to the human — a third pass
  burns exactly the credits this ladder exists to save.

**Always specify the model explicitly when dispatching a subagent.** An
omitted model inherits your session's model — the mid default, or whatever
you switched to — which is the wrong tier as often as not: over-powered for
mechanical work, under-powered for a substantive review. Either way it
silently defeats this section.

**Turn count beats token price.** Wall-clock and context cost scale with how
many turns a subagent takes, and the cheapest models routinely take 2-3× the
turns on multi-step work — costing more overall. Use the mid tier as the
floor for reviewers of anything but a small mechanical diff, and for
implementers working from prose descriptions.
When the task's plan text contains the complete code to write, the
implementation is transcription plus testing: use the cheapest tier for
that implementer. Single-file mechanical fixes also take the cheapest tier.

**Task complexity signals (implementation tasks):**

- Touches 1-2 files with a complete spec → cheap model
- Touches multiple files with integration concerns → standard model
- Requires design judgment or broad codebase understanding → most capable model

## Handling Implementer Status

Implementer subagents report one of four statuses. Handle each appropriately:

**DONE:** Generate the review package (`scripts/review-package BASE HEAD`, from this skill's directory — it prints the unique file path it wrote; BASE is the commit you recorded before dispatching the implementer — never `HEAD~1`, which silently drops all but the last commit of a multi-commit task), then dispatch the task reviewer with the printed path.

**DONE_WITH_CONCERNS:** The implementer completed the work but flagged doubts. Read the concerns before proceeding. If the concerns are about correctness or scope, address them before review. If they're observations (e.g., "this file is getting large"), note them and proceed to review.

**NEEDS_CONTEXT:** The implementer needs information that wasn't provided. Provide the missing context and re-dispatch.

**BLOCKED:** The implementer cannot complete the task. Assess the blocker:

1. If it's a context problem, provide more context and re-dispatch with the same model
2. If the task requires more reasoning, re-dispatch with a more capable model
3. If the task is too large, break it into smaller pieces
4. If the plan itself is wrong, escalate to the human

**Never** ignore an escalation or force the same model to retry without changes. If the implementer said it's stuck, something needs to change.
