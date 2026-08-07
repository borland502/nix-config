# Spec Document Reviewer Prompt Template

Use this template when dispatching a spec document reviewer subagent.

**Purpose:** Verify the spec is complete, consistent, and ready for implementation planning.

**Dispatch after:** Spec document is written to the path supplied as `SPEC_FILE_PATH`.

**Tier — iterate cheap, confirm once on high.** A spec review loops the same
way a code review does (review → revise → re-review), and looping on the high
tier is the most expensive shape available. Run every round that may still
return issues on the **mid** tier. Only once a mid round returns Approved with
nothing changed since, spend **one** high-tier confirming pass before the spec
goes to planning — that pass is worth it because a flawed spec propagates into
the plan and then into every task. If it finds issues, revise and drop back to
mid; return to high only from another clean mid round. Two high-tier passes per
spec is the ceiling. Resolve `high`/`mid` via
`~/.config/instructions/agent-reference.md` § Model Tiers.

```
Subagent (general-purpose):
  description: "Review spec document"
  model: [MODEL — REQUIRED: mid for every round that may still return issues,
         including re-reviews after a revision; high only for one confirming
         pass off a clean mid round. An omitted model silently inherits the
         session's model]
  prompt: |
    You are a spec document reviewer. Verify this spec is complete and ready for planning.

    **Spec to review:** [SPEC_FILE_PATH]

    ## What to Check

    | Category | What to Look For |
    |----------|------------------|
    | Completeness | TODOs, placeholders, "TBD", incomplete sections |
    | Consistency | Internal contradictions, conflicting requirements |
    | Clarity | Requirements ambiguous enough to cause someone to build the wrong thing |
    | Scope | Focused enough for a single plan — not covering multiple independent subsystems |
    | YAGNI | Unrequested features, over-engineering |

    ## Calibration

    **Only flag issues that would cause real problems during implementation planning.**
    A missing section, a contradiction, or a requirement so ambiguous it could be
    interpreted two different ways — those are issues. Minor wording improvements,
    stylistic preferences, and "sections less detailed than others" are not.

    Approve unless there are serious gaps that would lead to a flawed plan.

    ## Output Format

    ## Spec Review

    **Status:** Approved | Issues Found

    **Issues (if any):**
    - [Section X]: [specific issue] - [why it matters for planning]

    **Recommendations (advisory, do not block approval):**
    - [suggestions for improvement]
```

**Placeholders:**
- `[MODEL]` — REQUIRED: reviewer tier per the ladder above (mid while issues
  keep landing, high once for the confirming pass)
- `[SPEC_FILE_PATH]` — the spec under review

**Reviewer returns:** Status, Issues (if any), Recommendations
