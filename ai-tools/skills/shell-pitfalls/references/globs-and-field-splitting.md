# zsh nullglob: "no matches found" aborts the command

Unlike bash, zsh **errors out** when a glob matches nothing — the command never
runs at all:

```zsh
# Aborts with "zsh: no matches found: docker-compose*.yml" if none exist
ls docker-compose*.yml

# Guard 1: null_glob in a subshell — the unmatched word vanishes, no error
( setopt local_options null_glob; ls docker-compose*.yml )

# Guard 2: let fd do the matching (no shell glob involved) — best for one-shots
fd -g 'docker-compose*.yml' --max-depth 1

# Guard 3: hand the quoted pattern to a tool that globs internally
rg --glob 'docker-compose*.yml' 'needle' .
```

## The `(N)` qualifier does NOT work in the agent shell

This is the trap inside the trap. `foo*(N)` is the answer every zsh reference
gives, and it fails here:

```zsh
echo nomatch-probe-*.zst(N)
# (eval):1: no matches found: nomatch-probe-*.zst(N)
```

The agent's Bash-tool shell runs with **`nobareglobqual`** set, which disables
bare glob qualifiers entirely — so `(N)` is parsed as literal text, the word
still matches nothing, and the abort fires anyway. Confirm on any host with:

```zsh
setopt          # agent shell prints exactly: nobareglobqual, nohashdirs
zsh -f -c setopt  # a pristine zsh prints neither — the default is bareglobqual ON
```

That difference is why a `(N)` guard copied from an interactive session, from
documentation, or from a committed script keeps failing when an agent runs it.
Use Guard 1/2/3 above. If you truly need qualifiers, re-enable them first —
`( setopt bareglobqual; ls docker-compose*.yml(N) )` — but `null_glob` is
shorter and needs no qualifier.

Observed failures: `docker-compose*.yml`, `~/.config/ops-agent/config*`,
`session_*.log.zst(N)`, `/Applications/Brave*.app`, and
`home-manager/modules/plasma*` with no match killed whole `&&` chains. In
`zsh -c` one-shots prefer `fd`; in committed zsh scripts add `setopt nullglob`.
Bash behaves differently (passes the literal pattern through), which is why a
snippet tested in bash breaks under zsh.

**The silent-truncation case is the expensive one.** A multi-target search
where only one target is a no-match glob aborts before *any* of it runs:

```zsh
rg -n 'bareglobqual' ~/.zshrc ~/.zshenv ~/.config/zsh/* chezmoi/dot_zshrc*
# (eval):1: no matches found: chezmoi/dot_zshrc*
# → ~/.zshrc and ~/.zshenv were never searched. Nothing says so.
```

Reading that output as "the pattern is not in any of those files" is the wrong
conclusion, and nothing on screen contradicts it. Quote or drop the speculative
path rather than letting it decide whether the command runs.

**How far the abort reaches** depends on the separator, and the pipeline case is
the quiet one:

```zsh
zsh -c 'echo A && ls nope*glob && echo B'   # A, error — B never runs
zsh -c 'ls nope*glob | wc -l'               # error, then prints 0 (!)
```

In a pipeline the globbing command is skipped but the rest still runs, so
`wc -l` reports `0` — indistinguishable from a real "zero matches" answer.

## `?` and `[` are glob characters too — quote URLs

The same abort fires on characters that don't look like globs at all. A `gh api`
path with a query string is the recurring case:

```bash
# Aborts: "(eval):1: no matches found: repos/OWNER/REPO/contents/f.ts?ref=prod"
gh api repos/OWNER/REPO/contents/f.ts?ref=prod -q .content

# Right: quote the whole path
gh api 'repos/OWNER/REPO/contents/f.ts?ref=prod' -q .content
```

This hit four separate sessions on `contents/…?ref=<branch>` fetches. The `*`
examples above read as "file globbing," so a URL doesn't register as in scope —
it is. **Quote every argument containing `?`, `*`, `[`, or `~`**, including URLs,
`curl` query strings, and regex passed positionally.

## zsh does not word-split unquoted expansions

The most expensive trap in this file, because nothing errors at the point of the
mistake. Bash splits an unquoted `$var` on `$IFS`; **zsh does not** (no
`SH_WORD_SPLIT` by default). Every bash idiom that relies on implicit splitting
silently yields *one* word:

```zsh
p="a b"; set -- $p; echo $#        # zsh -> 1    bash -> 2
l="x y z"; for w in $l; do …; done # zsh -> 1 iteration   bash -> 3
arr=($var)                         # zsh -> one element   bash -> n elements
```

The damage lands downstream, disguised as a bug in whatever consumed the value:

```zsh
# Wrong: $1 becomes the entire pair, $2 is empty
for pair in "origin/main origin/dev6" "origin/dev6 HEAD"; do
  set -- $pair
  git merge-base $1 $2
done
# fatal: ambiguous argument 'origin/main origin/dev6...': unknown revision…
# fatal: empty string is not a valid pathspec
```

Two separate sessions wrote exactly this loop and burned ~20 git invocations
before the cause was clear — the errors name *git* revisions, so they read as a
bad ref, not a shell problem.

**Fixes, in order of preference:**

```zsh
# 1. Use a real array — portable, no splitting needed
pairs=("origin/main origin/dev6" "origin/dev6 HEAD")
for pair in "${pairs[@]}"; do
  a="${pair%% *}"; b="${pair##* }"     # parameter expansion, not splitting
  git merge-base "$a" "$b"
done

# 2. Restructure so each field is its own loop variable
for a b in origin/main origin/dev6  origin/dev6 HEAD; do …; done   # zsh-only

# 3. Ask zsh for the split explicitly
set -- ${=pair}                        # =  forces word splitting
```

**Signature to memorize:** an error quoting *two space-separated values inside
one set of quotes* (`'origin/main origin/dev6...'`, `'mdpmdd-879 e6f6e07…'`)
means an unquoted expansion didn't split. Paired with a second error about an
*empty* argument (`'^{tree}'`, `empty string is not a valid pathspec`) from the
variable that should have held field 2, it is conclusive.

Do not "fix" this with `setopt SH_WORD_SPLIT` — it changes expansion semantics
for the whole script and breaks correctly-quoted code elsewhere in it.
