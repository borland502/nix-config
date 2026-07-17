---
description: Weekday Jira triage digest — list open assigned tickets and flag stale / next-action. Read-only; never transitions, comments, or assigns.
---

Produce a short Jira triage digest for the current user. Safe to run unattended:
**read-only — do not transition, comment on, or assign any ticket.**

1. Run `jira-my-tickets` (zero-token helper; Bearer auth via the token at
   `~/.config/ops-agent/jira-token` — no email needed). This is the
   open-ticket list, ranked.
2. For triage detail on specific tickets, use the `ops-agent` skill/CLI
   (summary, status, assignee) — prefer it over ad-hoc REST.
3. Assess each ticket: actionable now, blocked, or stale (no recent movement)?

Output — keep it tight, this is a digest not a report:

- **Act on today (top 3):** KEY — title — why / suggested next step
- **Stale (needs a nudge or status change):** KEY — title — days idle
- **Everything else:** count only

If `jira-my-tickets` returns nothing or errors (e.g. an expired token), say so
in one line and stop — do not retry interactively or fall back to prompting.
