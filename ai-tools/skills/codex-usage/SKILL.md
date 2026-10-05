---
name: codex-usage
description: Use when asked about current Codex credits, monthly allotments, credits used or remaining, usage percentages, or reset times for the signed-in account.
---

# Codex Usage

Read the account's current usage. Never infer it from local token totals or
reuse a snapshot from an earlier reset period.

## Procedure

1. If `mcp__codex_app__get_usage_limits` is available, call it with `{}` and
   read the `codex` entry from `rateLimitsByLimitId`.
2. Otherwise run `python3 scripts/codex_usage.py`, resolving the script relative
   to this skill directory.
3. Report `individualLimit.used`, `individualLimit.limit`, calculated remaining
   credits and percentage used, `remainingPercent`, and the local time
   represented by `resetsAt`.
4. Say when a value is unavailable; missing or null fields are not zero.

The dashboard at `https://chatgpt.com/codex/settings/usage` is authoritative and
may refresh after a short delay.

## Safety

- Use only `account/rateLimits/read`. Never call
  `account/rateLimitResetCredit/consume`, purchase credits, or change account
  settings unless the user separately requests and authorizes that action.
- Do not open the interactive Codex TUI for this lookup; startup prompts can
  intercept `/status`.
- Do not expose authentication data or `accountId`.
- Cached transcripts may recover the method, but not the current amount.
