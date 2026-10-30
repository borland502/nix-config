"""Quality reports and review artifacts for one locked PDF snapshot."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
import time
from pathlib import Path

import pymupdf

from htmlpdf.quality import audit_document


def write_json(output: Path, value: dict) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    handle, name = tempfile.mkstemp(prefix=f'.{output.name}-', dir=output.parent)
    try:
        with os.fdopen(handle, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.write('\n')
        os.replace(name, output)
    finally:
        Path(name).unlink(missing_ok=True)


def finish_report(pdf_path, args, *, source_issues=None, expected_links=None, timings=None, started=None):
    # The caller holds the PDF's existing output/preview lock across this function.
    from htmlpdf.cli import parse_pages, save_previews_atomically

    timings = dict(timings or {})
    quality_start = time.perf_counter()
    with pymupdf.open(pdf_path) as doc:
        report = audit_document(doc, expected_pages=getattr(args, 'expected_pages', None),
                                source_issues=source_issues, expected_links=expected_links)
        report['page_count'] = doc.page_count
        report['pdf_sha256'] = hashlib.sha256(pdf_path.read_bytes()).hexdigest()
        report['pdf'] = str(pdf_path)
        timings['quality_seconds'] = round(time.perf_counter() - quality_start, 4)
        preview = args.preview
        review_requested = getattr(args, 'contact_sheet', False) or preview in {'auto', 'changed'} or getattr(args, 'compare_to', None)
        review_start = time.perf_counter()
        if review_requested:
            from htmlpdf.review import build_review

            out_dir = pdf_path.with_name(f'{pdf_path.stem}-preview')
            baseline = Path(args.compare_to).expanduser() if getattr(args, 'compare_to', None) else out_dir / 'manifest.json'
            previous = json.loads(baseline.read_text()) if baseline.exists() else None
            if getattr(args, 'compare_to', None) and previous is None:
                raise ValueError(f'comparison manifest does not exist: {baseline}')
            flagged = sorted({issue['page'] for issue in report['issues'] if issue.get('page')})
            with tempfile.TemporaryDirectory(prefix='.htmlpdf-review-', dir=pdf_path.parent) as staging:
                staging_path = Path(staging)
                review = build_review(doc, staging_path, previous_manifest=previous, flagged_pages=flagged, dpi=72)
                review['pdf_sha256'] = report['pdf_sha256']
                write_json(staging_path / 'manifest.json', review)
                if preview == 'auto':
                    pages = sorted(set(review['changed_pages']) | set(flagged) | {1, doc.page_count})
                elif preview == 'changed':
                    pages = sorted(set(review['changed_pages']) | set(flagged))
                else:
                    pages = parse_pages(preview, doc.page_count)

                def copy_review(_doc, destination):
                    for name in ('contact-sheet.png', 'manifest.json'):
                        shutil.copy2(staging_path / name, destination / name)

                save_previews_atomically(doc, pdf_path, pages, args.dpi, lock_held=True, extras=copy_review)
                report['review'] = review
                report['review']['directory'] = str(out_dir)
                print(f'  contact sheet: {out_dir / "contact-sheet.png"}')
                print(f'  changed pages: {review["changed_pages"]}; flagged pages: {flagged}')
        else:
            pages = parse_pages(preview, doc.page_count)
            if pages:
                save_previews_atomically(doc, pdf_path, pages, args.dpi, lock_held=True)
        timings['review_seconds'] = round(time.perf_counter() - review_start, 4)
    timings['total_seconds'] = round(time.perf_counter() - (started or quality_start), 4)
    report['timings'] = timings
    for issue in report['issues']:
        location = f'p{issue["page"]}' if issue.get('page') else 'document'
        print(f'  {issue["severity"].upper()} {issue["code"]} {location}: {issue["message"]}')
    print(f'  quality: {report["summary"]["errors"]} errors, {report["summary"]["warnings"]} warnings')
    print('  timings: ' + ', '.join(f'{key.removesuffix("_seconds")} {value:.2f}s' for key, value in timings.items()))
    if getattr(args, 'report_json', None):
        write_json(Path(args.report_json).expanduser().resolve(), report)
    return report
