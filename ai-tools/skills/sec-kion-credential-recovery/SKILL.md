---
name: sec-kion-credential-recovery
description: Use when AWS calls fail with ExpiredToken and `source ~/.local/bin/kac ensure` reports only "Kion AWS credential refresh failed", when a LaunchAgent shows OS_REASON_CODESIGNING or "needs LWCR update", or before planning live AWS reads (CloudFormation, Lambda logs, ephemeral per-branch stages) that dead credentials would waste. Covers diagnosing the hidden HTTP status and recovering an expired App API key.
---

# Kion Credential Recovery

`kac ensure` exits 1, so `&&` chains stop correctly — but it names the *refresh* layer when the fault is almost always the *key* layer underneath it. Chasing the wrong tier is the whole failure mode this skill prevents.

Current refreshers append the chained status, so one line usually ends the investigation:

```text
Kion AWS credential refresh failed: Kion temporary-credential request failed <- HTTPError: HTTP Error 401: Unauthorized
```

A bare `Kion AWS credential refresh failed.` with no status means the host is running an older `kion-aws-refresh` — fall to step 3 of the ladder. A `Warning: Kion App API key is N days old` line means rotation has stalled and the key is heading for the ~7-day cliff; fix that before it becomes a 401.

Finding and *using* credentials is **sec-credentials**. Use this skill only when the refresh itself is broken.

## Two tiers, two LaunchAgents

| Tier | Job | Cadence | Holds |
|---|---|---|---|
| 1. Long-lived App API key | `org.nix-community.home.kion-api-key-rotate` — home-manager owns the schedule; the script itself stays user-local. Older hosts carry a hand-installed `gov.cms.kion-api-key-rotate` instead | Daily, noon | `kion.api_key` in `~/.kion.yml` |
| 2. Short-term AWS creds | `org.nix-community.home.kion-aws-refresh` — home-manager | 4 hours | `~/.cache/kion-aws-cache/` |

Tier 2 fails loudly and harmlessly whenever tier 1 is dead. **Diagnose tier 1 first** — fixing tier 2 fixes nothing.

## Preflight

Run before planning AWS work, not after a failure:

```bash
zsh -lc 'source ~/.local/bin/kac ensure >/dev/null 2>&1 && aws sts get-caller-identity --query Arn --output text' 2>&1 | tail -1
```

An ARN means go. Anything else means stop and walk the ladder below — never start an AWS-dependent plan on dead credentials.

## Diagnostic ladder — cheapest first

**1. Read the rotate job's own log.** Unlike the refresh helper, `kion-api-key-rotate` reports its HTTP status:

```bash
tail -3 ~/Library/Logs/KionApiKeyRotate/stderr.log
```

**2. Run the rotation by hand.** It prints the status and, on failure, leaves `~/.kion.yml` untouched:

```bash
/etc/profiles/per-user/$(id -un)/bin/python3 ~/.local/bin/kion-api-key-rotate
```

On a *live* key this rotates it — that is the job's purpose, not a side effect to avoid.

**3. Only if the refresher reports no status** (an older copy that swallows its cause) **or rotation succeeds while refresh still fails**, extract it directly. Write this to a file under `~/.cache/<agent>/` and run it — never inline it through `zsh -c`; print the status only, since the settings tuple carries the key:

```python
import importlib.util, importlib.machinery, pathlib
p = pathlib.Path.home() / ".local/bin/kion-aws-refresh"
loader = importlib.machinery.SourceFileLoader("kar", str(p))
spec = importlib.util.spec_from_loader("kar", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
home = pathlib.Path.home()
s = m.load_settings(home / ".kion.yml", home / ".config" / "gkion" / "config.toml")
try:
    m.request_credentials(*s); print("request: OK")
except Exception as e:
    c = e.__cause__
    while c:
        print(type(c).__name__, str(c)[:200], getattr(c, "code", "")); c = c.__cause__
```

