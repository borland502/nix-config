# TODO — skill & tool-use flaw remediation

Execution-ready plan from a 3-week cache-log failure scan (`cache-scan --days 21`
plus a categorizing aggregator over 36 logs / ~2,350 records, meta log-reads
filtered out). Ordered by frequency × leverage. Counts are heuristic — the log
hook sees no exit code, so these are output-pattern matches, not exit statuses.

**Executed 2026-07-06** on branch `feat/agent-flaw-remediation`, one commit per
tier (PR #67 had already merged, so a new branch per the fallback). All items
below are checked off; per-item outcome notes added inline where execution
deviated from the spec.

**2026-07-02 follow-up scan** (26 recent sessions + 93 archived session logs,
~3 months): re-validated Tiers 1–2 (50 `ExpiredToken` hits archived; a
stale-creds `kac load` in that day's session), confirmed the stat-dialect fix
landed in shell-pitfalls, and added Tier 4 (cache hygiene + artifact
graduation) plus the `kac load` bullet in Tier 1.

## Tier 1 — systemic (AWS credentials dominate: 20 of the failures)

Root cause: agents call `aws` without a fresh session — bare `aws`,
`AWS_PROFILE=… aws` (stale), or `export …=$(cat ~/.cache/kion-aws-cache/…)`
(stale) — instead of `source ~/.local/bin/kac ensure` first. One case ran
`source kac ensure` and *still* got `ExpiredToken`: a bare `zsh -c` strips the
nix/Homebrew PATH, so `kac ensure` can't find `gkion`/`aws` to refresh/validate.

- [x] **`ai-tools/skills/sec-credentials/SKILL.md`** — fix two doc bugs that
      actively cause the stale-creds pattern:
  - Line ~37: drop "must be sourced, **zsh only**" — `kac` now sources under bash
    too (fixed in commit ba95641). Say "source it from bash or zsh".
  - Lines ~60-66: remove or hard-caveat the "If you can't source `kac`, read the
    cached values directly" `cat …/AWS_*` block — raw `cat` gives **no freshness
    guarantee** and is the exact observed anti-pattern (loads stale creds).
  - Require checking `kac ensure`'s **exit code**; never run `aws` if it failed
    (`source ~/.local/bin/kac ensure && aws …`).
  - Document `load` vs `ensure`: `kac load` validates cached creds but **does
    not refresh** — on expiry it fails (`&&` chain stops) instead of
    self-healing via gkion, sending agents off exploring (observed 2026-07-02:
    `source ~/.local/bin/kac load && …`). Rule: agents always use `ensure`;
    have `load`'s expiry message point at `ensure`.
  - Warn: a bare `zsh -c '…'` (no `-l`) strips the nix profile + `/opt/homebrew`
    PATH, so `gkion`/`aws` "vanish" and the refresh silently fails. Use the
    current (already-provisioned) shell, or `zsh -lc`, or pass PATH explicitly.
- [x] **`chezmoi/dot_local/lib/kion-aws-cache`** — harden `_kion_aws_cache_main`:
      prepend the known tool dirs to a **`local PATH`** so a PATH-stripped
      subshell can still validate + refresh. Scope with `local` so the caller's
      PATH is untouched; exported `AWS_*` still persist. Dirs to add if present:
      `/opt/homebrew/bin` (gkion), `/etc/profiles/per-user/$USER/bin`,
      `/run/current-system/sw/bin`, `$HOME/.nix-profile/bin` (aws). This fixes
      the "sourced kac but still ExpiredToken" case. Re-`shfmt`, re-test both
      shells (see Verify).
- [x] **`ai-tools/skills/shell-pitfalls/SKILL.md`** (and cross-link
      `gh-graphql-jq-pipelines`) — the "Heavy quoting → write a script file"
      section: add an **AWS-logs / jq** example (nested quotes + `$LATEST` /
      glob tokens, e.g. `aws logs filter-log-events … '2026/06/30/[$LATEST]…'`).
      5 hits, all `source kac ensure >/dev/null` + heavy-quoted `aws logs …`.

## Tier 2 — recurring shell traps

- [x] **`ai-tools/skills/shell-pitfalls/SKILL.md`** — NEW section **"Subshell
      PATH loss"**: `env -i`, `sudo`, and bare `zsh -c` do **not** inherit the
      nix profile PATH, so `stat`/`timeout`/`gkion`/`aws` appear "not found" even
      though they're on the interactive PATH (verified: GNU `stat -c`, `timeout`
      both resolve in a login shell). Fix: pass `PATH=` explicitly or use
      absolute paths. Ties Tier-1's kac failure to a general rule.
      (stat-dialect 4 + cmd-not-found 6 hits.)
- [x] **`ai-tools/skills/shell-pitfalls/SKILL.md`** — promote zsh **`nullglob`**
      "no matches found" to a first-class section (4 hits: `docker-compose*.yml`,
      `~/.config/ops-agent/config*` with no match abort the command). Fix: quote
      the glob, guard with `2>/dev/null`, or use `fd`.
- [x] **`chezmoi/dot_config/instructions/agent-reference.md`** — tool catalog:
      `psql` is **NOT installed** on managed hosts (use `docker exec <db> psql`
      or add it); `nc` is BSD (`/usr/bin/nc`, different flags); note GNU
      coreutils + `timeout` are only on the login PATH (see Subshell PATH loss).
      (`agent-reference.md` is read on-demand, NOT the always-on prefix — no
      instruction regen needed.)

## Tier 3 — lower / external

- [x] **`ai-tools/skills/ops-jira-integration/SKILL.md`** — note: Jira API
      `Connection reset by peer` on VPN (4 hits) → retry with backoff; prefer
      direct REST with the token (already the standing rule).
- [x] **Darwin cask permission/TCC** — document the Full Disk Access grant for
      root-owned / TCC-protected `/Applications` casks (`sudo chown`/`rm -rf
      …Caskroom`). Ties to the `project_switch_nonfatal_errors` memory and the
      switch-tolerance work in PR #67. Put in `agent-reference.md` or ops notes.
- [x] TS/build failures (36, mostly real dev iteration: `./run typecheck`,
      `tsc -b`) live in the **mdp-application** repo, not here — no change in
      this repo. Optional: note "standardize on `./run typecheck`" there.

## Tier 4 — cache hygiene & artifact graduation (2026-07-02 scan)

The cache dir is now an AI liability: 460 MB, 5,254 top-level entries, 3,976 of
them archived one-off `.log` files. `cache-scan`, credential/disk lookups, and
any `rg`/`fd` sweep over `~/.cache/copilot` wade through all of it.

- [x] **`ai-tools/scripts/compress-old-cache`** — add a **retention pass**:
      delete `.zst` archives older than **1.5 years** (`fd --max-depth 1
      --type f -e zst --changed-before 78weeks … | xargs -0 rm`). Keep the
      existing live-session grace; keep the 30-min throttle.
- [x] **`ai-tools/scripts/compress-old-cache`** — handle **subdirectories**:
      the current `fd --max-depth 1 --type f` never compresses or prunes
      subdirs, so big trees sit uncompressed forever (129 MB
      `mdpmdd-827-diagram/` incl. `node_modules`, 110 MB `vscode-stable-clean/`,
      44 MB CI run artifacts). Apply the same 1.5-year retention to
      subdirectories by mtime (`rm -rf` after the threshold); always exclude
      `node_modules` trees from any compression sweep (delete-only). Document
      the policy in the script header and the ops-cache-scan skill.
- [x] **Graduate `failscan.py`** — the failure-categorizing aggregator cited in
      Evidence below lives only in a session scratchpad
      (`/private/tmp/claude-502/-Users-42245--config-nix/5dd8988a-…/scratchpad/failscan.py`)
      and `/private/tmp` does not survive reboots. A safety copy exists at
      `~/.cache/claude/failscan-rescued-20260702.py`. Fold it into
      `cache-scan` as a `--classify` mode (or `ai-tools/scripts/`) so failure
      triage is repeatable, then update the Evidence footnote here.
- [x] **`ai-tools/skills/shell-pitfalls/SKILL.md`** — NEW pitfall: **piping
      non-JSON into `jq`**. 8+ archived hits of `jq: parse error: Invalid
      numeric literal` from feeding an HTML 401/error page into `jq`, plus a
      `null` result used as a file path (`bash: null: No such file or
      directory`). Fix: `curl -fsS` (fail on HTTP errors), check the payload
      before filtering, use `// empty` defaults, and `gron` for unknown-shaped
      JSON.
- [x] **Per-ticket helper graduation** (optional) — `~/.cache/copilot/`
      `mdpmdd800-bench/{rds-exec.sh,jira-comment.py,queries*.sh}` get rewritten
      each session. *Assessed 2026-07-06, no promotion:* `jira-comment.py` is a
      one-shot with a hardcoded MDPMDD-800 body — obsolete (ops-agent posts
      Jira comments); `rds-exec.sh` hardcodes the dev6 cluster + secret ARNs —
      a parameterized Data-API helper would belong in mdp-application, not this
      repo.

## Verify (after executing)

- [x] `kac` still sources clean in **both** shells:
      `bash -c 'source chezmoi/dot_local/bin/executable_kac status'` and the same
      under `zsh -c` (expect `current=…`, exit 0). Test `ensure` reaches `gkion`
      from a stripped subshell: `env -i HOME="$HOME" bash -c 'source …/kac status'`.
- [x] `shfmt -d chezmoi/dot_local/lib/kion-aws-cache` clean; `task lint:sh` green.
- [x] `markdownlint-cli2` clean on every edited SKILL.md (note: `lint:md` skips
      `ai-tools/`, so lint the skill files directly).
- [x] No always-on prefix (`agent-defaults.md`) change → no
      `task generate:agent-instructions` needed. If that changes, regenerate.
- [x] `compress-old-cache` retention: dry-run first (swap `rm` for `echo` /
      `fd … --changed-before 78weeks` listing) and eyeball the candidate list
      before the first destructive run; `shfmt -d ai-tools/scripts/compress-old-cache`
      clean; confirm the live `session_*.log` and recent artifacts survive.
- [x] `cache-scan --classify` (or the graduated aggregator) reproduces the
      Evidence categories below on the current logs.

## Evidence (category → count, 21-day window, de-noised)

`stale-aws-creds 20 · build-ts-node 36 (mostly real dev) · file-not-found 18 ·
cmd-not-found 6 · gh-graphql-jq 5 · quoting-heredoc 5 · permission-denied 5 ·
zsh-nullglob 4 · stat-dialect 4 · network-tls 4 · git-workflow 1 · nix-build 1`.
Aggregator: graduated into `cache-scan --classify` (safety copy of the
original at `~/.cache/claude/failscan-rescued-20260702.py` can be deleted once
the chezmoi-deployed cache-scan is confirmed on all hosts).
