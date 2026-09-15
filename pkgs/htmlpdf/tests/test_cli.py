from htmlpdf.cli import is_web_font_family, print_css


def test_web_font_instances_match_loaded_family_prefix() -> None:
    assert is_web_font_family("Public Sans Thin", ["Public Sans"])
    assert is_web_font_family("IBM Plex Mono Medium", ["IBM Plex Mono"])
    assert not is_web_font_family("Helvetica", ["Public Sans", "IBM Plex Mono"])


def test_print_css_caps_only_reoriented_mermaid_diagrams() -> None:
    css = print_css("#1A5FB4")
    assert ".mermaid[data-htmlpdf-reoriented] svg" in css
    assert "max-height: 6.5in" in css
