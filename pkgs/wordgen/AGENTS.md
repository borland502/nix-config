# wordgen — agent notes

Go CLI (cobra). Generates words and exports word lists from open-source corpora. Imported from `github.com/borland502/wordgen`, which was
retired once this became the source of truth.

## Working on it

```bash
cd pkgs/wordgen
task check          # gofmt -l + go vet + go test
task build          # local binary into dist/
task run -- --help
task nix:build      # what actually ships
```

## Assets

`assets/` carries the source word lists. The bulk lists are stored **zstd
compressed** (`*.txt.zst`) — 17.8 MB of plain text became 6.3 MB. Only
`assets/all.json.zst` is embedded into the binary via `go:embed`; the rest are
inputs to `scripts/build_all_words_json.py`, which decompresses them
transparently and must keep emitting the logical `.txt` source labels so the
generated index does not shift.

Regenerate the index with `python3 scripts/build_all_words_json.py` after
changing any source list.

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
