import json

import pymupdf
import pytest

from htmlpdf.review import build_review


def make_document(count=2):
    doc = pymupdf.open()
    for number in range(count):
        page = doc.new_page(width=300, height=240)
        page.insert_text((20, 40), f"Page {number + 1}")
    return doc


def test_fresh_review_writes_manifest_and_visible_contact_sheet(tmp_path):
    with make_document() as doc:
        result = build_review(doc, tmp_path, flagged_pages=[2, 2])
    assert result["schema_version"] == 1
    assert result["page_count"] == 2
    assert result["changed_pages"] == [1, 2]
    assert result["removed_pages"] == []
    assert result["flagged_pages"] == [2]
    assert result["dpi"] == 72
    assert result["pages"][0]["width"] == 300
    assert result["pages"][0]["height"] == 240
    assert len(result["pages"][0]["sha256"]) == 64
    assert json.loads((tmp_path / "manifest.json").read_text()) == result
    sheet = pymupdf.Pixmap(str(tmp_path / "contact-sheet.png"))
    assert sheet.width >= 300 and sheet.height >= 240
    assert len(set(sheet.samples)) > 20
    assert sorted(p.name for p in tmp_path.iterdir()) == ["contact-sheet.png", "manifest.json"]


def test_identical_pixels_are_unchanged_and_vector_only_change_is_detected(tmp_path):
    with make_document() as doc:
        first = build_review(doc, tmp_path)
        second = build_review(doc, tmp_path, previous_manifest=first)
        assert second["changed_pages"] == []
        doc[1].draw_rect(pymupdf.Rect(30, 80, 90, 130), fill=(1, 0, 0))
        changed = build_review(doc, tmp_path, previous_manifest=first)
    assert changed["changed_pages"] == [2]
    assert changed["pages"][0]["sha256"] == first["pages"][0]["sha256"]
    assert changed["pages"][1]["sha256"] != first["pages"][1]["sha256"]


def test_added_and_removed_page_numbers(tmp_path):
    with make_document() as doc:
        first = build_review(doc, tmp_path)
        doc.new_page(width=300, height=240)
        added = build_review(doc, tmp_path, previous_manifest=first)
        assert added["changed_pages"] == [3]
        doc.delete_pages(1, 2)
        removed = build_review(doc, tmp_path, previous_manifest=added)
    assert removed["changed_pages"] == []
    assert removed["removed_pages"] == [2, 3]


def test_different_dpi_is_incompatible(tmp_path):
    with make_document() as doc:
        first = build_review(doc, tmp_path)
        with pytest.raises(ValueError, match="dpi"):
            build_review(doc, tmp_path, previous_manifest=first, dpi=144)


@pytest.mark.parametrize("previous", [
    {}, {"schema_version": 999}, {"schema_version": 1, "dpi": 72, "page_count": 1, "pages": []},
    {"schema_version": 1, "dpi": 72, "page_count": 1, "pages": [{"page": 2}]},
    {"schema_version": 1, "dpi": 72, "page_count": 1, "pages": [
        {"page": 1, "sha256": "not-a-hash", "width": 300, "height": 240}]},
    [],
])
def test_malformed_previous_manifest_has_clear_error(tmp_path, previous):
    with make_document() as doc, pytest.raises(ValueError, match="manifest"):
        build_review(doc, tmp_path, previous_manifest=previous)
    assert not (tmp_path / "manifest.json").exists()


@pytest.mark.parametrize("dpi, flags", [(0, []), (-1, []), (72, [0]), (72, [3])])
def test_invalid_render_inputs_are_rejected(tmp_path, dpi, flags):
    with make_document() as doc, pytest.raises(ValueError):
        build_review(doc, tmp_path, dpi=dpi, flagged_pages=flags)


@pytest.mark.parametrize("field, value", [("schema_version", True), ("dpi", 72.0)])
def test_manifest_rejects_noninteger_render_metadata(tmp_path, field, value):
    with make_document() as doc:
        first = build_review(doc, tmp_path)
        first[field] = value
        with pytest.raises(ValueError, match="manifest"):
            build_review(doc, tmp_path, previous_manifest=first)
