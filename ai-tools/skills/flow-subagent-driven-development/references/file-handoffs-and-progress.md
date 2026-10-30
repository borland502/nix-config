# File Handoffs

Large pasted prompts and reports increase context pressure and duplicate
material across handoffs. Pass stable file paths so each agent can read the
relevant artifact directly; keep returned status concise. Actual context reuse
and billing depend on the harness, model and caching. Use these contracts:

- **Task brief:** before dispatching an implementer, run this skill's
  `scripts/task-brief PLAN_FILE N` — it extracts the task's full text to a
  uniquely named file and prints the path. Compose the dispatch so the
  brief stays the single source of requirements. Your dispatch should
  contain: (1) one line on where this task fits in the project; (2) the
  brief path, introduced as "read this first — it is your requirements,
  with the exact values to use verbatim"; (3) interfaces and decisions
  from earlier tasks that the brief cannot know; (4) your resolution of
  any ambiguity you noticed in the brief; (5) the report-file path and
  report contract. Exact values (numbers, magic strings, signatures, test
  cases) appear only in the brief.
- **Report file:** name the implementer's report file after the brief
  (brief `…/task-N-brief.md` → report `…/task-N-report.md`) and put it in
  the dispatch prompt. The implementer writes the full report there and
  returns only status, commits, a one-line test summary, and concerns.
- **Reviewer inputs:** the task reviewer gets three paths — the same brief
  file, the report file, and the review package — plus the global
  constraints that bind the task.
- Fix dispatches append their fix report (with test results) to the same
  report file and return a short summary; re-reviews read the updated file.

## Durable Progress

Compaction and session changes can omit operational details. Track progress
in a durable ledger as well as todos so a later controller can corroborate
completion against git history and avoid repeating completed tasks.

- At skill start, resolve the workspace with
  `workspace=$(scripts/sdd-workspace)`, then check
  `cat "$workspace/progress.md"`. The helper uses
  `<repository>/.superpowers/sdd` only when that path is already ignored;
  otherwise it uses a stable path under
  `${XDG_CACHE_HOME:-$HOME/.cache}/copilot/`, keyed by a full Git object hash
  of the absolute repository root. It never changes repository ignore rules.
  Tasks listed as complete are DONE — do not re-dispatch them;
  resume at the first task not marked complete.
- When a task's review comes back clean, append one line to the ledger in
  the same message as your other bookkeeping:
  `Task N: complete (commits <base7>..<head7>, review clean)`.
- The ledger is your recovery map: the commits it names exist in git even
  when your context no longer remembers creating them. After compaction,
  trust the ledger and `git log` over your own recollection.
- `git clean -fdx` can destroy a local ignored ledger; a cache-backed ledger
  is outside the repository. If either is lost, recover from `git log`.

## Prompt Templates

- [implementer-prompt.md](../implementer-prompt.md) - Dispatch implementer subagent
- [task-reviewer-prompt.md](../task-reviewer-prompt.md) - Dispatch task reviewer subagent (spec compliance + code quality)
- Final whole-branch review: use nix-config-tools:git-request-review's [code-reviewer.md](../../git-request-review/code-reviewer.md)
