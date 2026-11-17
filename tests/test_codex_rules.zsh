#!/usr/bin/env -S zsh -f
# The managed Codex rules allow only read-only network helpers outside the
# sandbox; every mutation and ops-agent's prompt mode must keep prompting.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
rules=$repo_root/ai-tools/codex/nix-config.rules

# Codex is installed on macOS hosts only (update-agent-clis); skip elsewhere.
if ! command -v codex >/dev/null 2>&1; then
	print -r -- 'codex-rules: skipped (codex not installed)'
	exit 0
fi

decision() {
	codex execpolicy check --rules $rules -- "$@" | jq -r '.decision // "no-match"'
}

assert_eq "$(decision jira-get 'issue/KEY-1?fields=summary')" allow
assert_eq "$(decision ops-agent --tool jira_get_issue '{"ticket_id":"KEY-1"}')" allow
assert_eq "$(decision ops-agent --tool jira_get_transitions '{"ticket_id":"KEY-1"}')" allow
assert_eq "$(decision ops-agent --tool ecs_get_status '{"ticket_id":"KEY-1","service":"web"}')" allow
assert_eq "$(decision gh-run-logs 123 --repo owner/name --tail 35)" allow

for tool in jira_comment jira_transition ecs_force_deploy aws_cli; do
	assert_eq "$(decision ops-agent --tool $tool '{}')" no-match
done
assert_eq "$(decision ops-agent 'transition KEY-1 to Done')" no-match
assert_eq "$(decision direnv exec /some/repo gh-run-logs 1)" no-match
print -r -- 'codex-rules: ok'
