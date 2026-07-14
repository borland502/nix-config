# TODO — brew→nix migration & unmanaged-tool cleanup

## Already done (2026-07-09, this machine — no repo change needed)

- `brew uninstall acli` (undeclared; conflicts with direct-REST Jira policy)
- `brew uninstall --force --cask windsurf` (undeclared; cask token renamed
  upstream to `devin-desktop`, plain uninstall bounced — force worked)
- Removed unmanaged binaries:
  `~/.local/bin/{cobra-cli,helloc,technitiumdns-cli,tdns}`

## Tier 1 — CLI migrations (no GUI/TCC risk)

- [x] Check `onActivation` cleanup mode in hosts/darwin/default.nix — if not
      `uninstall`/`zap`, migrated formulas need manual `brew uninstall` after
      a successful switch.
- [x] hosts/darwin/default.nix: remove brews `colima`,
      `docker-credential-helper`, `lima-additional-guestagents`, `pydantic`;
      remove casks `session-manager-plugin`, `android-platform-tools`.
- [x] Add nix pkgs (darwin-only → hosts/darwin systemPackages): `colima`,
      `lima-additional-guestagents`, `docker-credential-helpers`,
      `ssm-session-manager-plugin`, `android-tools`.
- [x] `pydantic`: find the consumer (`rg -l pydantic` over scripts/ai-tools);
      none → drop; else `python3.withPackages (ps: [ps.pydantic])` in
      common.nix. Record decision in the commit message.
- [x] Verify: `task dry-build`; after user runs `task switch`:
      `command -v colima session-manager-plugin adb docker-credential-osxkeychain`
      resolve to nix paths, `colima status` still sees the VM (state in
      `~/.colima` is binary-independent).

## Tier 2 — GUI migrations

Rationale: chrome + slack are the root-owned/TCC-blocked casks that keep
failing `task switch` upgrades. Nix apps update via the store with stable
trampolines, so TCC grants generally survive.

- [x] Batch A casks → nix: `google-chrome`, `slack`. Manual: after switch,
      remove/chown the stale root-owned `/Applications/{Google Chrome,Slack}.app`
      copies; first nix launch re-prompts TCC (user at keyboard). Then update
      memory `project_switch_nonfatal_errors`.
