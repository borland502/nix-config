from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path
from threading import Event

import pymupdf

from htmlpdf import cli
from htmlpdf.cli import (
    audit,
    is_web_font_family,
    mermaid_script_tag,
    preview_directory_lock,
    print_css,
    save_pdf_atomically,
    save_previews_atomically,
    stage_html,
)


def test_web_font_instances_match_loaded_family_prefix() -> None:
    assert is_web_font_family("Public Sans Thin", ["Public Sans"])
    assert is_web_font_family("IBM Plex Mono Medium", ["IBM Plex Mono"])
    assert not is_web_font_family("Helvetica", ["Public Sans", "IBM Plex Mono"])


def test_print_css_caps_only_reoriented_mermaid_diagrams() -> None:
    css = print_css("#1A5FB4")
    assert ".mermaid[data-htmlpdf-reoriented] svg" in css
    assert "max-height: 6.5in" in css


def test_mermaid_script_tag_uses_bundled_runtime_unless_overridden() -> None:
    with mermaid_script_tag(None) as bundled:
        assert set(bundled) == {"path"}
        asset = Path(bundled["path"])
        assert asset.name == "mermaid-11.4.1.min.js"
        assert asset.is_file()
        assert "mermaid" in asset.read_text(encoding="utf-8")[:1000].casefold()

    with mermaid_script_tag("https://example.test/mermaid.js") as overridden:
        assert overridden == {"url": "https://example.test/mermaid.js"}


def test_markdown_document_embeds_offline_font_faces_by_default(tmp_path) -> None:
    source = tmp_path / "guide.md"
    source.write_text("# Guide\n\nReadable **Markdown**.", encoding="utf-8")

    document = cli.markdown_to_document(source)

    assert "https://fonts.googleapis.com" not in document
    assert "https://fonts.gstatic.com" not in document
    assert "@font-face" in document
    assert "url(data:font/woff2;base64," in document


def test_stage_html_uses_a_unique_file_and_cleanup_is_scoped_to_it(tmp_path) -> None:
    source = tmp_path / "guide.md"
    source.write_text("# Guide", encoding="utf-8")

    first = stage_html(source, "<p>first invocation</p>")
    second = stage_html(source, "<p>second invocation</p>")

    assert first != second
    assert first.parent == source.parent
    assert first.read_text(encoding="utf-8") == "<p>first invocation</p>"
    assert second.read_text(encoding="utf-8") == "<p>second invocation</p>"

    first.unlink()
    assert not first.exists()
    assert second.exists()


def test_save_pdf_atomically_replaces_an_existing_destination(tmp_path) -> None:
    output = tmp_path / "guide.pdf"
    output.write_bytes(b"previous output")
    document = pymupdf.open()
    document.new_page()

    save_pdf_atomically(document, output)
    document.close()

    saved = pymupdf.open(output)
    assert saved.page_count == 1
    saved.close()
    assert list(tmp_path.glob(".guide.htmlpdf-*.pdf")) == []


def test_save_previews_atomically_replaces_directory_and_removes_stale_pages(tmp_path) -> None:
    pdf = tmp_path / "guide.pdf"
    document = pymupdf.open()
    document.new_page()
    document.new_page()
    document.save(pdf)
    document.close()

    preview = tmp_path / "guide-preview"
    preview.mkdir()
    (preview / "page-99.png").write_bytes(b"stale preview")

    first = pymupdf.open(pdf)
    save_previews_atomically(first, pdf, [1, 2], 72)
    first.close()
    second = pymupdf.open(pdf)
    save_previews_atomically(second, pdf, [1], 72)
    second.close()

    assert preview.is_symlink()
    assert (preview / "page-01.png").is_file()
    assert not (preview / "page-02.png").exists()
    assert not (preview / "page-99.png").exists()


def write_solid_pdf(path, color: tuple[float, float, float]) -> None:
    document = pymupdf.open()
    page = document.new_page()
    page.draw_rect(page.rect, color=color, fill=color, overlay=False)
    document.save(path)
    document.close()


def write_pdf_with_pages(path, count: int) -> None:
    document = pymupdf.open()
    for _ in range(count):
        document.new_page()
    save_pdf_atomically(document, path)
    document.close()


def test_save_previews_atomically_renders_current_pdf_after_waiting_for_output_lock(tmp_path, monkeypatch) -> None:
    pdf = tmp_path / "guide.pdf"
    write_solid_pdf(pdf, (1, 0, 0))
    previous_document = pymupdf.open(pdf)
    preview = tmp_path / "guide-preview"
    lock_attempted = Event()
    original_lock = preview_directory_lock

    @contextmanager
    def observed_lock(out_dir):
        lock_attempted.set()
        with original_lock(out_dir):
            yield

    monkeypatch.setattr(cli, "preview_directory_lock", observed_lock)
    with ThreadPoolExecutor(max_workers=1) as executor:
        with original_lock(preview):
            future = executor.submit(save_previews_atomically, previous_document, pdf, [1], 72)
            assert lock_attempted.wait(timeout=2)
            write_solid_pdf(pdf, (0, 1, 0))
        future.result(timeout=2)
    previous_document.close()

    rendered = pymupdf.Pixmap(preview / "page-01.png")
    assert rendered.samples[:3] == bytes((0, 255, 0))


def test_inspect_locks_pdf_before_auditing_to_avoid_stale_page_selection(tmp_path, monkeypatch) -> None:
    pdf = tmp_path / "guide.pdf"
    write_pdf_with_pages(pdf, 2)
    preview = tmp_path / "guide-preview"
    opened_for_audit = Event()
    original_open = pymupdf.open

    def observed_open(filename=None, *args, **kwargs):
        if filename == pdf:
            opened_for_audit.set()
        return original_open(filename, *args, **kwargs)

    monkeypatch.setattr(cli.pymupdf, "open", observed_open)
    args = type("InspectArgs", (), {"pdf": str(pdf), "preview": "2", "dpi": 72})()
    with ThreadPoolExecutor(max_workers=1) as executor:
        with preview_directory_lock(preview):
            future = executor.submit(cli.inspect, args)
            assert not opened_for_audit.wait(timeout=0.2)
            write_pdf_with_pages(pdf, 1)
        future.result(timeout=2)

    assert not (preview / "page-02.png").exists()


def test_audit_limits_link_contrast_claim_to_white_backgrounds(tmp_path, capsys) -> None:
    pdf = tmp_path / "guide.pdf"
    document = pymupdf.open()
    page = document.new_page()
    rect = pymupdf.Rect(72, 72, 160, 90)
    page.insert_text((72, 84), "Example link", color=(0.1, 0.37, 0.71))
    page.insert_link({"kind": pymupdf.LINK_URI, "from": rect, "uri": "https://example.com"})
    document.save(pdf)
    document.close()

    audit(pdf, "none", 72)

    report = capsys.readouterr().out
    assert "link text colors (contrast against white only):" in report
    assert "on white" in report
