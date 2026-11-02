---
name: markdown
description: Use when drafting or editing Markdown for people to read, including explanations, reports, READMEs, guides, release notes, and handoffs. Also use when reviewing Markdown readability or renderer compatibility. Excludes machine-only payloads and verbatim source reproduction.
---

# Markdown for readers

Make the rendered document and its source easy to read. Preserve the user's
facts, uncertainty, audience, requested format, and existing document conventions.
Apply this guidance within the task; it does not authorize saving or publishing.

## Choose the dialect

- Use [CommonMark](https://spec.commonmark.org/) as the syntax baseline.
  When the destination is unknown, prefer portable paragraphs, headings, lists,
  explicit links, and code fences without blocking on clarification.
- When the destination supports [GitHub Flavored Markdown](https://github.github.com/gfm/),
  use tables, task lists, and strikethrough where useful. These extend CommonMark.
- Verify renderer support for footnotes, heading IDs, alerts, math, Mermaid,
  and YAML frontmatter; they are not all part of the formal GFM specification.
  Use ordinary text, lists, or links when support is unknown. Check local
  renderer configuration before claiming compatibility.
- Use the [Markdown Guide](https://www.markdownguide.org/extended-syntax/)
  for practical examples; the specifications settle syntax questions.
  The conventions below are readability defaults, not universal syntax laws.

## Shape the document

Lead with the answer, finding, or purpose. Develop one idea per paragraph in
plain language. Separate established facts from assumptions and pending work.
Use descriptive headings when they help navigation; short replies can remain
plain prose. For standalone documents, use one title and a logical heading
hierarchy; preserve the hierarchy of an existing document or inserted section.

Use bullets for parallel items and numbered lists for ordered steps. Keep
nesting shallow. Use tables for compact comparisons with short cells; use
lists or subsections for long explanations. Emphasize only key terms or
decisions. Give links descriptive labels and images meaningful alt text.
Keep source links near the claims they support; preserve provided destinations.

## Keep the source predictable

- Prefer ATX headings (`## Heading`), consistent list markers, and blank lines
  around headings, lists, tables, and fenced blocks. Indent continuation blocks
  under their list item's content so their nesting survives rendering.
- Give fences a language when known. When showing literal fenced Markdown,
  use an outer fence longer than any matching fence inside it. Present the
  document directly; wrap it in a code block only for literal-source delivery.
- Escape literal pipes in GFM table cells, including inside code spans.
  Check header and row column counts. Avoid multiline table-cell layouts.
- Use inline code for identifiers and commands. Preserve copyable code and
  URLs exactly; avoid typographic quote substitution in executable examples.

## Check before delivery

Review heading order, list nesting, fence closure, link destinations, reference
definitions, table shape, and factual completeness. Use an existing Markdown
linter/configuration for repository files when available. Lint rules are local
style choices; do not add dependencies or reformat unrelated files for this skill.
For complex or renderer-specific content, inspect a preview when available;
state any unverified compatibility that matters to the user.

Markdown defines structure. Fonts, colors, page breaks, and PDF pagination
belong to the renderer or template; use the relevant artifact skill for those.
