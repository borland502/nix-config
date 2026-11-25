---
name: cli-ast-grep
description: Use when finding or rewriting code by syntax shape with ast-grep, especially multiline calls and patterns that regex would confuse with comments or strings.
---

# Search code structure with ast-grep

Use the `ast-grep` binary explicitly; the shorter `sg` name can conflict with
other system commands. Honor an explicitly requested tool.

## Choose a tool

```text
What do you need to match?
|-- File or directory names -> fd
|-- Literal/regex source text, comments, or strings -> rg
|-- Code syntax across whitespace and line breaks -> ast-grep
|-- Text extracted from PDF/DOCX/archives -> rga
|-- Intentional simple text replacement -> sd
`-- Symbol rename requiring scope/type knowledge -> language-server tooling
```

See [rga](../cli-rga/SKILL.md) for document extraction. ast-grep recognizes syntax;
it does not establish symbol identity or type equivalence.

## Search before rewriting

```sh
ast-grep run --lang ts --pattern 'console.log($$$ARGS)' src
ast-grep run --lang ts --pattern 'console.log($$$ARGS)' --json=compact src
ast-grep run --lang ts --pattern 'console.log($$$ARGS)' --rewrite 'logger.debug($$$ARGS)' src
```

The third command previews a rewrite without modifying files. It does not prove
the replacement is valid in that codebase; verify imports, scope, and semantics.

Single-quote patterns and replacements so the shell preserves `$`. `$ARG`
matches one syntax node; `$$$ARGS` captures zero or more nodes. Pick the actual
language (`ts` versus `tsx`, for example), and scope paths before broadening.

For a requested edit, inspect matches and preview first, then use
`--interactive` for selected edits or `--update-all` for the already reviewed
scope. Review the diff and run relevant checks. If the pattern misses a case,
inspect it with `--debug-query` rather than assuming an empty result proves
absence.

[Upstream](https://github.com/ast-grep/ast-grep)
