---
name: ops-agent
description: 'Run the local ops-agent CLI for Jira issue lookup, Jira comments or transitions, ECS status checks, and ECS force deploys for MDP tickets. Use when the task mentions ops-agent, Jira workflow updates, ECS status, or MDP ticket operations.'
argument-hint: 'Describe the Jira or ECS task to run through ops-agent'
user-invocable: true
---

# Ops Agent

Use this skill when the local `ops-agent` command is the safest path for Jira and ECS operational tasks.

## When To Use
- Fetch a Jira ticket summary, assignee, status, or description.
- List or apply Jira workflow transitions.
- Post a Jira comment tied to an MDP ticket.
- Check ECS task status for `web` or `data` services.
- Force a new ECS deployment for an MDP ticket service.

## Procedure
1. Confirm the command exists with `command -v ops-agent`.
2. Confirm required secrets exist:
   `~/.config/ops-agent/jira-base-url` and `~/.config/jira/token`.
3. If prerequisites are missing, stop and direct the user to run `scripts/provision-secrets.sh`, then re-run their Home Manager apply.
4. Run `ops-agent "<user request>"`.
5. Summarize the result with the important ticket IDs, transitions, service names, deployment actions, and errors.

## Notes
- Prefer this skill over handwritten Jira REST or AWS CLI mutations when the request fits the built-in `ops-agent` flow.
- The underlying CLI already knows the MDP cluster and service naming conventions.