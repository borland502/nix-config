"""Reusable report defaults and a small, editable starting document."""
from pathlib import Path

REPORT_MARGIN = "39pt,40pt,34pt,40pt"
REPORT_LINK_COLOR = "#176A72"


def write_template(output: Path) -> None:
    # Exclusive creation protects authored content on repeat invocations.
    document = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Service report</title></head>
<body><main class="report">
<section class="report-section">
<p class="report-label">SERVICE REPORT / REVIEW DRAFT</p>
<h1 id="overview">Service report</h1>
<p class="report-subtitle">Prepared for review</p>
<p>This report brings together the requested outputs, their uses, and the decisions needed for delivery.</p>
<div class="report-callout">Reuse shared data selections while preserving each report's audience, period, and output format.</div>
<h2>Report inventory</h2>
<table><colgroup><col style="width:20%"><col style="width:20%"><col style="width:45%"><col style="width:15%"></colgroup>
<thead><tr><th>Audience</th><th>Frequency</th><th>Requested output</th><th>Evidence</th></tr></thead>
<tbody><tr><td>Operations</td><td>Monthly</td><td>Volumes, status, and exceptions by service.</td><td><a href="#source-1">[S1]</a></td></tr>
<tr><td>Planning</td><td>Quarterly</td><td>Trends and capacity summaries with the reporting period recorded.</td><td><a href="#source-1">[S1]</a></td></tr></tbody></table>
<h2>Review decisions</h2><p>Confirm the initial reports, reference outputs, and reviewers. Record the filters and extraction time with each delivered file.</p>
</section>
<section class="report-section">
<p class="report-label">SERVICE REPORT / EVIDENCE</p>
<h1 id="references">References and evidence notes</h1>
<p class="report-subtitle">Keep source labels stable as the report changes.</p>
<div class="report-references"><p id="source-1"><b>S1 Service requirements</b><br><a href="https://example.com/requirements">Example requirements</a>. Replace this entry with the authoritative source for the report.</p></div>
<p class="report-small">Method: describe the source selection, date of review, and limits of the evidence.</p>
</section></main></body></html>
'''
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x', encoding='utf-8') as stream:
        stream.write(document)
