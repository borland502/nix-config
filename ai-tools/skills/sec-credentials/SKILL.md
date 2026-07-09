---
name: sec-credentials
description: Use when looking for an API token, auth key, or cached session for a tool (e.g. "where's the Jira token?", "how do I get the Anthropic key?"). Documents this repo's credential lookup precedence — sops-managed secrets, then the XDG config home, then the legacy fallback paths — so an agent never asks the user for credentials it could have read from disk.
---

# Credential Lookup

Use this skill when a task needs a credential and you don't yet know where to find it. The repo has a deliberate precedence chain — check it before prompting the user.

**Core principle:** look on disk before asking. The user has provisioned credentials once; if a tool can't find one, the path was probably wrong, not missing.

## Precedence

1. **sops-decrypted runtime path** — `~/.config/<tool>/<secret-name>` (no extension).
   These are populated by [home-manager/modules/sops.nix](../../../home-manager/modules/sops.nix) at activation time from encrypted blobs in `secrets/` and the age key at `~/.config/sops/age/keys.txt`. Files appear only after `home-manager switch` has run with the age key present.

2. **XDG config home** — `$XDG_CONFIG_HOME/<tool>/...` (defaults to `~/.config/<tool>/...`).
   For tools that manage their own auth (`gh`, `aws`, `chezmoi`), this is where their config + token files live.

3. **Cache home** — `$XDG_CACHE_HOME/<tool>/...` (defaults to `~/.cache/<tool>/...`).
   Tools that cache short-lived session state (browser cookies, refreshed OAuth tokens, kerberos tickets) typically write here. Check this before prompting if a session-style credential is needed.

4. **Legacy / tool-default path** — whatever the tool's docs specify (`~/.aws/credentials`, `~/.kube/config`, `~/.netrc`).
   These are fallback locations the tool consults when XDG isn't honored. Some tools (notably `gh`) use the XDG path now; older ones still write here. **AWS is the trap here:** `~/.aws/credentials` and `AWS_PROFILE` are frequently stale and raise `ExpiredTokenException` — see the AWS section below before reaching for them.

5. **Last resort: prompt the user.** Only after the above four paths have all been checked.

## Canonical example

[home-manager/local/bin/ops-agent.py](../../../home-manager/local/bin/ops-agent.py) implements this pattern for the Jira token: read `~/.config/ops-agent/jira-token` (sops-decrypted), fall back to `~/.config/jira/token` (legacy), then error out. That precedence chain is the template — any new credential consumer in this repo should follow the same layering.

## AWS credentials (Kion)

**Do not trust `~/.aws/credentials`, `AWS_PROFILE`, or `aws --profile <name>`** — the `--profile` flag is the same stale-credential path as the env var — they are usually stale and produce `ExpiredTokenException`. The live AWS session lives in the Kion credential cache at `~/.cache/kion-aws-cache/`. Prefer the `kac` helper, which loads from that cache and auto-refreshes via `gkion` when it's empty or expired:

```bash
# Preferred: load valid creds into the current shell (must be sourced; works
# from bash or zsh)
source ~/.local/bin/kac ensure
```

**Run `kac ensure` *before* the first `aws` call, not as recovery after one
fails, and gate the call on its exit code.** Firing `aws` against an inherited
stale token wastes round-trips on `ExpiredTokenException` and then sends agents
off exploring. For a one-shot, non-interactive invocation, chain both with `&&`
so the refresh always precedes the call and a failed refresh stops the chain:

```bash
zsh -lc 'source ~/.local/bin/kac ensure >/dev/null && aws sts get-caller-identity --output text'
```

**`ensure`, not `load`.** `kac load` validates the cached creds but does **not**
refresh them — on expiry it fails (stopping an `&&` chain) instead of
self-healing via `gkion`. `load` is for a human who just refreshed; agents and
scripts always use `ensure`.

**Shell PATH note:** a bare `zsh -c '…'` (no `-l`) or `env -i` strips the
nix/Homebrew `PATH`, which used to make `gkion`/`aws` "vanish" mid-refresh. The
`kac` lib now prepends the known tool dirs itself, but prefer the current
(already-provisioned) shell or `zsh -lc` anyway — other tools in the same
command line don't get that rescue (see shell-pitfalls "Subshell PATH loss").

Anti-patterns (observed wasting time in real sessions):

- **Do not reach for `aws sso login`** — Kion, not raw SSO, owns auth here; `kac`
  refreshes via `gkion` for you.
- **Do not `find` / `zstdcat` for the cache location.** `kac` owns
  `~/.cache/kion-aws-cache/`; the path is documented here and in
  `agent-reference.md`. Re-deriving it from cold burns tokens and risks a stale
  path.
- **Do not `cat` the cache files into `export`s**
  (`export AWS_ACCESS_KEY_ID=$(/bin/cat ~/.cache/kion-aws-cache/…)`). Raw reads
  carry **no freshness guarantee** — this is the exact observed stale-creds
  pattern. `kac ensure` reads the same files *and* validates/refreshes them;
  there is no situation where the raw `cat` is the better move.

If an `aws` call fails with an expired-token error, the inherited env vars (`AWS_ACCESS_KEY_ID`, etc.) are likely overriding the cache — clear them and re-source `kac` rather than editing `~/.aws/credentials`. Full `kac` subcommand reference is in `agent-reference.md`.

## Quick checks

```bash
# Is the credential available as a sops-decrypted file?
test -e "$HOME/.config/<tool>/<secret>" && echo "found at sops path"

# Does the tool have its own XDG-aware config?
ls "$XDG_CONFIG_HOME/<tool>/" 2>/dev/null

# Is there a cached session?
ls "$XDG_CACHE_HOME/<tool>/" 2>/dev/null

# Last-resort tool-default path (tool-specific)
ls "$HOME/.<tool>/" 2>/dev/null
```

## Cross-references

- **[sec-sops-encrypt](../sec-sops-encrypt/SKILL.md)** — how secrets get into the sops-decrypted runtime paths in the first place. Read this when you need to *add* a new credential, not just find one.
- **[ops-agent](../ops-agent/SKILL.md)** — the canonical consumer of this pattern. Its source is the live worked example.

## Common pitfalls

- **Don't `cat` decrypted secret files into terminal output.** They get logged by the PostToolUse hook to `~/.cache/<agent>/*.log`. Read with `python -c 'open("...").read().strip()'` and use the value, but don't echo it.
- **Don't assume the file exists.** Activation may have failed or the user may not have an age key on this host. If the file isn't there, fall through to the next precedence step.
- **Don't write a new credential to disk yourself.** Adding a secret means encrypting it with sops first — see `sec-sops-encrypt`.
