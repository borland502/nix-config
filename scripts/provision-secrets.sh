#!/usr/bin/env bash
# provision-secrets.sh — interactive secret provisioning using gum
# Prompts for sensitive values and persists them to their expected locations.

set -euo pipefail

# ---------------------------------------------------------------------------
# Colour palette (Monokai Spectrumish)
# ---------------------------------------------------------------------------
C_PURPLE="#948ae3"
C_GREEN="#7BD88F"
C_YELLOW="#FCE566"
C_RED="#FC618D"
C_CYAN="#5AD4E6"
C_ORANGE="#fd9353"
C_TEXT="#f7f1ff"
C_MUTED="#8b888f"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
header() {
  echo
  gum style \
    --foreground "$C_PURPLE" --bold \
    --border rounded --border-foreground "$C_PURPLE" \
    --padding "0 2" \
    "$1"
  echo
}

info()    { gum style --foreground "$C_CYAN"   "  $1"; }
success() { gum style --foreground "$C_GREEN"  "  $1"; }
warn()    { gum style --foreground "$C_YELLOW" "  $1"; }
error()   { gum style --foreground "$C_RED"    "  $1"; }
label()   { gum style --foreground "$C_ORANGE" --bold "$1"; }
muted()   { gum style --foreground "$C_MUTED"  "$1"; }

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
header "Secret Provisioning"
muted "  Stores sensitive values in their expected locations on this machine."
echo

# ---------------------------------------------------------------------------
# Age private key → ~/.config/sops/age/keys.txt
# ---------------------------------------------------------------------------
AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"

label "Age private key"
info "Target: ${AGE_KEY_FILE}"
echo

if [[ -f "$AGE_KEY_FILE" ]]; then
  success "Age key already present at ${AGE_KEY_FILE} — nothing to do."
  echo
  exit 0
fi

info "Paste your age private key below (input is hidden)."
muted "  It should start with AGE-SECRET-KEY-1..."
echo

while true; do
  AGE_KEY=$(
    gum input \
      --password \
      --placeholder "AGE-SECRET-KEY-1..." \
      --prompt "> " \
      --prompt.foreground "$C_PURPLE" \
      --cursor.foreground "$C_PURPLE" \
      --width 72 \
      --char-limit 256
  )

  if [[ -z "$AGE_KEY" ]]; then
    error "No input received. Try again, or press Ctrl-C to abort."
    continue
  fi

  # Normalise — strip surrounding whitespace and any trailing carriage returns
  AGE_KEY=$(printf '%s' "$AGE_KEY" | tr -d '\r' | xargs)

  if [[ "$AGE_KEY" != AGE-SECRET-KEY-1* ]]; then
    error "That doesn't look like an age private key (expected AGE-SECRET-KEY-1...)."
    if ! gum confirm \
        --prompt.foreground "$C_YELLOW" \
        --selected.background "$C_PURPLE" --selected.foreground "$C_TEXT" \
        --unselected.foreground "$C_MUTED" \
        "Try again?"; then
      error "Aborted."
      exit 1
    fi
    continue
  fi

  break
done

mkdir -p "$(dirname "$AGE_KEY_FILE")"
printf '%s\n' "$AGE_KEY" > "$AGE_KEY_FILE"
chmod 600 "$AGE_KEY_FILE"

success "Age key written to ${AGE_KEY_FILE} (mode 600)."
echo
muted "  Run \`home-manager switch\` (or \`nixos-rebuild switch\`) to pick up the"
muted "  new key — chezmoi and sops-nix will use it automatically on next apply."
echo
