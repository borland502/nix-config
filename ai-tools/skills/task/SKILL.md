---
name: task
description: task (go-task) — Makefile replacement with YAML syntax, dependency graphs, parallel execution, namespacing, and built-in watch mode. Use when reading, writing, or debugging Taskfile.yml task definitions.
---

# task (go-task)

`task` is a task runner that reads `Taskfile.yml`. It replaces Make with YAML syntax, explicit dependencies, parallel execution, and cross-platform support. The binary is `task`; the config file is `Taskfile.yml` (or `Taskfile.yaml`).

## Running Tasks

```bash
# Run a task
task build

# Run multiple tasks sequentially
task lint test build

# Run multiple tasks in parallel
task -p lint test

# Dry-run: print what would run without executing
task -n build

# Force run even if task is up-to-date
task -f build

# Pass variables
task build VERSION=1.2.3

# List tasks with descriptions
task -l

# List all tasks including those without descriptions
task -a

# Show summary for a specific task
task --summary build

# Watch a task and re-run on file changes
task -w build
```

## Taskfile.yml Structure

```yaml
version: '3'

vars:
  APP_NAME: myapp
  BUILD_DIR: dist

env:
  CGO_ENABLED: '0'

tasks:
  default:
    desc: List all tasks
    cmds:
      - task -l

  build:
    desc: Compile the application
    deps: [lint]           # Run lint first
    cmds:
      - go build -o {{.BUILD_DIR}}/{{.APP_NAME}} ./cmd/...
    generates:
      - dist/myapp         # Enables up-to-date check

  lint:
    desc: Run linter
    cmds:
      - golangci-lint run ./...
    sources:
      - '**/*.go'          # Only re-run if .go files changed

  test:
    desc: Run tests
    cmds:
      - go test ./...

  clean:
    desc: Remove build artifacts
    cmds:
      - rm -rf {{.BUILD_DIR}}

  release:
    desc: Build and publish
    deps: [test, lint]
    cmds:
      - task: build
        vars: { BUILD_DIR: release }
```

## Namespaces

Large Taskfiles can split into sub-files with namespacing:

```yaml
# Taskfile.yml
version: '3'
includes:
  db: ./tasks/db.yml         # Tasks callable as "task db:migrate"
  docker: ./tasks/docker.yml # Tasks callable as "task docker:build"
```

```yaml
# tasks/db.yml
version: '3'
tasks:
  migrate:
    cmds:
      - flyway migrate
  seed:
    cmds:
      - go run ./cmd/seed
```

## Key Features

### Up-to-Date Checks

```yaml
tasks:
  codegen:
    sources:
      - schema.graphql
      - '**/*.proto'
    generates:
      - generated/**/*.go
    cmds:
      - buf generate
```

Task skips execution if `generates` files are newer than `sources`.

### Dynamic Variables

```yaml
vars:
  GIT_SHA:
    sh: git rev-parse --short HEAD
  DATE:
    sh: date -u +%Y%m%d
```

### Internal Tasks (not listed)

```yaml
tasks:
  _setup:
    internal: true
    cmds:
      - mkdir -p dist
```

### Dotenv Support

```yaml
dotenv:
  - .env
  - .env.local
```

## Common Flags

| Flag | Effect |
|---|---|
| `-l` | List tasks with descriptions |
| `-a` | List all tasks (including undescribed) |
| `-n` / `--dry` | Print commands without running |
| `-f` / `--force` | Ignore up-to-date checks |
| `-p` / `--parallel` | Run CLI-provided tasks in parallel |
| `-w` / `--watch` | Re-run on source file changes |
| `-C N` | Concurrency limit for parallel tasks |
| `--summary <task>` | Show full task documentation |
| `-g` | Run global `~/Taskfile.yml` |

## Best Practices

- Use `desc:` on every user-facing task so `task -l` is useful.
- Use `sources:` + `generates:` for idempotent tasks (codegen, compilation).
- Prefix internal helper tasks with `_` and set `internal: true` to hide them from listings.
- Use `deps:` for required predecessors; use `cmds: - task: <name>` for explicit sequential calls within a task.
- Keep variable names `UPPER_CASE`; access them as `{{.VAR_NAME}}`.
