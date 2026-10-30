---
name: flow-subagent-driven-development
description: Use when executing implementation plans with independent tasks in the current session
---

# Subagent-driven development

Execute an approved plan in this session with a fresh implementer per task,
task-scoped review of both specification compliance and code quality, then a
whole-branch review. Apply this workflow when independent delegated tasks are
authorized; it does not make every ordinary task require fan-out. Continue
authorized work without repeated approval between tasks.

## Start and recover

Use [git-worktrees](../git-worktrees/SKILL.md) to detect existing isolation before
creating anything. Read the approved plan once and scan for conflicting tasks
or global constraints. Batch genuinely unresolved contradictions for the user
with the relevant plan text; an already approved design needs no new approval.

Resolve the operational workspace with `scripts/sdd-workspace` from this skill
directory and inspect its `progress.md` before dispatch. It uses an already
ignored project path or a stable cache path without changing ignore rules.
After resume or compaction, trust the ledger and git history; do not re-dispatch
completed tasks. Record each task's starting commit before delegation.

## Task loop

1. Extract the task with `scripts/task-brief PLAN_FILE N`. Hand the implementer
   that path as requirements, the worktree, file ownership, relevant interfaces,
   binding global constraints and a report path. State that other agents may be
   editing and their changes must be preserved. Use a fresh scoped context.
2. Answer implementer questions before dependent work. Require implementation,
   appropriate TDD/verification and self-review under the user's commit policy.
   Handle DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT and BLOCKED explicitly using
   [tiers and status](references/model-tiers-and-status.md).
3. For DONE, generate `scripts/review-package BASE HEAD`; hand its printed path,
   brief and report to a task reviewer. BASE is the recorded starting commit,
   never `HEAD~1` for a multi-commit task. Uncommitted authorized work needs an
   explicit diff including new files. Both spec and quality verdicts are gates.
4. Resolve every “cannot verify” item against source and requirements. Fix
   supported Critical/Important findings, verify covering tests and re-review
   before the next task. Record Minor findings in the ledger for final triage.
   Do not suppress findings or pre-rate severity in reviewer prompts. Conflicts
   with binding plan text need the user's decision, not a silent contradiction.
5. Append `Task N: complete (commits BASE..HEAD, review clean)` only when the
   evidence supports it. Provide concise progress while continuing the plan.

## Model and review bounds

Choose explicit capability tiers and resolve them through the harness's current
model map: low for mechanical complete specs, mid for integration, prose-driven
implementation and substantive task review, high for architecture. Honor tool
availability and role restrictions. Read [tiers and status](references/model-tiers-and-status.md)
before dispatching; omitted models can inherit an unsuitable session model.

The final whole-branch review starts on mid. After a clean mid round, run a
high-tier confirming review; at most two high passes per branch. Findings go to
one fixer with the complete list, covering tests and report contract; return to
mid after fixes and re-earn high only from a clean round. Escalate unresolved
Critical findings after the second high pass. Do not run expensive review loops
on high or silently discard the accumulated Minor list.

Read [review gates](references/review-gates.md) when preparing reviewers/fixers,
and [file handoffs and progress](references/file-handoffs-and-progress.md) for
artifact contracts and recovery. Pass paths and commit IDs; do not paste whole
reports, plans, diffs or prior-task history into prompts. Use the existing
[implementer](implementer-prompt.md), [task reviewer](task-reviewer-prompt.md) and
[final reviewer](../git-request-review/code-reviewer.md) templates.

After all gates pass, use [git-finish-branch](../git-finish-branch/SKILL.md).
Merging, pushing or activation still requires the user's actual authorization.
