---
name: cli-dust
description: Use when identifying large files or directories with a quick dust disk-usage summary, or choosing between dust, ncdu, df, and Nix closure tools.
---

# Summarize disk usage with dust

dust gives a readable size-ranked directory tree without an interactive UI.
Honor an explicitly requested tool.

## Choose a tool

```text
What disk question are you answering?
|-- Which directories/files are largest? -> dust
|-- Interactive drill-down -> ncdu
|-- How much space is free on the filesystem? -> df
|-- Why is a Nix dependency retained? -> nix-tree
`-- Which packages changed between Nix closures? -> dix
```

## Bound the scan

```sh
dust -d 2 .
dust -d 2 -c -b -P ./logs
```

`-d` limits displayed depth, not traversal work. Choose a narrow starting
directory; `-x` keeps counting on its filesystem. The second example disables
color, percentage bars, and progress output for a cleaner agent capture.

Default sizes describe disk allocation; `-s` switches to apparent file lengths.
Sparse files, compression, hardlinks, and filesystem accounting can make these
differ from both `df` and reclaimable space. Read errors mean a total may be
incomplete; `--print-errors` identifies affected paths.

A large directory is evidence for investigation, not automatic deletion.
For the Nix store, inspect roots and closures before choosing a cleanup action;
a byte total alone does not explain retention.

[Upstream](https://github.com/bootandy/dust)
