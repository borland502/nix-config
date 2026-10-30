import pymupdf

from htmlpdf.navigation import repair_named_links


def named_document(heading="S1 Example heading", duplicate=False):
    doc = pymupdf.open()
    doc.new_page(width=300, height=300)
    doc.new_page(width=300, height=300)
    doc[0].insert_text((30, 40), "Details", fontsize=12)
    doc[1].insert_text((39, 120), heading, fontsize=12)
    if duplicate:
        doc[1].insert_text((39, 200), heading, fontsize=12)
    doc[0].insert_link({"kind": pymupdf.LINK_GOTO,
                        "from": pymupdf.Rect(29, 25, 80, 44), "page": 1,
                        "to": pymupdf.Point(39, 70)})
    doc = pymupdf.open(stream=doc.tobytes(), filetype="pdf")
    doc.xref_set_key(doc[0].get_links()[0]["xref"], "A/D", "/source-1")
    doc.xref_set_key(doc.pdf_catalog(), "Names",
                     f"<< /Dests << /Names [(source-1) [{doc.page_xref(1)} 0 R /XYZ 39 230 0]] >> >>")
    return pymupdf.open(stream=doc.tobytes(), filetype="pdf")


def expected(text="S1 Example heading", target_id="source-1"):
    return [{"text": "Details", "target_text": text, "target_id": target_id}]


def test_repairs_named_link_using_heading_geometry_and_survives_save():
    with named_document() as doc:
        original = doc[0].get_links()[0]
        result = repair_named_links(doc, expected())
        assert result == {"repaired": 1, "issues": []}
        link = doc[0].get_links()[0]
        heading = doc[1].search_for("S1 Example heading")[0]
        assert link["kind"] == pymupdf.LINK_GOTO
        assert link["xref"] == original["xref"]
        assert link["from"] == original["from"]
        assert link["page"] == 1
        assert abs(link["to"].x - heading.x0) < 0.01
        assert abs(link["to"].y - (heading.y0 - 2)) < 0.01
        with pymupdf.open(stream=doc.tobytes(), filetype="pdf") as reopened:
            assert reopened[0].get_links()[0]["to"] == link["to"]


def test_unknown_native_destination_is_unchanged():
    with named_document() as doc:
        original = doc[0].get_links()[0]
        result = repair_named_links(doc, expected(target_id="another-id"))
        assert result["repaired"] == 0
        assert doc[0].get_links() == [original]


def test_missing_heading_is_advisory_and_keeps_original_destination():
    with named_document() as doc:
        original = doc[0].get_links()[0]
        result = repair_named_links(doc, expected("Absent heading"))
        assert result["repaired"] == 0
        assert result["issues"] and result["issues"][0]["severity"] == "warning"
        assert doc[0].get_links() == [original]


def test_duplicate_heading_is_advisory_and_keeps_original_destination():
    with named_document(duplicate=True) as doc:
        original = doc[0].get_links()[0]
        result = repair_named_links(doc, expected())
        assert result["repaired"] == 0
        assert result["issues"] and result["issues"][0]["severity"] == "warning"
        assert doc[0].get_links() == [original]


def test_source_labels_do_not_override_native_destination_identity():
    with named_document() as doc:
        result = repair_named_links(doc, expected() + expected("Other heading", "source-2"))
        assert result["repaired"] == 1
        assert not result["issues"]


def test_similar_numbered_heading_is_not_a_match():
    with named_document(heading="S10 Example heading") as doc:
        result = repair_named_links(doc, expected("S1"))
        assert result["repaired"] == 0
        assert result["issues"]


def test_multiline_heading_is_one_occurrence():
    with named_document(heading="S1 Example\nheading") as doc:
        result = repair_named_links(doc, expected())
        assert result["repaired"] == 1
        assert not result["issues"]
