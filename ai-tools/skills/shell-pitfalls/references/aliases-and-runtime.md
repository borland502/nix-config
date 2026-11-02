# Aliases hide real binaries

This repo's zsh config aliases `ls` → `eza` and `cat` → `bat` (see [home-manager/zsh.nix](../../../../home-manager/zsh.nix)). Both replacements are great for humans but break when a script depends on the exact output format of the original.

**Rule:** when you need exact, unstyled output, bypass the alias by calling the binary directly.

```bash
# Wrong: gets eza's columnar output, breaks downstream parsers
files=$(ls /var/log/*.log)

# Right: real BSD/GNU ls
files=$(/bin/ls /var/log/*.log)

# Wrong: gets bat's syntax highlighting + pager
config=$(cat /etc/hosts)

# Right: raw file contents
config=$(/bin/cat /etc/hosts)
```

The same applies to anything you alias — `command <name>` works as a generic escape hatch (`command ls /tmp`) when you don't want to hardcode `/bin/`.

## zsh `$status` is read-only

In zsh, `status` is a read-only special variable (it mirrors `$?` for the previous pipeline). Assigning to it crashes the script.

```zsh
# Crashes: "status: read-only variable"
status=0
some_command
status=$?

# Use a different name
rc=0
some_command
rc=$?

# Or use $? directly without re-storing
some_command
if [[ $? -ne 0 ]]; then ...; fi
```

**Names to avoid as zsh variables:** `status`, `path`, `cdpath`, `fpath`, `manpath` — these are linked to special arrays/integers. `rc`, `exit_code`, `result` are safe.

Related quoting trap: never emit a bare `==` or `===` as standalone shell text — zsh treats it as a glob/comparison operator and can error or mis-expand. Quote those strings (`"=="`) when they are literal data.
