# shop-scan — agent notes

TypeScript/bun CLI that drives a real browser through `playwright-cli` to read
public storefront listings at human pace. See [README.md](./README.md) for usage.

## Working on it

```bash
cd pkgs/shop-scan
task install      # bun install --frozen-lockfile
task typecheck    # tsc --noEmit, strict + noUncheckedIndexedAccess
task run -- search amazon "N305 mini pc"
task nix:build    # what actually ships
```

## Non-negotiable behaviour

The pacing and the bot-wall abort are **the point of the tool**, not incidental
politeness. Do not add a flag to disable the delay, do not add user-agent
spoofing, proxy rotation, or CAPTCHA handling, and do not turn the exit-3 abort
into a retry loop. If a site blocks it, the correct outcome is that the run
stops and says so — matching the `stop-at-anti-bot-walls` guidance.

## Traps already paid for

- `playwright-cli` prints results under a `### Result` header and then echoes
  the code it ran. A greedy JSON match over the whole output swallows the echo —
  slice the Result section.
- There is no `--headless` flag; headless is the default and only `--headed`
  exists.
- Page payloads are **validated with zod, not cast**. Keep it that way: the
  markup changes without notice and a silent shape drift must fail loudly.
- Listing sellers write `8G DDR5` as often as `8GB`; spec regexes must accept
  both.

## Applicable global skills

Deployed globally from `ai-tools/skills/` — invoke by name rather than improvising:

- **ops-nix-pitfalls** — any `nix build` / `task switch` failure, and before editing `default.nix`.
- **flow-verification-before-completion** — before claiming this builds or works.
- **flow-test-driven-development** — when adding behaviour, not just wiring.
- **web-playwright-cli** — the CLI this tool wraps; read it before changing
  the browser plumbing.
- **shell-pitfalls** — quoting, globbing, `zsh`-vs-`bash` surprises.
- **git-finish-branch** / **git-request-review** — when the work is done.

## Repo rules that apply here

- This is a **public** repo. No internal hostnames, URLs, or credentials in
  source, comments, or docs — see the root `AGENTS.md`.
- Changing dependencies means refreshing a Nix hash. The Taskfile prints the
  exact steps; never hand-edit a hash to silence an error.