| Status | Meaning | Fix |
|---|---|---|
| 401 | App API key expired or revoked — tier 1 | Re-mint by hand (below) |
| 403 / 404 | Account or CAR selection wrong | `~/.config/gkion/config.toml`, sops-managed from `secrets/gkion.toml` |
| Timeout / DNS | Off VPN | Reconnect; the Kion base URL is internal |
| `load_settings` raises | Config unreadable | Repair `~/.kion.yml` shape (`kion.url`, `kion.api_key`) |

## Why rotation stopped — check both traps

A 401 means rotation silently stopped days earlier. Two independent causes, both visible here:

```bash
launchctl print gui/$(id -u)/gov.cms.kion-api-key-rotate 2>&1 | rg 'runs|last exit|interval|properties'
uptime   # compare against the interval
```

Both traps are fixed for the nix-managed agent; expect them only on a host still carrying the hand-installed plist.

**Trap 1 — macOS kills the job.** `last exit reason = OS_REASON_CODESIGNING`, with `properties = inferred program | needs LWCR update | managed LWCR`, means launchd's recorded Lightweight Code Requirement no longer matches the binary. This happens when a plist invokes an interpreter through a Nix profile symlink (`/etc/profiles/per-user/<user>/bin/python3`), whose store target changes on every home-manager generation. The nix-managed tier-2 agent escapes this by pinning an absolute `/nix/store/...` path, which is immutable — that asymmetry is why tier 2 keeps running while tier 1 dies.

Re-register to clear the stale LWCR:

```bash
launchctl bootout gui/$(id -u)/gov.cms.kion-api-key-rotate
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/gov.cms.kion-api-key-rotate.plist
```

`properties` should drop back to `inferred program`, and a subsequent run reports a real `last exit code` instead of a kill reason. **Durable fix:** let home-manager own the agent, which pins `${pkgs.python3}` by absolute store path and re-bootstraps it on every switch.

**Trap 2 — the interval never elapses.** `StartInterval` counts from *load*, so under `RunAtLoad=false` every reboot restarts the timer. `runs = 0` with `last exit code = (never exited)` and an uptime shorter than the interval means it has not fired this boot at all. Cross-check the true last rotation by mtime — `~/Library/Logs/KionApiKeyRotate/stdout.log` and `~/.kion.yml` move together. **Durable fix:** `StartCalendarInterval`, which fires on a wall clock and runs once on wake after a missed window, plus `RunAtLoad=true` — both now set on the nix-managed agent.

## Recovery: the key cannot self-heal

The key expires on an absolute clock of roughly **seven days from issuance** — not, as the CMS SOP states, after seven days of *inactivity*: a measured key died at 6 d 15 h while a successful refresh ran against it every four hours. Rotation authenticates to `/api/v3/app-api-key/rotate` with the very key it replaces, so once that key is dead **no scheduler run and no amount of re-bootstrapping can recover it.** Recovery is manual, always:

1. Mint a fresh App API key in the Kion UI (`kion.url` in `~/.kion.yml`).
2. Replace the `api_key:` value in `~/.kion.yml`, preserving indentation. Edit in place; never echo the key.
3. Verify with the preflight above.
4. Clear both traps: re-bootstrap (trap 1), then `launchctl kickstart -k gui/$(id -u)/gov.cms.kion-api-key-rotate` to restart the cadence from now.

## Don't

- **Don't hand-edit `~/.aws/credentials`, and don't reach for `aws sso login`.** `kion-aws-refresh` writes that file from the same session it caches, so an edit is overwritten within two hours and a dead App API key stops both paths at once. Kion owns auth (see sec-credentials).
- **Don't `cat` the cache files into `export`s** — no freshness guarantee.
- **Don't re-run `kac ensure` hoping it self-heals** a 401. It cannot. Two failures in a row means read the status.
- **Don't stop at "the job exists".** `launchctl list` showing the label proves registration, not execution — read `runs` and `last exit reason`.

## Cross-references

- **sec-credentials** — where credentials live and the `kac ensure` discipline.
- **sec-sops-encrypt** — re-encrypting `secrets/gkion.toml` after an account/CAR change.
- **ops-deploy-probes** — the live-read budget this preflight protects; ephemeral per-branch stages are exactly where dead credentials waste a plan.
