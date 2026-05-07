---
name: cli-sd
description: Use when doing find-and-replace across files. sd is the project's preferred sed replacement — modern regex (Rust), much simpler syntax than sed, in-place by default. Pairs with rg/fd for the find→replace pipeline.
---

# sd

`sd` is on the shared tooling list as the project's sed replacement. The agent-defaults says it implicitly via the broader "prefer modern Rust replacements" pattern (`rg` for `grep`, `fd` for `find`, `sd` follows the same model for `sed`).

## Quick Reference

```bash
# Replace in stdin → stdout
echo "hello world" | sd "world" "there"

# Replace in a file (in place; sd is in-place by default)
sd "old-name" "new-name" path/to/file.md

# Replace across many files (use rg or fd to enumerate)
rg -l "old-pattern" | xargs sd "old-pattern" "new-pattern"

# Preview without writing (-p / --preview)
sd -p "foo" "bar" file.txt

# Literal mode — no regex (-F / --fixed-strings)
sd -F "$.foo.bar" "_dollar_foo_bar" file.txt

# Capture groups (Rust regex syntax — $1, $2 not \1)
sd '(\w+)\s+(\w+)' '$2 $1' file.txt
```

## Project Context

This branch's Phase 2 used sd to rewrite cross-skill namespace prefixes after ingesting from upstream:

```bash
for f in $(rg -l "superpowers:" ai-tools/skills/); do
  sd 'superpowers:' 'nix-config-tools:' "$f"
done
for f in $(rg -l "docs/superpowers/" ai-tools/skills/); do
  sd 'docs/superpowers/' 'docs/' "$f"
done
```

That's the canonical `rg-l → xargs/loop → sd` pattern. The [reconciliation](../reconciliation/SKILL.md) skill documents the same workflow for future re-syncs.

## Differences from sed

| Concept | sed | sd |
|---|---|---|
| In-place | `sed -i` | default |
| Regex flavor | BRE/ERE (varies) | Rust `regex` crate (PCRE-like, no backtracking) |
| Capture refs | `\1`, `\2` | `$1`, `$2` |
| Delimiter | `s/foo/bar/g` (escape `/`) | `sd 'foo' 'bar'` (separate args) |
| Global by default | no (need `g` flag) | yes |
| Multiline by default | no | yes (Rust regex `m` flag is on for `^/$`, `.` matches `\n` by default off) |

## Common Idioms

### rg→sd pipeline (find then replace)

```bash
# Files containing the pattern, then rewrite all of them
rg -l 'OLD_VAR' | xargs sd 'OLD_VAR' 'NEW_VAR'
```

### Preview first, then commit

```bash
rg -l 'pattern' | xargs sd -p 'pattern' 'replacement'    # preview
rg -l 'pattern' | xargs sd 'pattern' 'replacement'       # apply
```

### Replace using capture groups

```bash
sd '(\w+)@example\.com' 'redacted@$1' contact-list.txt
```

### Update YAML frontmatter origin field across ingested skills

```bash
# Hypothetical: rebrand "origin: ECC" -> "origin: everything-claude-code"
rg -l 'origin: ECC' ai-tools/skills/ \
  | xargs sd '^origin: ECC$' 'origin: everything-claude-code'
```

### Multiline pattern with `(?s)` flag (dotall)

```bash
sd '(?s)BEGIN.*?END' 'REPLACED' file.txt
```

## Flags Worth Knowing

| Flag | Meaning |
|---|---|
| `-p` / `--preview` | Print diff to stdout, don't write |
| `-F` / `--fixed-strings` | Treat pattern as literal, not regex |
| `-s` / `--string-mode` | Same as `-F`, deprecated alias |
| `-f F` | Specify regex flags (`i` ignore case, `m` multiline `^/$`, `s` dotall, `c` case-sensitive, `e` disable unicode, `w` whole word, `x` ignore whitespace) |

Examples: `sd -f i 'foo' 'bar'` (case-insensitive). Multiple flags concatenated: `sd -f is '...' '...'`.

## References

- `references/help.txt` — captured `sd --help` (sd 1.0.0).
- Project: <https://github.com/chmln/sd>.
- Rust regex syntax: <https://docs.rs/regex/latest/regex/#syntax>.

## Notes

- sd writes in place by default — no `-i` flag needed, no backup file. Pipe through `-p` first when uncertain.
- sd's regex engine is `regex` crate, which **does not support backreferences in the search pattern**. `$1` works in the *replacement*; `\1` referring back to a captured group in the *match* does not. This is also true of rg in the default (non-`-P`) mode.
- For shell-special characters (`$`, `&`, etc.) in the replacement, single-quote the replacement to avoid shell expansion: `sd 'foo' '$bar' file` (literal `$bar`, not the shell variable).
- sd does not have an "address" / line-range concept like sed's `1,5s/foo/bar/`. For line-bounded edits, pre-filter with `awk`/`head`/`sed -n 'p'` and pipe in.
