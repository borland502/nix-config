# shop-scan

Price comparison across public storefront listings, at human pace.

It drives a real browser via `playwright-cli` so that ordinary bot *scanning* —
which rejects plain `curl`/`fetch` with 403s, 500s, or empty bodies — sees a
normal browser. That is the entire purpose: fair price comparison on pages any
logged-out visitor can read.

## What it will not do

- no user-agent or fingerprint spoofing, no proxy or IP rotation
- no CAPTCHA solving, no retry-until-through loop
- no authentication, and no access to anything a logged-out visitor cannot see

If a site returns a real challenge or a soft refusal, the run **aborts with exit
code 3**. Getting past a challenge is the operator's decision, not the tool's.

Pacing is enforced rather than advisory: a randomised delay follows every page
load (6 s ±40 %, 3 s floor) and a hard per-run page cap applies. There is
deliberately no flag to turn either off.

## Usage

```bash
shop-scan search <amazon|ebay> <query...>   [--limit N] [--delay S] [--json]
shop-scan item   <amazon|ebay> <id> [id...] [--json]
shop-scan close
```

```bash
shop-scan search amazon "N305 firewall mini pc i226"
shop-scan item   amazon B0H5PHNKCF
```

`item` reports `BAREBONE` vs `configured`, which is the distinction that matters
when comparing mini-PC listings — many are sold with no RAM or SSD at all.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | success |
| 2 | browser missing, or the page would not open |
| 3 | the site returned a bot challenge — stopped deliberately |
| 4 | per-run page cap reached |

## Notes

`playwright-cli` comes from `npx` on demand. If chromium is missing:

```bash
npx --yes @playwright/cli@latest install-browser chrome-for-testing
```

Browser state (snapshots, console logs) is written to
`~/.cache/claude/shop-scan/`, never the working directory.
