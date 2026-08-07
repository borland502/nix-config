---
name: git-request-review
description: Use when completing tasks, implementing major features, or before merging to verify work meets requirements
---

# Requesting Code Review

Dispatch a code reviewer subagent to catch issues before they cascade. The reviewer gets precisely crafted context for evaluation — never your session's history. This keeps the reviewer focused on the work product, not your thought process, and preserves your own context for continued work.

**Core principle:** Review early, review often.

## When to Request Review

**Mandatory:**
- After each task in subagent-driven development
- After completing major feature
- Before merge to main

**Optional but valuable:**
- When stuck (fresh perspective)
- Before refactoring (baseline check)
- After fixing complex bug

## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git rev-parse HEAD~1)  # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch code reviewer subagent:**

Dispatch a `general-purpose` subagent, filling the template at [code-reviewer.md](code-reviewer.md)

Pick the tier with the escalation ladder below, and always name it explicitly —
an omitted model silently inherits your session's model, which defeats the
ladder in both directions.

**Escalation ladder — iterate cheap, confirm once on high:**

Review loops are where top-tier credits vanish: each round of findings triggers
a fix and another full read of the diff. So **never iterate on the high tier.**

1. Run every round that may still return findings on the **mid** tier (**low**
   for a trivial diff — typo, style, single-file): review → fix → re-review, all
   at the same tier. Stay here as long as findings keep landing.
2. When a cheap round comes back clean — no Critical or Important findings, and
   nothing changed since — dispatch **one** high-tier confirming pass. This is
   the final/pre-merge review of a substantive diff (correctness, security,
   concurrency, broad or multi-file change). A trivial diff never needs it.
3. If the high-tier pass returns findings, fix them and drop back to the cheap
   tier for the re-review. Return to high only from another clean cheap round.
4. Two high-tier passes per branch is the ceiling. If the second still returns
   Critical findings, stop and bring it to the human rather than looping.

Resolve `high`/`mid`/`low` to your harness's model via
`~/.config/instructions/agent-reference.md` § Model Tiers. Never write a
versioned model ID.

**Placeholders:**
- `{DESCRIPTION}` - Brief summary of what you built
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{BASE_SHA}` - Starting commit
- `{HEAD_SHA}` - Ending commit

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with reasoning)

## Example

```
[Just completed Task 2: Add verification function]

You: Let me request code review before proceeding.

BASE_SHA=$(git log --oneline | grep "Task 1" | head -1 | awk '{print $1}')
HEAD_SHA=$(git rev-parse HEAD)

[Dispatch code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  PLAN_OR_REQUIREMENTS: Task 2 from ~/.cache/copilot/2026-07-20-deployment-plan.md
  BASE_SHA: a7981ec
  HEAD_SHA: 3df7661

[Subagent returns]:
  Strengths: Clean architecture, real tests
  Issues:
    Important: Missing progress indicators
    Minor: Magic number (100) for reporting interval
  Assessment: Ready to proceed

You: [Fix progress indicators]
[Continue to Task 3]
```

## Integration with Workflows

**Subagent-Driven Development:**
- Review after EACH task
- Catch issues before they compound
- Fix before moving to next task

**Executing Plans:**
- Review after each task or at natural checkpoints
- Get feedback, apply, continue

**Ad-Hoc Development:**
- Review before merge
- Review when stuck

## Red Flags

**Never:**
- Skip review because "it's simple"
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback
- Run a review loop on the high tier — findings → fix → re-review is a cheap-tier
  loop; the high tier gets one confirming pass off a clean round
- Re-review a high-tier pass's own findings on the high tier

**If reviewer wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

See template at: [code-reviewer.md](code-reviewer.md)
