#!/usr/bin/env bash
# Non-interactive variant of secret provisioning for ops-agent.yaml.
# Reads tokens from their standard config locations and writes them into the
# SOPS-encrypted secrets/ops-agent.yaml in this repo.
#
# Prerequisites: age key at ~/.config/sops/age/keys.txt, tokens already placed
# at their expected paths (run provision-secrets.sh first if needed).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YAML="$REPO_ROOT/secrets/ops-agent.yaml"
export SOPS_AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"

jira_token=$(/bin/cat "${HOME}/.config/ops-agent/jira-token")
confluence_token=$(/bin/cat "${HOME}/.config/confluence/token")
confluence_url=$(/bin/cat "${HOME}/.config/confluence/base-url" 2>/dev/null || echo "")

if [[ -z "$confluence_url" ]]; then
  echo "encrypt-secrets: ~/.config/confluence/base-url not found" >&2
  exit 1
fi

sops --set '["ops_agent"]["jira_token"] "'"$jira_token"'"' "$YAML"
sops --set '["ops_agent"]["confluence_base_url"] "'"$confluence_url"'"' "$YAML"
sops --set '["ops_agent"]["confluence_token"] "'"$confluence_token"'"' "$YAML"

echo "Done. Keys written to $YAML:"
sops -d "$YAML" | grep -E '^\s+\w+:' | awk '{print $1}'
