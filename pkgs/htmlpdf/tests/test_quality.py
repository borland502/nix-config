import pymupdf

from htmlpdf.quality import audit_document


def make_document():
    doc = pymupdf.open()
    doc.new_page(width=300, height=300)
    return doc


def codes(report):
    return {issue["code"] for issue in report["issues"]}


def test_reports_page_metrics_and_advisory_layout_warnings():
    with make_document() as doc:
        doc[0].insert_text((30, 40), "Small sample", fontsize=6)
        report = audit_document(doc)
    assert report.get("schema_version") == 1
    assert report["summary"]["errors"] == 0
    assert report["summary"]["warnings"] == 2
    assert codes(report) == {"sparse_page", "small_font"}
    assert report["pages"][0]["chars"] == len("Small sample")
    assert report["pages"][0]["min_font_size"] == 6
    assert 0 < report["pages"][0]["body_occupancy"] < 0.1


def test_page_count_and_source_errors_are_hard_errors():
    with make_document() as doc:
        report = audit_document(doc, expected_pages=2, source_issues=[{
            "code": "missing_anchor", "message": "Unknown anchor example", "severity": "error"
        }])
    assert {"page_count_mismatch", "missing_anchor"} <= codes(report)
    assert report["summary"]["errors"] == 2
    assert all("page" in issue for issue in report["issues"])


def test_detects_text_outside_page_even_when_normal_extraction_clips_it():
    with make_document() as doc:
        doc[0].insert_text((280, 40), "Hidden overflow text", fontsize=14)
        report = audit_document(doc)
    clipped = [i for i in report["issues"] if i["code"] == "text_out_of_bounds"]
    assert clipped and clipped[0]["severity"] == "error"
    assert clipped[0]["bbox"][2] > 300


def linked_document(target="S1 reference", destination_y=70):
    doc = make_document()
    doc.new_page(width=300, height=300)
    doc[0].insert_text((30, 40), "S1", fontsize=12)
    doc[1].insert_text((30, 80), target, fontsize=12)
    doc[0].insert_link({"kind": pymupdf.LINK_GOTO, "from": pymupdf.Rect(29, 25, 50, 45),
                        "page": 1, "to": pymupdf.Point(0, destination_y)})
    doc[0].insert_link({"kind": pymupdf.LINK_URI, "from": pymupdf.Rect(60, 25, 90, 45),
                        "uri": "https://example.com"})
    return pymupdf.open(stream=doc.tobytes(), filetype="pdf")


def test_expected_link_checks_actual_annotation_destination_and_counts_links():
    with linked_document() as doc:
        report = audit_document(doc, expected_links=[{
            "text": "S1", "target_text": "S1 reference", "target_id": "ref-1"
        }])
    assert report["summary"]["errors"] == 0
    assert report["summary"]["internal_links"] == 1
    assert report["summary"]["external_links"] == 1


def test_target_text_does_not_match_similar_numbered_reference():
    with linked_document(target="S10 reference") as doc:
        report = audit_document(doc, expected_links=[{
            "text": "S1", "target_text": "S1", "target_id": "ref-1"
        }])
    assert "link_target_mismatch" in codes(report)


def test_expected_link_requires_pdf_annotation_and_nearby_target():
    with linked_document(destination_y=200) as doc:
        report = audit_document(doc, expected_links=[
            {"text": "S1", "target_text": "S1 reference", "target_id": "ref-1"},
            {"text": "S2", "target_text": "S2 reference", "target_id": "ref-2"},
        ])
    assert {"link_target_mismatch", "missing_pdf_link"} <= codes(report)


def test_invalid_bookmark_and_goto_are_hard_errors():
    with linked_document() as doc:
        # Low-level PDF mutation preserves an invalid destination that insert_link rejects.
        link = doc[0].get_links()[0]
        doc.xref_set_key(link["xref"], "A/D", "[99999 0 R /XYZ 0 0 0]")
        doc.set_toc([[1, "Example section", 1]])
        doc.xref_set_key(doc.get_outline_xrefs()[0], "A/D", "[99999 0 R /XYZ 0 0 0]")
        report = audit_document(doc)
    assert {"invalid_link_destination", "invalid_bookmark_destination"} <= codes(report)


def test_empty_inline_anchor_near_reference_line_is_valid():
    with linked_document(destination_y=110) as doc:
        report = audit_document(doc, expected_links=[{
            "text": "S1", "target_text": "S1 reference", "target_id": "ref-1"
        }])
    assert report["summary"]["errors"] == 0


