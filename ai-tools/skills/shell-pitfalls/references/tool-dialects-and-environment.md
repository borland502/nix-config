# GNU coreutils shadow the BSD tools, even on macOS

On these hosts nix `coreutils` puts **GNU `stat`** on `PATH` ahead of the macOS
BSD `stat` — on darwin and Linux alike. So BSD format syntax silently fails:

```bash
# Wrong on these hosts: GNU stat reads -f as --file-system and treats '%Sm' as a
# filename → "stat: cannot read file system information for '%Sm': No such file…"
stat -f '%Sm' ~/.aws/config

# Right: GNU format syntax
stat -c '%y' ~/.aws/config        # mtime
stat -c '%A %n' ~/.aws/config     # mode + name
```

If you need a portable mtime regardless of which `stat` wins, sidestep it:
`eza -l --time-style=long-iso <file>` or `date -r <file>`. The repo's own
scripts assume GNU `stat -c` for this reason (see `cache-scan`'s header note).

**`date` has the same split, and it bites harder** because macOS documentation,
Stack Overflow answers, and your own muscle memory all reach for BSD flags:

```bash
# Wrong on these hosts: -j/-f are BSD-only
# → "date: invalid option -- 'j'"  … and under `set -e` the script dies mid-way,
#   often after the arithmetic that consumed its empty output already broke
S=$(date -u -j -f '%Y-%m-%d' "$D" +%s)

# Right: GNU syntax
S=$(date -u -d "$D" +%s)
date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ    # relative windows for log queries
```

The same rule covers `readlink -f`, `sed -i` (GNU takes no backup suffix, BSD
requires one), `base64 -w0`, and `find -printf`: **assume GNU syntax on every
host in this fleet, darwin included.** When a flag error names a single letter
you were sure about, check the dialect before rewriting the logic.

## Subshell PATH loss

`env -i`, `sudo`, and a bare `zsh -c '…'` (no `-l`) do **not** inherit the nix
profile + Homebrew `PATH`. Tools that resolve fine interactively — GNU `stat`,
`timeout`, `kion-aws-refresh`, `aws` — suddenly report `command not found`, and it looks
like a missing install when it's a missing PATH.

```bash
# Wrong: bare zsh -c gets the system default PATH — timeout/aws are not on it
zsh -c 'timeout 30 aws s3 ls'

# Right: login shell pulls in the nix/Homebrew profile
zsh -lc 'timeout 30 aws s3 ls'

# Also right: stay in the current (already-provisioned) shell, or pass PATH /
# absolute paths explicitly when a stripped environment is unavoidable
env -i HOME="$HOME" PATH="$PATH" bash -c 'timeout 30 aws s3 ls'
```

The `kac` credential helper PATH-hardens its own refresh internally, but
nothing else on your command line gets that rescue. If a "not found" error
names a tool you know is installed, check *which shell* is resolving it before
reinstalling anything. This is also why the GNU-vs-BSD `stat` trap (above)
sometimes appears to flip: a stripped PATH can fall back to `/usr/bin/stat`
(BSD) while the interactive shell resolves the nix GNU one.

## zsh `local` drops the export attribute

The inverse failure: PATH is fine in the parent, and children still get none.
In zsh, `local VAR=…` creates a **non-exported** parameter even when `VAR` was
exported in the environment; bash keeps the export attribute. So the common
idiom for "adjust PATH without clobbering the caller's" silently launches every
child process with no PATH at all.

```zsh
# Identical source, opposite behavior
f() { local PATH="$PATH"; /usr/bin/env | grep -c '^PATH='; }
f     # zsh  -> 0   children inherit NO PATH
      # bash -> 1   children inherit it

# Fix: re-export inside the function. The export stays function-scoped, so the
# caller's PATH is still restored on return — in both shells.
f() { local PATH="$PATH"; export PATH; PATH="/extra:$PATH"; … }
```

**Signature to memorize:** a child whose shebang is `#!/usr/bin/env python3`
dies with `error: tool 'python3' not found`. That is not a missing interpreter
— with no PATH in the environment, `env` falls back to the system default path
and reaches macOS's `/usr/bin/python3` xcrun shim, which emits that message.

This bit [chezmoi/dot_local/lib/kion-aws-cache](../../../../chezmoi/dot_local/lib/kion-aws-cache):
its PATH-hardening block opened with `local PATH="$PATH"`, which broke every
sourced `kac dump` / `kac clear` under zsh — the shell `kac` exists to be
sourced from — while the bash test fixtures kept passing. A bash-only test
suite cannot catch this; exercise sourced helpers under `zsh -f` too.

The trap is not PATH-specific. Any exported variable a function scopes with
`local` stops reaching children until it is re-exported.

## `rg -h` is `--help`, not "hide filenames"

The most dangerous of the grep→rg habit slips, because it **fails silently in
the wrong direction**: `grep -h` suppresses filename prefixes, but ripgrep uses
`-h` for `--help`. So `rg -h PATTERN file` prints ripgrep's help text and exits
0 — no error, no hint — and whatever consumes that output parses a manual page
as if it were matches.

```bash
# Wrong: prints rg's help; downstream sees ~200 lines of option docs as "data"
rg -h 'command not found' ~/.cache/claude/session_*.log | sort | uniq -c

# Right
rg --no-filename 'command not found' ~/.cache/claude/session_*.log | sort | uniq -c
```

Observed damage: three successive log-analysis passes produced counts of
ripgrep's own `--binary` / `--block-buffered` option lines, and the mistake was
invisible until the *same* output appeared for three different patterns.

**Tell:** identical results from patterns that should differ, or option-looking
strings (`--foo`) in what should be data. Other name collisions worth knowing:
`rg -i` matches grep's `-i`, but grep's `-r`/`-R` have no rg equivalent
(recursion is the default) and `-e` is `--regexp` in both.
