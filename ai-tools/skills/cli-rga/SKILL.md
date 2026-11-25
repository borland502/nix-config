---
name: cli-rga
description: Use when searching extracted text inside PDFs, DOCX, ebooks, archives, or other supported binary formats with rga (ripgrep-all), and when choosing rg versus rga or ast-grep.
---

# Search documents and archives with rga

The package is `ripgrep-all`; the command is `rga`. Honor an explicitly requested
tool.

## Choose a search tool

```text
What are you searching?
|-- File/directory names -> fd
|-- Plain text or source code with literal/regex matching -> rg
|-- Code syntax, including multiline patterns -> ast-grep
|-- Extracted text in documents or archive members -> rga
|-- Structured JSON/YAML fields -> jq / yq / dasel
`-- Timestamped log correlation or log SQL -> lnav
```

Use `rg` as the default for ordinary repository search. Choose
[ast-grep](../cli-ast-grep/SKILL.md) for syntax, [dasel](../cli-dasel/SKILL.md) for
cross-format fields, or [lnav](../cli-lnav/SKILL.md) for log timelines.

## Search a bounded directory

```sh
rga --rga-list-adapters
rga -l -F 'release checklist' ./documents
rga -n -F 'release checklist' ./documents
```

`-l` limits output to matching files; `-F` treats the pattern literally.
Extraction produces a text representation: reported line positions are not
original source offsets. Check the adapter's supported extensions before
assuming a format works. Scanned image PDFs need OCR separately; `--rga-accurate`
uses file-type detection and is not OCR.

rga forwards search options to ripgrep but adds defaults including smart-case;
set `-s` or `-i` when case behavior must be explicit. It respects ignore rules.
An empty result is not proof that ignored files or unsupported formats were
searched. Check stderr: preprocessing errors can coexist with partial matches.

## Cache behavior on the pinned version

Extracted content is cached. Use `--rga-cache-path=DIR` for a dedicated cache;
for sensitive inputs, create a private disposable directory and remove it after
the search. This still writes extracted data to disk.

On the tested 0.10.10 build, `--rga-no-cache` fails document/archive adapters with
`No cache?`. Use a dedicated cache, or direct extraction piped into `rg` when
on-disk caching is inappropriate. Recheck this behavior after upgrades.
The upstream [related report](https://github.com/phiresky/ripgrep-all/issues/343)
describes the same failure on 0.10.9.

[Upstream](https://github.com/phiresky/ripgrep-all)