def test_hidden_overflow_does_not_report_visible_clipping():
    with make_document() as doc:
        doc[0].insert_text((280, 40), "Invisible overflow", fontsize=14, render_mode=3)
        report = audit_document(doc)
    assert "text_out_of_bounds" not in codes(report)
    assert report["pages"][0]["chars"] == 0


def test_unmatchable_wrapped_anchor_is_unverified_warning():
    with linked_document() as doc:
        report = audit_document(doc, expected_links=[{
            "text": "A long source anchor which wraps over multiple lines and lacks reliable extracted text",
            "target_text": "S1 reference", "target_id": "ref-1"
        }])
    assert "unverified_pdf_link" in codes(report)
    assert report["summary"]["errors"] == 0


def test_numbered_source_label_does_not_match_similar_label():
    with linked_document() as doc:
        report = audit_document(doc, expected_links=[{
            "text": "S10", "target_text": "S1 reference", "target_id": "ref-10"
        }])
    assert "missing_pdf_link" in codes(report)


def test_bad_destination_coordinate_is_an_error_without_source_expectations():
    with linked_document(destination_y=400) as doc:
        report = audit_document(doc)
    assert "invalid_link_destination" in codes(report)


def duplicate_label_document(second_destination=180):
    doc = make_document()
    doc.new_page(width=300, height=300)
    for y, target_y in [(40, 70), (80, second_destination)]:
        doc[0].insert_text((30, y), "Details", fontsize=12)
        doc[0].insert_link({"kind": pymupdf.LINK_GOTO,
                            "from": pymupdf.Rect(29, y-15, 80, y+4),
                            "page": 1, "to": pymupdf.Point(30, target_y)})
    doc[1].insert_text((30, 80), "Alpha", fontsize=12)
    doc[1].insert_text((30, 190), "Beta", fontsize=12)
    return pymupdf.open(stream=doc.tobytes(), filetype="pdf")


def test_duplicate_source_labels_require_plausible_targets_without_false_errors():
    with duplicate_label_document() as doc:
        report = audit_document(doc, expected_links=[
            {"text": "Details", "target_text": "Alpha", "target_id": "alpha"},
            {"text": "Details", "target_text": "Beta", "target_id": "beta"},
        ])
    assert report["summary"]["errors"] == 0
    assert "ambiguous_pdf_link" in codes(report)


def test_duplicate_source_labels_still_require_each_expected_target():
    with duplicate_label_document(second_destination=70) as doc:
        report = audit_document(doc, expected_links=[
            {"text": "Details", "target_text": "Alpha", "target_id": "alpha"},
            {"text": "Details", "target_text": "Beta", "target_id": "beta"},
        ])
    assert "link_target_mismatch" in codes(report)


def test_adjacent_wrong_reference_does_not_validate_previous_reference():
    with linked_document(destination_y=100) as doc:
        doc[1].insert_text((30, 100), "S2 reference", fontsize=12)
        report = audit_document(doc, expected_links=[{
            "text": "S1", "target_text": "S1", "target_id": "ref-1"
        }])
    assert "link_target_mismatch" in codes(report)


def test_neighbor_column_reference_does_not_validate_wrong_column():
    with linked_document() as doc:
        doc[1].insert_text((180, 80), "S2", fontsize=12)
        link = doc[0].get_links()[0]
        link["to"] = pymupdf.Point(180, 70)
        doc[0].update_link(link)
        report = audit_document(doc, expected_links=[{
            "text": "S1", "target_text": "S1", "target_id": "ref-1"
        }])
    assert "link_target_mismatch" in codes(report)


def named_destination_document(valid=True):
    doc = linked_document()
    link = doc[0].get_links()[0]
    doc.xref_set_key(link["xref"], "A/D", "/ref-1")
    if valid:
        doc.xref_set_key(doc.pdf_catalog(), "Names",
                         f"<< /Dests << /Names [(ref-1) [{doc.page_xref(1)} 0 R /XYZ 30 230 0]] >> >>")
    return pymupdf.open(stream=doc.tobytes(), filetype="pdf")


def test_named_destinations_resolve_with_pdf_coordinate_conversion():
    with named_destination_document() as doc:
        assert doc[0].get_links()[0]["kind"] == pymupdf.LINK_NAMED
        report = audit_document(doc, expected_links=[{
            "text": "S1", "target_text": "S1 reference", "target_id": "ref-1"
        }])
    assert report["summary"]["errors"] == 0
    assert report["summary"]["internal_links"] == 1


def test_unresolved_named_destination_is_an_error():
    with named_destination_document(valid=False) as doc:
        report = audit_document(doc)
    assert "invalid_link_destination" in codes(report)
