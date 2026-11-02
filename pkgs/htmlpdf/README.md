# htmlpdf

Convert HTML or Markdown to a bookmarked PDF with offline fonts and Mermaid,
print preparation, quality diagnostics, and visual review artifacts.

## Reports

```bash
htmlpdf template report -o report.html
htmlpdf convert report.html --profile report --strict \
  --report-json report.json --contact-sheet --preview all
```

The editable template uses a landscape Letter profile with navy headings,
teal links, compact tables, callouts and reference columns. Sections marked
`report-section` start on new pages. Use `report-compact` on dense tables and
`report-references` or `report-reference-columns` for source lists. Native
browser footers provide the actual page number and total. Explicit `--paper`,
`--no-landscape`, and `--margin` override profile defaults. The default profile
retains ordinary HTML/Markdown layout.

The converter aligns named internal links with uniquely located source target
headings in the PDF. It leaves ambiguous targets unchanged and reports them for
review. Keep target IDs unique and use distinctive headings or bold reference
labels. Printed page-number prose remains authored content; the tool does not
rewrite statements such as “see page 4.”

## Quality and visual review

```bash
htmlpdf inspect report.pdf --strict --expected-pages 8 \
  --report-json inspection.json --contact-sheet --preview auto
htmlpdf convert report.html --profile report --preview changed \
  --compare-to previous-manifest.json --report-json revision.json
```

`--strict` exits with status 2 for hard errors, while retaining the PDF and
review artifacts. Errors include missing source anchors, unresolved or invalid
internal destinations, proven target mismatches, text beyond page bounds,
missing images and an unexpected page count. Small text and sparse pages are
advisory warnings. Standalone inspection cannot infer the source's intended
anchors. Checks do not prove visual quality, all clipping/overlap, or external
URL reachability; inspect the rendered pages before delivery.

The JSON report includes page diagnostics, issue codes/severities, PDF SHA256
and phase timings. `--contact-sheet` publishes an overview and `manifest.json`
in the PDF's preview directory. `--preview auto` selects changed/flagged pages
plus first and last; `changed` selects changed/flagged pages. Other selections
include `all`, `none`, or `1,3-5`. Without `--compare-to`, the existing preview
manifest is used when present. Page comparisons use rendered RGB pixels at a
fixed 72 DPI and report removed pages; metadata-only changes do not count.
Comparisons require compatible manifest versions and DPI. Preserve a separate
manifest when comparing against a specific approved revision.

## Development

`task check` runs lint, types and tests in the Poetry environment. Browser tests
are opt-in because Nix package checks have no browser:

```bash
HTMLPDF_BROWSER_TESTS=1 poetry run pytest -q
```

They use host Chrome and a synthetic long report to verify repeated headers,
complete rows, reference navigation, strict failures and visual comparison.
`task nix:build` builds the standalone executable; `task smoke` exercises the
packaged Markdown and Mermaid fixtures with host Chrome.
