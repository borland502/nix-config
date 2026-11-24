#!/usr/bin/env -S zsh -f
# Compatibility entry point; all destinations share one manifest and renderer.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
exec python3 "$repo_root/scripts/render-agent-instructions.py" check "$repo_root"
