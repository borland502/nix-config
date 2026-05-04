#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$repo_root/chezmoi/dot_config/instructions/agent-defaults.md"
mirror_file="$repo_root/.github/copilot-instructions.md"
tmp_dir=$(mktemp -d)

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT

normalize() {
  awk '
    BEGIN {
      in_frontmatter = 0
      at_start = 1
      heading_skipped = 0
      emitted_content = 0
      pending_blank = 0
    }

    at_start && $0 == "---" {
      in_frontmatter = 1
      at_start = 0
      next
    }

    in_frontmatter {
      if ($0 == "---") {
        in_frontmatter = 0
      }
      next
    }

    {
      at_start = 0

      if (!heading_skipped && ($0 == "# Persistent Terminal Defaults" || $0 == "# Copilot Defaults")) {
        heading_skipped = 1
        next
      }

      line = $0
      gsub(/`/, "", line)

      if (line == "") {
        if (!emitted_content || pending_blank) {
          next
        }
        pending_blank = 1
        next
      }

      if (pending_blank) {
        print ""
        pending_blank = 0
      }

      print line
      emitted_content = 1
    }
  ' "$1"
}

substituted_source="$tmp_dir/agent-defaults.copilot.md"
sed 's|@@AGENT@@|copilot|g' "$source_file" > "$substituted_source"

normalized_source="$tmp_dir/copilot-defaults.normalized.md"
normalized_mirror="$tmp_dir/copilot-instructions.normalized.md"

normalize "$substituted_source" > "$normalized_source"
normalize "$mirror_file" > "$normalized_mirror"

if ! cmp -s "$normalized_source" "$normalized_mirror"; then
  printf '%s\n' 'Normalized Copilot instruction content diverged:'
  diff -u \
    -L 'chezmoi/dot_config/instructions/agent-defaults.md (normalized, copilot variant)' "$normalized_source" \
    -L '.github/copilot-instructions.md (normalized)' "$normalized_mirror" || true
  exit 1
fi
