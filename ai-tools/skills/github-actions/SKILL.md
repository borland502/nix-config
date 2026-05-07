---
name: github-actions
description: Build secure, efficient GitHub Actions CI/CD workflows with action pinning, OIDC authentication, least-privilege permissions, caching, matrix strategies, and deployment patterns. Use when creating or reviewing .github/workflows/*.yml files.
origin: github/awesome-copilot
---

# GitHub Actions CI/CD

## Security-First Rules

### Action Pinning (critical)

Always pin actions to a full-length commit SHA, never to mutable tags or branches:

```yaml
# CORRECT — immutable, supply-chain safe
uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1

# WRONG — tag @v4 can be silently moved to malicious commit
uses: actions/checkout@v4
uses: actions/checkout@main
```

Use Dependabot or Renovate to automate SHA updates when action versions change.

### Least Privilege Permissions

```yaml
permissions:
  contents: read  # default — never grant write unless the workflow needs it

jobs:
  deploy:
    permissions:
      contents: read
      id-token: write  # only for OIDC
```

### OIDC — No Long-Lived Credentials

```yaml
jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@<sha> # v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActions
          aws-region: us-east-1
```

Configure trust policy in AWS IAM to trust `token.actions.githubusercontent.com`.

### Secrets

- Access via `${{ secrets.MY_SECRET }}` — never hardcode
- Use environment-specific secrets (`environment: production`) for staged access
- Never log or echo secrets, even if masked

## Workflow Structure

```yaml
name: Build and Deploy

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true   # true = cancel stale PR builds; false = don't cancel deploys

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          fetch-depth: 1  # shallow clone; use 0 only if history is needed

  build:
    needs: test
    outputs:
      artifact_path: ${{ steps.pkg.outputs.path }}
    steps:
      - id: pkg
        run: |
          zip -r dist.zip dist
          echo "path=dist.zip" >> "$GITHUB_OUTPUT"

  deploy:
    needs: build
    environment: production
    if: github.ref == 'refs/heads/main'
    steps:
      - run: echo "Deploying ${{ needs.build.outputs.artifact_path }}"
```

## Caching

```yaml
- uses: actions/cache@668228422ae6a00e4ad889ee87cd7109ec5666a7 # v5.0.4
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

- Use `hashFiles()` of lock files as cache keys — only invalidates when deps change
- Add `restore-keys` as fallbacks for partial matches
- Built-in caching: `actions/setup-node`, `actions/setup-python` cache automatically when configured

## Matrix Strategy

```yaml
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, windows-latest]
        node: [18.x, 20.x]
    steps:
      - uses: actions/setup-node@3235b876344d2a9aa001b8d1453c930bba69e610 # v3.9.1
        with:
          node-version: ${{ matrix.node }}
```

## Artifacts

```yaml
- uses: actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f # v7.0.0
  with:
    name: build-output
    path: dist/
    retention-days: 30

- uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
  with:
    name: build-output
```

## Security Scanning

```yaml
- name: Dependency review (PRs only)
  uses: actions/dependency-review-action@<sha>

- name: CodeQL analysis
  uses: github/codeql-action/analyze@<sha>

- name: Container scanning
  uses: aquasecurity/trivy-action@<sha>
  with:
    image-ref: myapp:${{ github.sha }}
```

## Deployment Strategies

| Strategy | When to use | Key mechanism |
|---|---|---|
| Rolling | Default; stateless apps | `maxSurge`/`maxUnavailable` in K8s |
| Blue/Green | Zero-downtime; instant rollback | Traffic switch at load balancer |
| Canary | Controlled risk; metric-based | Service mesh traffic splitting |
| Feature flags | Decouple deploy from release | LaunchDarkly/Unleash |

## Rollback

```bash
kubectl rollout undo deployment/myapp
# OR
git revert HEAD && git push
```

## Review Checklist

- [ ] Actions pinned to full SHA with version comment
- [ ] `permissions: contents: read` at workflow level
- [ ] OIDC for cloud auth; no long-lived secrets
- [ ] `concurrency` configured
- [ ] `fetch-depth: 1` for checkout (unless history needed)
- [ ] Caching with `hashFiles()` keys
- [ ] `retention-days` set on artifacts
- [ ] Dependency review and CodeQL on PRs
- [ ] Environment protection rules for production
- [ ] `timeout-minutes` on long-running jobs
