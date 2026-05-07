---
name: sec-sops-encrypt
description: Add, update, or manage encrypted secrets in SOPS files. Covers age key provisioning, secret encryption, and common pitfalls.
---

# SOPS Secret Encryption & Management

Use this skill to manage encrypted secrets in this repository using SOPS + age.

## Quick Reference

**First time setup:**
```bash
bash scripts/provision-secrets.sh    # Provision age private key
task switch                          # Materialize decrypted secrets to ~/.config/
```

**Add/update a secret:**
```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops secrets/ops-agent.yaml         # Opens editor; add/edit keys
# Then declare the secret in home-manager/modules/sops.nix and run 'task switch'
```

---

## Workflow: Add a New Secret

### 1. Provision Age Key (One-Time Per Machine)

If `~/.config/sops/age/keys.txt` doesn't exist:

```bash
bash scripts/provision-secrets.sh
```

Follow the interactive prompts to paste your age private key.
- Key format: `AGE-SECRET-KEY-1...`
- Stored at: `~/.config/sops/age/keys.txt` (mode 600)

### 2. Encrypt the Secret into SOPS File

```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops secrets/ops-agent.yaml
```

This opens an editor. Add a new key-value pair:

```yaml
ops_agent:
  jira_base_url: https://jira.example.com
  jira_token: your-secret-token-here
```

Save and close the editor. SOPS encrypts the file automatically.

**Verify encryption:**
```bash
head -5 secrets/ops-agent.yaml | grep -i "ecs_auth\|version"
# Should show encrypted header, not plaintext
```

### 3. Declare Secret in Home Manager Config

Edit `home-manager/modules/sops.nix` and add:

```nix
secrets."ops_agent/jira_token" = {
  sopsFile = ../../secrets/ops-agent.yaml;
  path = "${config.home.homeDirectory}/.config/ops-agent/jira-token";
};
```

**Key points:**
- `sopsFile` path must be relative to the nix file location
- `path` is where the decrypted secret is materialized
- Secret key path uses `/` separator (e.g., `ops_agent/jira_token`)

### 4. Update Code to Read from Secret Path

In your script (e.g., `ops-agent.py`):

```python
def _jira_token() -> str:
    primary = Path.home() / ".config" / "ops-agent" / "jira-token"
    fallback = Path.home() / ".config" / "jira" / "token"
    if primary.exists():
        return primary.read_text().strip()
    return fallback.read_text().strip()  # migration fallback
```

### 5. Apply Changes

```bash
task switch
# Or: home-manager switch
```

The decrypted secret is now available at `~/.config/ops-agent/jira-token`.

---

## Lessons Learned from This Session

### Pitfall 1: Age Key Not Provisioned Before Declaring Secrets

**Error:**
```
the key 'ops_agent/jira_token' cannot be found in /nix/store/.../ops-agent.yaml
```

**Cause:** SOPS secret declared in `sops.nix` but the key doesn't exist in the encrypted SOPS file.

**Prevention:**
- Always provision age key first: `bash scripts/provision-secrets.sh`
- Add secret to encrypted file: `sops secrets/ops-agent.yaml`
- Only then declare it in `sops.nix`
- Run in order: provision → sops edit → declare → switch

### Pitfall 2: SOPS_AGE_KEY_FILE Not Set

**Error:**
```
identity did not match any of the recipients
```

**Cause:** SOPS couldn't find the age private key.

**Prevention:**
```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
# Verify it exists:
ls -la ~/.config/sops/age/keys.txt
```

Set in script header or provision-secrets.sh flow.

### Pitfall 3: Uncommitted Changes Block Nix Build

**Error:**
```
warning: Git tree has uncommitted changes
```

**Prevention:**
```bash
git add secrets/ops-agent.yaml home-manager/modules/sops.nix .github/...
git commit -m "Add ops_agent jira_token secret"
```

SOPS file changes must be staged and committed.

### Pitfall 4: Secret Path Mismatch

**Scenario:** Secret declared in `sops.nix` with path `~/.config/ops-agent/jira-token`, but code tries to read from `~/.config/jira/token`.

**Prevention:**
- Define path in `sops.nix` clearly
- Reference exact same path in code
- Use environment-agnostic paths (no hardcoded usernames)

### Pitfall 5: Long-Running SOPS Operations in Shared Terminal

**Symptom:** SOPS command times out or hangs when run in a shared shell with other active processes.

**Prevention:**
```bash
# Use isolated shell for sensitive SOPS operations
/bin/zsh -f -c 'export SOPS_AGE_KEY_FILE=...; sops ...'
```

---

## Reference: SOPS File Structure

**Encrypted SOPS file** (`secrets/ops-agent.yaml`):
```yaml
ops_agent:
    jira_base_url: ENC[AES256_GCM,data:...,type:str]
    jira_token: ENC[AES256_GCM,data:...,type:str]
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age:
        - recipient: age19vlys87e2zs36pv4aq2m026qrxxk4e0wh44gxr3y98shrpnamvsqm7mgpk
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            ...
```

**Decrypted view** (only visible inside `sops` editor or after `home-manager switch`):
```yaml
ops_agent:
  jira_base_url: https://jira.example.com
  jira_token: my-secret-token
```

---

## Troubleshooting

### SOPS editor won't open
```bash
export EDITOR=vim  # or nano, emacs
sops secrets/ops-agent.yaml
```

### Can't decrypt file after provisioning key
```bash
# Verify age key is in recipients
sops --show-master-keys secrets/ops-agent.yaml

# Re-add key to recipients if needed
sops --rotate secrets/ops-agent.yaml
```

### Secret not appearing in ~/.config after switch
```bash
# Verify sops.nix declaration syntax
nix flake check path:.

# Check activation script output
home-manager switch --show-trace

# Manually verify decryption
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
sops -d secrets/ops-agent.yaml
```

---

## Next Steps After This Session

1. ✅ Age key provisioned (`~/.config/sops/age/keys.txt`)
2. ✅ `secrets/ops-agent.yaml` encrypted with `ops_agent.jira_base_url`
3. ⏭️  **Add** `ops_agent.jira_token` to encrypted file:
   ```bash
   export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
   sops secrets/ops-agent.yaml
   # Add: ops_agent.jira_token: <your-token>
   ```
4. ⏭️  Uncomment in `home-manager/modules/sops.nix`:
   ```nix
   secrets."ops_agent/jira_token" = {
     sopsFile = ../../secrets/ops-agent.yaml;
     path = "${config.home.homeDirectory}/.config/ops-agent/jira-token";
   };
   ```
5. ⏭️  Run `task switch` to materialize both secrets.
