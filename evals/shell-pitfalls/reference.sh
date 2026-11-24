#!/bin/sh
set -e
cat >copy-text.zsh <<'SCRIPT'
for file in "$1"/*.txt(N); do
  [[ -f "$file" && ! -L "$file" ]] || continue
  cp -- "$file" "$2/"
done
SCRIPT
