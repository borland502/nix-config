# Plan Document Reviewer Prompt Template

Use this template when dispatching a plan document reviewer subagent.

**Purpose:** Verify the plan is complete, matches the spec, and has proper task decomposition.

**Dispatch after:** The complete plan is written.

**Tier — iterate cheap, confirm once on high.** A plan review loops the same
way a code review does (review → revise → re-review), and looping on the high
tier is the most expensive shape available. Run every round that may still
return issues on the **mid** tier. Only once a mid round returns Approved with
nothing changed since, spend **one** high-tier confirming pass before the plan
goes to implementers — that pass is worth it because a flawed plan multiplies
across every task dispatched from it. If it finds issues, revise and drop back
to mid; return to high only from another clean mid round. Two high-tier passes
per plan is the ceiling. Resolve `high`/`mid` via
`~/.config/instructions/agent-reference.md` § Model Tiers.

```
Subagent (general-purpose):
  description: "Review plan document"
  model: [MODEL — REQUIRED: mid for every round that may still return issues,
         including re-reviews after a revision; high only for one confirming
         pass off a clean mid round. An omitted model silently inherits the
         session's model]
  prompt: |
    You are a plan document reviewer. Verify this plan is complete and ready for implementation.

    **Plan to review:** [PLAN_FILE_PATH]
    **Spec for reference:** [SPEC_FILE_PATH]

    ## What to Check

    | Category | What to Look For |
    |----------|------------------|
    | Completeness | TODOs, placeholders, incomplete tasks, missing steps |
    | Spec Alignment | Plan covers spec requirements, no major scope creep |
    | Task Decomposition | Tasks have clear boundaries, steps are actionable |
    | Buildability | Could an engineer follow this plan without getting stuck? |

    ## Calibration

    **Only flag issues that would cause real problems during implementation.**
    An implementer building the wrong thing or getting stuck is an issue.
    Minor wording, stylistic preferences, and "nice to have" suggestions are not.

    Approve unless there are serious gaps — missing requirements from the spec,
    contradictory steps, placeholder content, or tasks so vague they can't be acted on.

    ## Output Format

    ## Plan Review

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Task X, Step Y]: [specific issue] - [why it matters for implementation]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

**Placeholders:**
- `[MODEL]` — REQUIRED: reviewer tier per the ladder above (mid while issues
  keep landing, high once for the confirming pass)
- `[PLAN_FILE_PATH]` — the plan under review
- `[SPEC_FILE_PATH]` — the spec it must match

**Reviewer returns:** Status, Issues (if any), Recommendations
