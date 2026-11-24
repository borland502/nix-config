#!/usr/bin/env -S zsh -f
# Compatibility entry point for committed instruction generation.
emulate -R zsh
setopt err_exit no_unset pipe_fail

script_dir=${0:A:h}
exec python3 "$script_dir/render-agent-instructions.py" write "${1:?usage: render-agent-instructions.sh <output-root>}"
