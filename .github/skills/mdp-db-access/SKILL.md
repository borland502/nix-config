---
name: mdp-db-access
description: Access the mdp-application database from the local Docker db container or AWS-backed environments with credential-refresh safeguards (kion/gkion).
argument-hint: Describe the db access goal (query, validation, seed check, or aws env lookup).
user-invocable: true
---

# MDP Database Access

Use this skill for mdp-application database access via:
- Local Docker DB container (`db`)
- AWS-backed workflows that require temporary credentials

This skill is intended for both Copilot and Claude workflows in this repo.

## Preflight

1. Confirm command availability:
```bash
command -v docker
command -v psql
command -v aws
command -v gkion
```

2. If `gkion` is missing, install as a Go executable:
```bash
mkdir -p "$HOME/.local/src"
if [ ! -d "$HOME/.local/src/gkion/.git" ]; then
  git clone https://github.com/borland502/gkion.git "$HOME/.local/src/gkion"
fi
cd "$HOME/.local/src/gkion"
go install ./cmd/gkion
command -v gkion
```

3. Validate AWS credentials sourced from the Kion cache:
```bash
AWS_ACCESS_KEY_ID="$(<"$HOME/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID")" \
AWS_SECRET_ACCESS_KEY="$(<"$HOME/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY")" \
AWS_SESSION_TOKEN="$(<"$HOME/.cache/kion-aws-cache/AWS_SESSION_TOKEN")" \
aws sts get-caller-identity
```

If this fails with expired/invalid token behavior, prompt the user to refresh immediately:
- Run `kion s` (interactive refresh), or
- Run `gkion shell` / `gkion env` (Go-based refresh flow)

Then re-run credential validation.

## Local Docker DB Access (mdp-application)

Use patterns proven in cache logs:

```bash
docker exec -i db psql -U postgres -d mdp -v ON_ERROR_STOP=1 -X -qAt -F $'\t' -c "SELECT now();"
```

Read-only query example:
```bash
docker exec -i db psql -U postgres -d mdp -v ON_ERROR_STOP=1 -X -qAt -F $'\t' \
  -c "select prod_lblr_rebt_agrmt_id, rebt_agrmt_trmntn_dt from mdp_ods.prod_lblr_rebt_agrmt limit 20;"
```

SQL file execution pattern:
```bash
docker exec -i db psql -U postgres -d mdp -v ON_ERROR_STOP=1 < tmp/query.sql
```

Safe validation pattern for migration/seed SQL:
```bash
{ printf "BEGIN;\n"; cat database/load-test-data/some-seed.sql; printf "\nROLLBACK;\n"; } \
  | docker exec -i db psql -U postgres -d mdp -v ON_ERROR_STOP=1
```

## AWS-Backed Access Pattern

When commands require AWS context, always inject from cache explicitly:

```bash
AWS_ACCESS_KEY_ID="$(<"$HOME/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID")" \
AWS_SECRET_ACCESS_KEY="$(<"$HOME/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY")" \
AWS_SESSION_TOKEN="$(<"$HOME/.cache/kion-aws-cache/AWS_SESSION_TOKEN")" \
aws <service> <operation> ...
```

This pattern is used repeatedly in cached workflows (SSM, CloudFormation, SQS, S3).

## Credential Expiry Handling (Required Prompt Behavior)

If any AWS call fails due to auth/session expiry, stop and prompt:
1. "Credentials appear expired. Please run `kion s` or `gkion` to refresh auth."
2. After user confirms refresh, re-run `aws sts get-caller-identity`.
3. Only then continue DB or environment operations.

## Query Principles

- Prefer read-only checks first; avoid writes unless explicitly requested.
- Use `-v ON_ERROR_STOP=1` for psql so failures are surfaced immediately.
- Use `-X` to avoid local `psqlrc` side effects.
- Use `-qAt -F $'\t'` for deterministic script-friendly output.
- Keep changes reversible: validate write scripts inside a transaction (`BEGIN ... ROLLBACK`) where possible.

## Typical Command Set

- Check db container alive:
```bash
docker ps --format '{{.Names}}' | rg '^db$'
```

- Basic connectivity:
```bash
docker exec db psql -U postgres -d mdp -c 'select 1;'
```

- AWS identity sanity check:
```bash
AWS_ACCESS_KEY_ID="$(<"$HOME/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID")" \
AWS_SECRET_ACCESS_KEY="$(<"$HOME/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY")" \
AWS_SESSION_TOKEN="$(<"$HOME/.cache/kion-aws-cache/AWS_SESSION_TOKEN")" \
aws sts get-caller-identity
```

## Failure Triage

- `psql: could not connect`: confirm `db` container is running.
- `ExpiredToken` / `InvalidClientTokenId`: prompt user to run `kion s` or `gkion`, then retry.
- Missing cache files under `~/.cache/kion-aws-cache`: refresh auth first (`kion s`/`gkion`) and re-check.
