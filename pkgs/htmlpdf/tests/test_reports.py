import json
import os
import subprocess
import sys
from pathlib import Path

import pymupdf
import pytest

from htmlpdf.cli import find_chrome


def invoke(*args):
    return subprocess.run([sys.executable, '-m', 'htmlpdf', *map(str, args)], text=True, capture_output=True, check=False)


def test_template_creates_editable_report_without_overwriting(tmp_path):
    source = tmp_path / 'report.html'
    result = invoke('template', 'report', '-o', source)
    assert result.returncode == 0, result.stderr
    document = source.read_text()
    assert '<table' in document and '<section' in document and 'href="#' in document
    source.write_text('User changes')
    again = invoke('template', 'report', '-o', source)
    assert again.returncode != 0
    assert source.read_text() == 'User changes'


@pytest.mark.skipif(os.environ.get('HTMLPDF_BROWSER_TESTS') != '1', reason='set HTMLPDF_BROWSER_TESTS=1 for host Chrome integration')
def test_report_quality_and_visual_review_pipeline(tmp_path):
    source = tmp_path / 'report.html'
    created = invoke('template', 'report', '-o', source)
    assert created.returncode == 0, created.stderr
    output = tmp_path / 'report.pdf'
    report_path = tmp_path / 'audit.json'
    converted = invoke('convert', source, '-o', output, '--profile', 'report', '--strict', '--expected-pages', '2',
                       '--report-json', report_path, '--contact-sheet', '--preview', 'all', '--chrome', find_chrome(None))
    assert converted.returncode == 0, converted.stdout + converted.stderr
    report = json.loads(report_path.read_text())
    assert report['summary']['errors'] == 0
    assert report['page_count'] == 2
    assert report['summary']['internal_links'] >= 1
    assert report['timings']['total_seconds'] > 0
    assert report['pdf_sha256']
    with pymupdf.open(output) as doc:
        assert doc[0].rect == pymupdf.Rect(0, 0, 792, 612)
        assert len(doc.get_toc()) >= 2
    previews = output.with_name('report-preview')
    assert (previews / 'contact-sheet.png').is_file()
    baseline = tmp_path / 'baseline.json'
    baseline.write_bytes((previews / 'manifest.json').read_bytes())
    repeated = invoke('inspect', output, '--report-json', report_path, '--contact-sheet', '--preview', 'changed', '--compare-to', baseline)
    assert repeated.returncode == 0, repeated.stdout + repeated.stderr
    assert json.loads(report_path.read_text())['review']['changed_pages'] == []
    assert not list(previews.glob('page-*.png'))
    # A broken HTML anchor is fatal in strict mode, but still provides review artifacts.
    source.write_text(source.read_text().replace('href="#source-1"', 'href="#missing-source"'))
    broken = invoke('convert', source, '-o', output, '--profile', 'report', '--strict', '--report-json', report_path, '--chrome', find_chrome(None))
    assert broken.returncode == 2, broken.stdout + broken.stderr
    assert any(issue['code'] == 'missing_anchor' for issue in json.loads(report_path.read_text())['issues'])


def test_inspect_strict_page_count_writes_diagnostics(tmp_path):
    output = tmp_path / 'one.pdf'
    with pymupdf.open() as doc:
        page = doc.new_page()
        page.insert_text((72, 72), 'One page')
        doc.save(output)
    report_path = tmp_path / 'audit.json'
    result = invoke('inspect', output, '--strict', '--expected-pages', '2', '--report-json', report_path, '--preview', 'none')
    assert result.returncode == 2
    assert report_path.is_file(), result.stderr
    assert json.loads(report_path.read_text())['summary']['errors'] >= 1


@pytest.mark.skipif(os.environ.get('HTMLPDF_BROWSER_TESTS') != '1', reason='host Chrome integration')
def test_long_table_keeps_rows_headers_and_links(tmp_path):
    source = Path(__file__).parent / 'fixtures/long-report.html'
    output = tmp_path / 'long.pdf'
    audit = tmp_path / 'long.json'
    result = invoke('convert', source, '-o', output, '--profile', 'report', '--strict', '--preview', 'none', '--report-json', audit)
    assert result.returncode == 0, result.stdout + result.stderr
    with pymupdf.open(output) as doc:
        assert len(doc) >= 3
        all_text = ''.join(page.get_text() for page in doc)
        for number in range(1, 45):
            assert all_text.count(f'ROW-{number:03d}') == 1
        for page in doc:
            if 'ROW-' in page.get_text():
                assert 'Record key' in page.get_text()
    assert json.loads(audit.read_text())['summary']['internal_links'] == 44


@pytest.mark.skipif(os.environ.get('HTMLPDF_BROWSER_TESTS') != '1', reason='host Chrome integration')
def test_print_font_readiness_obeys_timeout(tmp_path):
    source = tmp_path / 'pending-font.html'
    source.write_text('''<html><body><p>Pending print font</p><script>
Object.defineProperty(document.fonts, 'ready', {get() {
  return matchMedia('print').matches ? new Promise(() => {}) : Promise.resolve();
}});
</script></body></html>''')
    result = subprocess.run([sys.executable, '-m', 'htmlpdf', 'convert', str(source),
                             '--profile', 'report', '--timeout', '1', '--preview', 'none'],
                            capture_output=True, text=True, check=False, timeout=6)
    assert result.returncode != 0
    assert 'Timed out waiting' in result.stderr


@pytest.mark.skipif(os.environ.get('HTMLPDF_BROWSER_TESTS') != '1', reason='host Chrome integration')
def test_default_profile_retains_existing_footer_size(tmp_path):
    source = tmp_path / 'plain.html'
    source.write_text('<html><head><title>Legacy footer</title></head><body>Body content</body></html>')
    output = source.with_suffix('.pdf')
    result = invoke('convert', source, '--preview', 'none')
    assert result.returncode == 0, result.stderr
    with pymupdf.open(output) as doc:
        footer_sizes = [span['size'] for span in doc[0].get_texttrace() if span['bbox'][1] > 700]
    assert footer_sizes and max(footer_sizes) < 6


@pytest.mark.parametrize('command', ['convert', 'inspect'])
@pytest.mark.parametrize('destination', ['manifest.json', 'contact-sheet.png', 'page-01.png', 'baseline.json', 'preview-directory'])
def test_report_path_cannot_overwrite_review_artifacts(tmp_path, command, destination):
    source = tmp_path / 'report.html'
    source.write_text('<p>Source must remain intact</p>')
    output = tmp_path / 'report.pdf'
    with pymupdf.open() as doc:
        doc.new_page().insert_text((72, 72), 'Existing PDF')
        doc.save(output)
    previews = tmp_path / 'report-preview'
    previews.mkdir()
    protected = [source, output]
    for name in ('manifest.json', 'contact-sheet.png', 'page-01.png'):
        artifact = previews / name
        artifact.write_bytes(b'Existing review artifact')
        protected.append(artifact)
    baseline = tmp_path / 'baseline.json'
    baseline.write_text(json.dumps({'schema_version': 1, 'dpi': 72, 'page_count': 0, 'pages': []}))
    protected.append(baseline)
    before = {path: path.read_bytes() for path in protected}
    report = baseline if destination == 'baseline.json' else previews if destination == 'preview-directory' else previews / destination
    args = ['convert', source, '-o', output] if command == 'convert' else ['inspect', output]
    result = invoke(*args, '--report-json', report, '--compare-to', baseline, '--contact-sheet')
    assert result.returncode == 2, result.stdout + result.stderr
    assert 'report-json' in result.stderr
    assert {path: path.read_bytes() for path in protected} == before
