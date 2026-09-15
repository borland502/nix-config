import pymupdf

from htmlpdf.cli import is_web_font_family, print_css, save_pdf_atomically, stage_html


def test_web_font_instances_match_loaded_family_prefix() -> None:
    assert is_web_font_family("Public Sans Thin", ["Public Sans"])
    assert is_web_font_family("IBM Plex Mono Medium", ["IBM Plex Mono"])
    assert not is_web_font_family("Helvetica", ["Public Sans", "IBM Plex Mono"])


def test_print_css_caps_only_reoriented_mermaid_diagrams() -> None:
    css = print_css("#1A5FB4")
    assert ".mermaid[data-htmlpdf-reoriented] svg" in css
    assert "max-height: 6.5in" in css


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
