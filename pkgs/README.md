# pkgs/ — tools built from this repo

One directory per tool, **named for the tool, not its language**. Callers should
not need to know what a thing is written in; `pkgs/shop-scan` is the convention,
`pkgs/typescript/shop-scan` is not.

Each directory owns its source, its dependency manifest, and a `default.nix`
that builds it. Registration is explicit in [`default.nix`](./default.nix) —
a directory is not a package until it is listed there, so a scratch directory
can never silently join the build.

Build and run one:

```bash
nix build .#shop-scan && ./result/bin/shop-scan --help
nix run   .#shop-scan -- search amazon "N305 firewall mini pc"
```

## Which layout to use

The dividing line is **dependencies**, not language. A dependency-free bash
helper belongs in `chezmoi/dot_local/bin/executable_*` as before; this directory
is for anything that needs a build step or third-party libraries.

| Language | Builder | Dependency pinning |
| --- | --- | --- |
| TypeScript (bun) | `stdenv.mkDerivation` + `bun build --compile` | fixed-output `node_modules` derivation keyed on `bun.lock` |
| Python | `buildPythonApplication`, `pyproject = true` | `pyproject.toml`, resolved from nixpkgs |
| Go | `buildGoModule` | `vendorHash` |

### TypeScript

nixpkgs has no `buildBunPackage`, so [`shop-scan/default.nix`](./shop-scan/default.nix)
follows the shape nixpkgs uses for its own bun packages (`pkgs/by-name/hu/hunk`):

1. A **fixed-output derivation** runs `bun install --frozen-lockfile`. This is the
   only phase allowed network access; `outputHash` pins everything it fetched.
2. The real build copies those `node_modules` in and runs `bun build --compile`,
   producing one static binary. It is hermetic — no network.

`dontFixup` and `dontStrip` are both required: the compiled output is a
self-extracting binary with the bun runtime appended, and stripping or
RPATH-rewriting it corrupts the payload.

**Updating dependencies:** change `package.json`, run `bun install`, commit the new
`bun.lock`, then set `outputHash` to `lib.fakeHash`, run `nix build .#<tool>`, and
paste back the hash nix prints as `got:`. This is the same churn `buildGoModule`'s
`vendorHash` causes; there is no way around it for a fixed-output derivation.

**Cost:** `--compile` embeds the whole bun runtime, so binaries are ~100 MB. That
is fine for a handful of tools and would not be fine for fifty.

Day-to-day development uses ordinary TypeScript tooling, no Nix in the loop:

```bash
cd pkgs/shop-scan
bun install
bun run typecheck     # tsc --noEmit, strict + noUncheckedIndexedAccess
bun run dev           # bun --watch
```

### Python

Two artifacts are possible, and the choice is about the *target*, not taste:

- **Nix closure** (`buildPythonApplication`) for hosts this flake manages.
- **zipapp** (`task <tool>:build:pyz`) for hosts it does not — a single
  executable `.pyz` that runs on any Python >= 3.11. This is what reaches
  `ellone`: aarch64, no Nix, and no aarch64 builder exists here.

A zipapp is only architecture-independent while every runtime dependency is
`py3-none-any`. The build task asserts that rather than trusting it — one
compiled wheel would silently pin the artifact to the build machine's arch, and
the failure would surface only on the target. Keep dev tooling (mypy, ruff,
which do ship compiled extensions) in `[dependency-groups]`, never in
`[project.dependencies]`.

Follow the upstream idiom — a `pyproject.toml` plus a thin `default.nix` calling
`buildPythonApplication { pyproject = true; }`, registered with
`pkgs.python3.pkgs.callPackage`. Do **not** reach for `uv`/PEP 723 inline
dependencies here: Nix is already the resolver, and a second one fights it.

### Go

`buildGoModule` is the direct analogue of the other two: `src`, a `vendorHash`
covering the module cache, and the build is otherwise automatic. It is the least
friction of the three, because Go's module graph maps cleanly onto one hash.
