#!/usr/bin/env bash

# Bootstrap a fresh Linux or WSL install: install Nix, then apply chezmoi and Home Manager.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect whether we are running inside WSL.
IS_WSL=false
if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
  IS_WSL=true
fi

# ── 1. Nix ────────────────────────────────────────────────────────────────────
if ! command -v nix > /dev/null 2>&1; then
  echo "==> Installing Nix via Determinate Systems installer..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm

  # Source Nix for the remainder of this script.
  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
else
  echo "==> Nix already installed ($(nix --version))"
fi

# ── 2. Bootstrap configuration via go-task ────────────────────────────────────
# Remove any standalone direnv profile entry before home-manager activates — home-manager
# owns direnv (programs.direnv) and will conflict with a pre-existing profile installation.
if nix profile list 2>/dev/null | grep -q 'direnv'; then
  echo "==> Removing standalone direnv from nix profile (home-manager will manage it)..."
  nix profile remove direnv 2>/dev/null || true
fi

echo "==> Applying configuration via go-task..."
cd "$SCRIPT_DIR"

nix shell nixpkgs#go-task nixpkgs#chezmoi --command bash -euo pipefail -c '
  task chezmoi-init
  task chezmoi-apply
  task home-switch
'

# ── 3. Allow the .envrc ───────────────────────────────────────────────────────
direnv allow .

# ── 4. Source the home-manager session so this shell is fully provisioned ─────
_hm_vars="$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
if [[ -f "$_hm_vars" ]]; then
  # hm-session-vars.sh references __HM_SESS_VARS_SOURCED without a default, so
  # temporarily suspend -u to avoid "unbound variable" under set -euo pipefail.
  set +u
  # shellcheck disable=SC1090
  . "$_hm_vars"
  set -u
  echo "==> Sourced home-manager session vars."
else
  echo "==> home-manager profile not found at $_hm_vars; open a new shell to pick up the full environment."
fi

# ── 5. Set zsh as the default login shell ─────────────────────────────────────
_zsh_path="$HOME/.nix-profile/bin/zsh"
if [[ -x "$_zsh_path" ]]; then
  if [[ "$SHELL" != "$_zsh_path" ]]; then
    echo "==> Registering $_zsh_path as a valid login shell..."
    if ! grep -qxF "$_zsh_path" /etc/shells 2>/dev/null; then
      echo "$_zsh_path" | sudo tee -a /etc/shells > /dev/null
    fi
    echo "==> Setting zsh as your default login shell..."
    chsh -s "$_zsh_path"
  fi
  echo ""
  echo "==> Open a new terminal (or run 'exec \$HOME/.nix-profile/bin/zsh -l') to start using zsh + starship."
else
  echo ""
  echo "==> Zsh not found at $_zsh_path — open a new shell to pick up the full environment."
fi

# ── 6. Bootstrap the Windows host (WSL only) ─────────────────────────────────
if [[ "$IS_WSL" == true ]]; then
  # Ensure WSL interop is enabled so we can invoke powershell.exe.
  if ! grep -q '^\[interop\]' /etc/wsl.conf 2>/dev/null; then
    echo "==> Enabling WSL interop in /etc/wsl.conf..."
    printf '\n[interop]\nenabled=true\nappendWindowsPath=true\n' | sudo tee -a /etc/wsl.conf > /dev/null
  elif ! grep -qP '^\s*enabled\s*=\s*true' /etc/wsl.conf 2>/dev/null; then
    echo "==> [interop] section exists but interop may not be enabled; please verify /etc/wsl.conf."
  fi

  _bootstrap_win="$SCRIPT_DIR/scripts/wsl/bootstrap-windows.sh"
  if [[ -f "$_bootstrap_win" ]]; then
    echo "==> Running Windows bootstrap..."
    bash "$_bootstrap_win"
  else
    echo "==> Windows bootstrap script not found at $_bootstrap_win; skipping."
  fi
fi

# ── 7. Provision secrets ─────────────────────────────────────────────────────
_provision_secrets="$SCRIPT_DIR/scripts/provision-secrets.sh"
if [[ -f "$_provision_secrets" ]]; then
  echo "==> Running secret provisioning..."
  bash "$_provision_secrets"
else
  echo "==> Secret provisioning script not found at $_provision_secrets; skipping."
fi

echo ""
if [[ "$IS_WSL" == true ]]; then
  echo "==> Setup complete.  Please run wsl --shutdown and start a new WSL session to ensure all changes take effect."
else
  echo "==> Setup complete.  Open a new terminal session to ensure all changes take effect."
fi