- [x] Batch B: `kitty`, `iterm2`, `keepassxc`, `dbeaver-community`→
      `dbeaver-bin`, `jordanbaird-ice`→`ice-bar`, `moonlight`→`moonlight-qt`,
      `obsidian`, `discord`, `firefox`, `whatsapp`→`whatsapp-for-mac`,
      `flameshot`.
  - flameshot: drop the cask-era `xattr -cr` quarantine-strip activation
    (nix apps aren't quarantined); check launchd agent path references;
    screen-recording TCC re-grant once.
  - firefox: optionally enable the Stylix firefox target later (README note).
- [x] Stay in brew (comment the casks list accordingly): `vivaldi`,
      `chromium` (no aarch64-darwin), `jetbrains-toolbox`
      (self-updater vs read-only store), `kion-cli`/`aws-console` (vendor
      tap), `nvm` (Tier 4), `corretto@11` (swap to
      `temurin-bin-11` only after confirming the JDK11 consumer allows).
      (2026-07-10: `visual-studio-code` moved to Nix on nixos-unstable and
      `visual-studio-code@insiders` was dropped — a dual Homebrew+Nix install
      corrupted VS Code webview service workers. `postman`/`postman-cli`
      removed from the repo entirely.)
- [x] Verify: `task dry-build` green; after user switch: apps land in
      `/Applications/Nix Apps` (or HM Apps), launch, Spotlight finds them;
      `brew list --cask` shrinks to the stay-in-brew set.

## Tier 3 — bring `gkion` under management (load-bearing orphan)

`~/.local/bin/gkion` (hand-placed 2026-05-06) is `kac ensure`'s refresh
dependency; the `kion-cli` formula ships `kion`, not `gkion`. Nothing rebuilds
it today.

- [x] Provenance: `go version -m ~/.local/bin/gkion | head -5` (module path),
      fallback `strings | rg 'github.com|module'`.
- [x] Public Go module → add to `chezmoi/.chezmoiexternal.toml.tmpl` +
      `chezmoi/run_install-go-tools.sh.tmpl` (wordgen pattern); verify rebuild
      then `source ~/.local/bin/kac ensure` still works. Private → document
      provenance + rebuild steps in agent-reference next to `kac`.
- [x] Add a gkion line to agent-reference's kac section either way.

## Tier 4 — decisions to record

- [x] nvm/node: keep nvm; add one agent-reference tool-catalog line stating
      node/npm are nvm-managed (`~/.nvm`, active v26). Migration to nixpkgs
      nodejs + devshells deferred unless the user opts in.
- [x] masApps unchanged.

## Verify (after all tiers)

- [x] `task dry-build` clean; pre-commit green per commit; no agent-defaults
      change → no instruction regen.
- [x] `brew leaves` → kion-cli, aws-console, nvm only; casks → documented set.
- [x] `cache-scan --days 1` post-switch: no new failure signatures.
- [x] Update memory `project_switch_nonfatal_errors` after Batch A lands.

## Evidence

Single `nix eval` availability matrix over locked nixpkgs
(`~/.cache/claude/brew-vs-nixpkgs.nix`); `brew leaves` matched declared brews
exactly pre-cleanup; unfree already allowed in both darwin and HM configs.

## Agent-workflow follow-ups

- [x] `ops-agent` CLI is broken for agent use: it crashes before doing anything
      with `TypeError: Could not resolve authentication method` from the
      Anthropic SDK (needs `ANTHROPIC_API_KEY`/auth_token in the environment;
      it loads its Jira token from `~/.config/ops-agent/` but not an Anthropic
      key). Observed 2026-07-13 fetching MDPMDD-828 — had to fall back to
      direct Jira REST. While in there: it pins model `claude-sonnet-4-6`;
      bump or make configurable.
      Done 2026-07-13 (no Anthropic key will exist — refactored to the
      `claude` CLI instead, per user direction): `ops-agent.py` no longer
      imports the Anthropic SDK. `ops-agent --tool <name> '<json>'` runs one
      Jira/ECS tool deterministically (no model call); `ops-agent "<prompt>"`
      execs `claude -p` (subscription OAuth) with the MDP system prompt
      appended and permissions scoped to `Bash(ops-agent --tool:*)`. Model now
      inherits the CLI default; `OPS_AGENT_MODEL` passes `--model`. common.nix
      drops the `ps.anthropic` python dep. Verified live: `--test` OK, `--tool
      jira_get_issue` fetches MDPMDD-828, and the prompt mode end-to-end via
      haiku answered correctly. Docs updated (ops-agent skill + agent,
      agent-reference helper entry).
- [x] Jira REST ergonomics trap: `~/.config/ops-agent/jira-base-url` already
      includes the `/rest/api/2` suffix despite the "base-url" name, so the
      obvious `"$JIRA_BASE/rest/api/2/issue/…"` composition 404s (and Jira's
      404 body is XML, so a piped `jq` dies with a parse error that masks the
      real failure). Rename the secret (e.g. `jira-api-root`), or note the
      contained path in agent-reference.md's Jira section, or add a tiny
      `jira-get <path>` helper that owns the composition.
      Done 2026-07-13 (note + helper; rename skipped — too many consumers of
      the existing path): new `jira-get <path>` helper
      (`chezmoi/dot_local/bin/executable_jira-get`) owns the composition,
      takes API-root-relative paths, and turns non-2xx/non-JSON responses
      into clear stderr errors instead of downstream `jq` parse failures.
      agent-reference.md documents the trap in the Jira credential entry and
      catalogs the helper. Verified live: `myself`, issue fetch with query
      params, and the old double-prefix mistake now reports
      `HTTP 404 for …/rest/api/2/rest/api/2/…` plainly.
- [x] Recognize zstd-compressed cache artifacts before treating a helper script
      or log as missing. `compress-old-cache` archives idle files under
      `~/.cache/{claude,copilot}` (the two are symlinked) to `*.zst` — see the
      "zstd-archived" note in `agent-defaults.md`. Restore with
      `zstdcat file.zst > file`; search inside archives with `zstdcat`/`zstdgrep`
      rather than plain `rg`/`ls`. Observed 2026-07-10: the `sno_*.py`
      SNO-benchmark scripts (`sno_jobtime.py`, `sno_parts.py`, `sno_trace.py`,
      `sno_quarters.py`) read as "gone" via `ls`/`fd` until found as
      `sno_*.py.zst` and decompressed.
      Done 2026-07-13: `cache-scan` now emits a **SCRIPTS** section (default
      output) listing top-level reusable helper/data files by mtime — code/query
      extensions incl. their `.zst` archives, tagged `(zstdcat)` for recovery;
      widen with `--days`. Documented in the ops-cache-scan skill "What To
      Extract" and in agent-reference's `compress-old-cache` entry (the always-on
      `agent-defaults.md` note was left untouched — it is at 6991/7000 bytes of
      its budget). agent-defaults.md unchanged → no instruction regen needed.
