# technitium-dash — agent notes

Python CLI: a live stats and query panel for Technitium DNS, built on `httpx`
and `rich`. This is the only implementation — the stdlib-only predecessor at
`chezmoi/dot_local/bin/executable_technitium-dash` was retired on 2026-09-07,
once this had been deployed to ellone and verified against the live server.

## Working on it

```bash
cd pkgs/technitium-dash
task sync                 # uv sync — dev venv only, the Nix build ignores it
task check                # ruff + ruff format --check + mypy --strict
task run -- --once        # one frame, then exit
task nix:build            # what actually ships
```

Nix builds the artifact; `uv` only drives the local dev loop. Do **not** add
`uv`/PEP 723 inline dependencies to the packaging path — nixpkgs is the resolver
there and a second one fights it.

## Migration status

**Validated against the live server on 2026-09-07.** The zipapp was run on ellone
(aarch64, Python 3.13.5) against the real Technitium API and rendered correctly:
v15.4, 5,898 queries, working sparklines, top columns, and a live feed with
correct local timestamps.

**Host-gated to ellone.** It is deliberately absent from `home.packages` — it is
a wall panel for one machine, not a general CLI. ellone is not a flake or
chezmoi host (aarch64 Debian, no Nix), so there is no module to gate it in; the
gate is simply that nothing installs it anywhere else. It stays registered in
`pkgs/default.nix`, so `nix run .#technitium-dash` still works from any checkout.

Deployment is a **zipapp**, not a Nix closure: ellone is aarch64 with no Nix, and
no aarch64 builder exists here. Every runtime dependency is `py3-none-any`, so a
single `dist/technitium-dash.pyz` runs on both architectures.

```bash
task technitium-dash:build:pyz   # dist/technitium-dash.pyz, ~2.1 MB
task deploy:ellone:dash          # build, install, restart the wall panel
```

`build:pyz` **asserts** that no compiled extension entered the runtime tree — one
non-pure wheel would silently pin the artifact to the build machine's
architecture, and the failure would only show up on the target.

Known intentional differences from the original stdlib script:

- Rendering is rebuilt on `rich`, not transliterated. That removes ~100 lines of
  hand-rolled truecolor/256-colour plumbing, and fixes cell-width measurement —
  the old regex-stripping `vlen` mis-measured double-width and combining
  characters.
- `--print-vtrgb` is ported (see `palette.py`) and verified to reproduce the
  deployed `/etc/vtrgb-monokai` byte for byte. It reads a deployed
  `monokai.toml` when present, which is where the base12..base16 slots come
  from; without one those fall back to base05.
- One pooled `httpx.Client` replaces per-request `urllib` calls — this polls four
  endpoints on a 5s refresh, where reconnecting each time dominated the cycle.

## The wall panel is a Linux VT, and that constrains rendering

ellone runs this as `technitium-dash.service` on **tty1**, with `TERM=linux`,
`COLUMNS=120`, a console font, and a `setvtrgb` palette. Two consequences:

- Debian console fonts ship U+2588 and the box-drawing set but **not** the
  1/8-block ramp U+2581..2587. The fine sparkline ramp renders as garbage there,
  so the ramp follows the terminal's colour depth: rich reports `standard` on a
  Linux VT, which selects `SPARK_COARSE`. Measured 2026-09-07 —
  `TERM=linux` → `standard` → coarse; `TERM=xterm-256color` → `256` → fine.
  Note `COLORTERM=truecolor` overrides `TERM` in rich, but the systemd unit sets
  no `COLORTERM`.
- Any change to the sparkline, box drawing, or colour handling must be checked
  under `TERM=linux` with no `COLORTERM`, not just in a modern terminal.

## Behaviour that must not regress

- The per-name cap is **per name across the whole visible feed**, not per page.
- Exclusions match the name and everything under it, the way a zone reads.
- A failing page 1 means "no feed"; a later page failing mid-walk must not
  discard entries already collected.
- The Sqlite query-log app is optional — its absence is not an outage, and the
  stats panel must still render.

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
