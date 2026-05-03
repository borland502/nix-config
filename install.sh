#!/usr/bin/env bash

# Install Nix and direnv if not already present, then use direnv to set up the development environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# ── 2. direnv ─────────────────────────────────────────────────────────────────
if ! command -v direnv > /dev/null 2>&1; then
  echo "==> Installing direnv via Nix..."
  nix profile install nixpkgs#direnv

  # Add the shell hook to the user's rc file if it isn't already there.
  _shell="$(basename "${SHELL:-bash}")"
  case "$_shell" in
    zsh)  _rc="$HOME/.zshrc";                        _hook='eval "$(direnv hook zsh)"'    ;;
    bash) _rc="${BASH_ENV:-$HOME/.bashrc}";           _hook='eval "$(direnv hook bash)"'   ;;
    fish) _rc="$HOME/.config/fish/config.fish";      _hook='direnv hook fish | source'    ;;
    *)
      echo "==> Unknown shell '$_shell' — add the direnv hook to your rc file manually."
      _rc=""
      ;;
  esac

  if [[ -n "${_rc:-}" ]] && ! grep -qF "direnv hook" "$_rc" 2>/dev/null; then
    printf '\n# direnv\n%s\n' "$_hook" >> "$_rc"
    echo "==> Added direnv hook to $_rc"
  fi
else
  echo "==> direnv already installed ($(direnv version))"
fi

# ── 3. Allow the .envrc ───────────────────────────────────────────────────────
cd "$SCRIPT_DIR"
direnv allow .

echo ""
echo "==> Setup complete."
echo "    Start a new shell (or run 'direnv reload') in this directory to activate the environment."
