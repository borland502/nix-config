---
name: htmlpdf
description: Use when converting HTML or Markdown reports, notes, dashboards, tables, charts, or Mermaid diagrams to print-ready PDFs.
---

# HTMLPDF

Use the installed `htmlpdf` command to make and audit readable, bookmarked
PDFs. Use `convert` for `.html`, `.htm`, `.md`, or `.markdown`; use `inspect`
for an existing PDF.

## Workflow

```bash
htmlpdf convert report.html -o report.pdf --preview 1,5
htmlpdf convert notes.md -o notes.pdf --preview 1-3
htmlpdf inspect report.pdf --preview 1,5
```

Always request preview pages during conversion, then inspect the PDF and the
same requested preview pages before reporting success. Confirm that bookmarks
reach the intended sections, the intended fonts are embedded and rendered, and
links printed against white have contrast of at least 4.5:1. Visually assess
links over tinted backgrounds; the PDF audit cannot reliably associate text
with its painted background.

## Print CSS

Set a legible root font size and let prose use the printable width. Declare
dashboard and table grids explicitly instead of relying on automatic layout.
Use `.page-break` for intentional section boundaries and `.no-print` for
controls or navigation that must not appear in the PDF:

```css
html { font-size: 16px; }
article { width: 100%; max-width: none; }
.metrics { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; }
.page-break { break-before: page; }
@media print { .no-print { display: none !important; } }
```

Use `htmlpdf convert --help` and `htmlpdf inspect --help` to select paper,
orientation, bookmarks, waits, or preview pages. Re-convert after correcting
any clipping, unreadable content, missing bookmarks, font substitution, or
low-contrast links.
