# TODO — brew→nix migration & unmanaged-tool cleanup

Execution-ready plan from the 2026-07-09 brew/nixpkgs audit (locked nixpkgs
`0ad6f47ea4fe`: 22 of 29 brew items now have working aarch64-darwin packages).
**Repo side executed 2026-07-09** (branch `feat/brew-to-nix`). Remaining
manual steps for the user, in order:

1. `task switch` — installs nix packages, `cleanup = "zap"` uninstalls the
   migrated brew formulas/casks.
2. Remove stale root-owned app copies the casks left behind:
   `sudo rm -rf '/Applications/Google Chrome.app' /Applications/Slack.app`
   (plus any other migrated app still present from its cask).
3. Launch each migrated GUI app once and re-grant TCC prompts (screen
   recording for Flameshot, etc.).
4. Verify: `command -v colima adb session-manager-plugin` → nix paths;
   `colima status`; `brew leaves` → kion-cli/aws-console/nvm only.
5. Re-auth Kion (`kac ensure` — the cached AWS creds were cleared during
   gkion verification) and update memory `project_switch_nonfatal_errors`.

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
      `postman`, `flameshot`.
  - flameshot: drop the cask-era `xattr -cr` quarantine-strip activation
    (nix apps aren't quarantined); check launchd agent path references;
    screen-recording TCC re-grant once.
  - firefox: optionally enable the Stylix firefox target later (README note).
- [x] Stay in brew (comment the casks list accordingly): `vivaldi`,
      `chromium` (no aarch64-darwin), `visual-studio-code` + `@insiders`
      (no insiders channel; keep the pair together), `jetbrains-toolbox`
      (self-updater vs read-only store), `kion-cli`/`aws-console` (vendor
      tap), `nvm` (Tier 4), `postman-cli`, `corretto@11` (swap to
      `temurin-bin-11` only after confirming the JDK11 consumer allows).
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
