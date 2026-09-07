# gopwgen — agent notes

Go CLI (cobra). Generates passwords and human-readable passphrases. Imported from `github.com/borland502/gopwgen`, which was
retired once this became the source of truth.

## Working on it

```bash
cd pkgs/gopwgen
task check          # gofmt -l + go vet + go test
task build          # local binary into dist/
task run -- --help
task nix:build      # what actually ships
```

## Note

Passphrase output is the reason this exists — prefer it over random strings when
a human has to read or retype the value.

## Packaging notes

`buildGoModule` needs no hand-rolled dependency derivation — `vendorHash`
covers the whole module graph. After changing `go.mod`, set `vendorHash` to
`lib.fakeHash`, run `nix build`, and paste back the printed `got:` hash.

`taskfile_integration_test.go` exercises `task deploy/undeploy` and is
excluded from the Nix `src` — it needs a Taskfile and the `task` binary the
build sandbox does not have. It still runs under a local `task test`.

Version metadata is injected via `ldflags` into `internal/version`; the Nix
build stamps `Commit=nix` and a zero timestamp so the output is reproducible.

## Applicable global skills

Deployed globally from `ai-tools/skills/` — invoke by name rather than improvising:

- **ops-nix-pitfalls** — any `nix build` / `task switch` failure, and before editing `default.nix`.
- **flow-verification-before-completion** — before claiming this builds or works.
- **flow-test-driven-development** — when adding behaviour, not just wiring.
- **shell-pitfalls** — quoting, globbing, `zsh`-vs-`bash` surprises.
- **git-finish-branch** / **git-request-review** — when the work is done.

## Repo rules that apply here

- This is a **public** repo. No internal hostnames, URLs, or credentials in
  source, comments, or docs — see the root `AGENTS.md`.
- Changing dependencies means refreshing a Nix hash. The Taskfile prints the
  exact steps; never hand-edit a hash to silence an error.
