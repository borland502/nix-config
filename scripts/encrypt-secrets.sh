#!/usr/bin/env -S zsh -f
# Non-interactive variant of secret provisioning for ops-agent.yaml.
# Reads tokens from their standard config locations and writes them into the
# SOPS-encrypted secrets/ops-agent.yaml in this repo.
#
# Prerequisites: age key at ~/.config/sops/age/keys.txt, tokens already placed
# at their expected paths (run provision-secrets.sh first if needed).
# Covered by tests/test_secret_provisioning.zsh.
emulate -R zsh
setopt err_exit no_unset pipe_fail

REPO_ROOT=${0:A:h:h}
YAML=$REPO_ROOT/secrets/ops-agent.yaml
export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt

jira_token=$(/bin/cat $HOME/.config/ops-agent/jira-token)
confluence_token=$(/bin/cat $HOME/.config/confluence/token)
confluence_url=$(/bin/cat $HOME/.config/confluence/base-url 2>/dev/null || print -r -- '')

if [[ -z $confluence_url ]]; then
	print -ru2 -- 'encrypt-secrets: ~/.config/confluence/base-url not found'
	exit 1
fi

sops --set '["ops_agent"]["jira_token"] "'"$jira_token"'"' $YAML
sops --set '["ops_agent"]["confluence_base_url"] "'"$confluence_url"'"' $YAML
sops --set '["ops_agent"]["confluence_token"] "'"$confluence_token"'"' $YAML

print -r -- "Done. Keys written to $YAML:"
sops -d $YAML | grep -E '^\s+\w+:' | awk '{print $1}'
