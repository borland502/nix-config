---
name: htmlpdf
description: Use when creating PDF reports, briefs, notes, dashboards, tables or charts, or converting HTML/Markdown to print-ready PDFs. Also use for PDF layout and navigation checks. Excludes filling forms and editing existing PDF objects.
---

# HTMLPDF

Use the installed `htmlpdf` for new report PDFs. Author content in HTML or
Markdown; reuse its templates, fonts, pagination, bookmarks and checks.

```bash
htmlpdf template report -o report.html
htmlpdf convert report.html --profile report --strict \
  --report-json report.json --contact-sheet --preview all
htmlpdf inspect report.pdf --strict --contact-sheet --preview all
```

Use the landscape `report` profile for table-heavy reports. Ordinary prose can
use the default profile. When matching an existing document, preserve its
content and visual hierarchy; compare the rendered pages, links and text.
Use `--expected-pages` only when a page-count requirement exists.

Inspect the JSON issues and all final pages. Strict errors require correction;
small-text and sparse-page warnings require judgment. Confirm bookmarks and
reference links reach the intended sections. Checks do not replace visual
review or verify external URLs. Fix the source and reconvert; avoid patching
only the final PDF or shrinking text to force a page count.

For revisions, `--preview auto` selects changed/flagged pages plus first/last;
`--preview changed --compare-to previous-manifest.json` compares a saved review
manifest. Contact sheets and pixel hashes live in the PDF's preview directory.
Still inspect every page before final delivery. Follow workspace conventions
for artifact locations; keep private report content out of public repositories.

Mermaid and Markdown fonts are bundled for offline use. Prefer explicit table
columns, `.report-compact` for dense tables, `.report-section` for intentional
page starts, and `.report-references` for source columns. Give anchors unique
IDs and distinctive heading or bold reference labels. Native footers handle
page totals; authored page references must be checked after pagination.

Run `htmlpdf convert --help` or `inspect --help` for paper, margins, waits,
bookmarks and previews. If the installed version lacks an option, inspect its
help and use the supported workflow or update it; do not invent flags.
