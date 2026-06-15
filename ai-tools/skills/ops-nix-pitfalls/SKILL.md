---
name: ops-nix-pitfalls
description: Use when a Nix build or activation fails — `task switch`/`task home-switch`/`task build`, nixos-rebuild, darwin-rebuild, or home-manager errors — or before editing flake.nix, home-manager modules, or host configs in this repo. Covers the flake, Home Manager, and repo-config pitfalls that break build/switch.
---

# Nix Configuration Pitfalls & Prevention

Use this skill when troubleshooting Nix flake errors, Home Manager switch failures, or config issues in this repository.

## Common Pitfalls & Solutions

### 1. Untracked Files in Nix Evaluation

**Error:** `Path 'home-manager/local/bin/...' in the repository ... is not tracked by Git.`

**Root Cause:** Nix flake evaluation requires all repo-relative file references to be tracked by Git. New scripts, configs, or derivation sources must be staged.

**Prevention:**
```bash
# Before running 'task switch', stage new files:
git add home-manager/local/bin/new-script.sh
git add .github/skills/new-skill/
git add any-other-new-files

# Verify staging:
git status
```

**Resolution:**
1. Identify missing files from the error message.
2. Run `git add <file>` for each untracked file.
3. Retry the switch/build.

---

### 2. SOPS Age Key Not Available During Encryption

**Error:** `identity did not match any of the recipients` or `Failed to get the data key required to decrypt the SOPS file`.

**Root Cause:** SOPS needs the age private key available in the shell environment to decrypt/encrypt secrets.

**Prevention:**
- Ensure `SOPS_AGE_KEY_FILE` is set before running SOPS commands:
  ```bash
  export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
  sops decrypt secrets/ops-agent.yaml
  ```
- Run `scripts/provision-secrets.sh` once per machine to set up the age key.
- Use isolated shells for SOPS operations if shared shell has interference.

**Resolution:**
1. Verify the age key exists:
   ```bash
   ls -la ~/.config/sops/age/keys.txt
   ```
2. If missing, run:
   ```bash
   bash scripts/provision-secrets.sh
   ```
3. Retry the SOPS operation with `SOPS_AGE_KEY_FILE` set.

---

### 3. Uncommitted Changes Block Nix Build

**Warning:** `Git tree ... has uncommitted changes`

**Root Cause:** Nix flake checks require all changes to be committed or staged.

**Prevention:**
```bash
git status          # Check for unstaged changes
git add <files>     # Stage changes
git commit -m "desc"  # Commit
```

**Resolution:**
- Stage and commit all meaningful changes before running Nix builds/switches.
- Use `git diff` to review changes before committing.

---

### 4. Hard-Wired Tool Paths Instead of PATH Resolution

**Symptom:** Scripts break if tool versions change or aren't in the hardcoded Nix store path.

**Prevention:**
- In Home Manager packages, assume tools exist on PATH (they're in `commonPackages`).
- Use plain command names instead of `${pkgs.tool}/bin/tool`.
- **Example (avoid):**
  ```nix
  cmd = "${pkgs.jq}/bin/jq '.field' $input"
  ```
- **Example (preferred):**
  ```nix
  cmd = "jq '.field' $input"
  ```

**Resolution:**
- Replace hard-wired paths with plain command names.
- Ensure the tool is listed in `home-manager/common.nix` `commonPackages`.

---

### 5. Template Variable Not Substituted (@@AGENT@@)

**Symptom:** Instructions/configs show literal `@@AGENT@@` instead of agent name (copilot/claude).

**Root Cause:** `task generate:agent-instructions` was not run or template substitution failed.

**Prevention:**
- Run `task generate:agent-instructions` after editing `chezmoi/dot_config/instructions/agent-defaults.md`.
- Commit rendered files to `.github/` paths.

**Resolution:**
```bash
task generate:agent-instructions
git add chezmoi/dot_config/github-copilot/
git commit -m "Update agent instructions"
```

---

### 6. SOPS Secret Path Mismatch

**Symptom:** Scripts can't read secrets from expected paths after adding them to sops.nix.

**Prevention:**
- When adding a new secret to `home-manager/modules/sops.nix`, ensure:
  1. It's declared in `secrets."section/name"` with correct `sopsFile` and `path`.
  2. The corresponding key exists in the encrypted SOPS file.
  3. `home-manager switch` has been run to materialize the decrypted file.

**Resolution:**
1. Verify the secret is declared in `sops.nix`:
   ```bash
   grep -n "ops_agent/jira_token" home-manager/modules/sops.nix
   ```
2. Verify the encrypted key exists:
   ```bash
   sops --in-place secrets/ops-agent.yaml  # editor opens; check for key
   ```
3. Run `task switch` to materialize `~/.config/ops-agent/jira-token`.

---

### 7. Shared Shell Terminal Interference

**Symptom:** Commands fail with exit code 130 (interrupted) or partial output when running alongside other active commands.

**Prevention:**
- Avoid launching multiple long-running commands in the same persistent shell.
- Use isolated shells (`/bin/zsh -f`) for sensitive operations (SOPS, nix build).
- Keep one persistent shell per long-running task.

**Resolution:**
- Rerun the command in a fresh shell:
  ```bash
  /bin/zsh -f -c 'your-command-here'
  ```

---

### 8. Cache-Scan Suggests Common Error Patterns

**Procedure:**
Use the `cache-scan` command (or skill) to identify recent failures:
```bash
cache-scan --days 7
```

Common patterns it finds:
- `error`, `failed`, `traceback` — code/logic issues
- `permission denied` — file or credential access problems
- `exit code` — abnormal termination clues
- `untracked`, `uncommitted` — git tracking issues

---

## Quick Checklist Before `task switch`

- [ ] New files tracked: `git status` shows only expected changes
- [ ] Age key available: `ls ~/.config/sops/age/keys.txt`
- [ ] Changes committed: `git commit -m "..."`
- [ ] No shared-shell interference: use isolated shells for heavy operations
- [ ] `task generate:agent-instructions` run if instructions were edited

---

## When to Use This Skill

- Setup errors or build failures on a fresh machine.
- After adding new scripts, secrets, or config files.
- Debugging mysterious Nix errors or flake evaluation failures.
- Confirming environment is correctly configured before running tasks.
