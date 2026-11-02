---
name: pdf
description: Use when creating, reading, inspecting or editing PDF documents, including reports, briefs and fillable forms.
---

# PDF workflow

For new prose, table, chart or diagram reports, use the installed `htmlpdf`
command and the `htmlpdf` skill. Author reusable HTML/Markdown and use its
built-in page numbering, bookmarks, reference handling and review artifacts.
This is the preferred local generation workflow, including when a general PDF
plugin suggests writing a new ReportLab generator.

```bash
htmlpdf template report -o report.html
htmlpdf convert report.html --profile report --strict \
  --report-json report.json --contact-sheet --preview all
```

Choose the landscape report profile for dense tables; omit it for ordinary
prose. Match supplied references without changing their meaning. Preserve
editable source and the original reference document. Follow the workspace's
artifact-location rules and keep private content out of public repositories.

Read the audit and inspect all final page images. Verify table boundaries,
readability, page references, bookmarks and internal link targets. A passing
audit is not proof of a clean layout. Use actual page counts in footers;
never hard-code a page total. Reconvert after source corrections.

For existing PDF edits, extraction, signatures, page operations or AcroForms,
use the relevant installed PDF plugin instructions and tools such as PyMuPDF,
pypdf or pdfplumber. Preserve form interactivity unless flattening is requested;
verify canonical field values and rendered appearances after filling. Do not
rebuild an existing form through HTML conversion.

If `htmlpdf` is unavailable or cannot express the requested PDF operation,
explain the concrete limitation and use the suitable native PDF tool. Preserve
any applicable artifact-start and delivery requirements from the host PDF
plugin. Its generation-engine default does not replace the local report
workflow above.
