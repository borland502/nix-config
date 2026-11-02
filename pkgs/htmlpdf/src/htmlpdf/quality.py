"""Deterministic PDF checks; warnings are review prompts, never layout fixes."""

from __future__ import annotations

import re
from typing import Any

import pymupdf


def _normalize(text: str) -> str:
    return " ".join(text.split())


def _contains(text: str, expected: str) -> bool:
    expected = _normalize(expected)
    return bool(expected) and re.search(
        r"(?<!\w)" + re.escape(expected) + r"(?!\w)", _normalize(text)
    ) is not None


def _bad_raw_destination(doc: Any, xref: int, page_xrefs: set[int]) -> bool:
    # MuPDF sometimes maps nonexistent page references to page zero.
    if not xref:
        return False
    for key in ("A/D", "Dest"):
        kind, value = doc.xref_get_key(xref, key)
        if kind == "array":
            match = re.match(r"\[\s*(\d+)\s+\d+\s+R", value)
            if match and int(match.group(1)) not in page_xrefs:
                return True
    return False



def _target_status(page: Any, point: Any, expected: str) -> str:
    """Compare destination geometry with the target and competing text lines."""
    lines = [("".join(span["text"] for span in line["spans"]),
              pymupdf.Rect(line["bbox"]))
             for block in page.get_text("dict")["blocks"]
             for line in block.get("lines", [])]
    # search_for can match S1 inside S10; require whole-word line evidence too.
    matching_lines = [box for text, box in lines if _contains(text, expected)]
    targets = [box for box in page.search_for(expected)
               if any(line.intersects(box) for line in matching_lines)]
    if not targets:
        # Wrapped headings can be extracted differently from annotation metadata.
        return "unverified" if _contains(page.get_text(), expected) else "mismatch"

    def distance(box: Any) -> float:
        # Anchors identify the beginning of text, not any point along a long line.
        dy = max(box.y0 - point.y, point.y - box.y1, 0)
        return ((box.x0 - point.x) ** 2 + dy ** 2) ** 0.5

    nearby = [box for box in targets if abs(box.x0 - point.x) <= 60
              and max(box.y0 - point.y, point.y - box.y1, 0) <= 40]
    if not nearby:
        return "mismatch"
    closest_target = min(distance(box) for box in nearby)
    closest_line = min((distance(box) for _, box in lines), default=closest_target)
    # A different closer line identifies adjacent references and other columns.
    return "valid" if closest_target <= closest_line + 1 else "mismatch"


def audit_document(
    doc: Any,
    *,
    expected_pages: int | None = None,
    min_font_size: float = 7.0,
    source_issues: list[dict[str, Any]] | None = None,
    expected_links: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    """Audit a loaded PDF with 1-based issue pages and JSON-safe diagnostics.

    expected_links contains source text, target_text and target_id. Standalone
    inspection can validate destinations but cannot infer missing source anchors.
    Body occupancy measures visible text box area, excluding the outer 5% bands;
    it is advisory and does not claim to measure image or chart density.
    """
    issues: list[dict[str, Any]] = []
    pages: list[dict[str, Any]] = []
    links: list[tuple[int, dict[str, Any], str]] = []
    internal_links = external_links = 0
    page_xrefs = {doc.page_xref(i) for i in range(len(doc))}

    def issue(code: str, severity: str, page: int | None, message: str,
              bbox: Any = None) -> None:
        item: dict[str, Any] = {"code": code, "severity": severity, "page": page, "message": message}
        if bbox is not None:
            item["bbox"] = [round(float(v), 3) for v in bbox]
        issues.append(item)

    for supplied in source_issues or []:
        item = dict(supplied)
        item.setdefault("severity", "error")
        item.setdefault("page", None)
        item.setdefault("code", "source_issue")
        item.setdefault("message", "Source validation issue")
        issues.append(item)
    if expected_pages is not None and len(doc) != expected_pages:
        issue("page_count_mismatch", "error", None,
              f"Expected {expected_pages} pages; PDF has {len(doc)}.")

    for index, page in enumerate(doc):
        number = index + 1
        # Texttrace includes glyphs outside the crop box that get_text omits.
        # It also uses glyph boxes rather than oversized font ascender boxes.
        spans = [s for s in page.get_texttrace()
                 if s.get("type") != 3 and s.get("opacity", 1) > 0]
        bounds = page.rect * page.derotation_matrix
        body = pymupdf.Rect(bounds)
        body.y0 += bounds.height * 0.05
        body.y1 -= bounds.height * 0.05
        area = 0.0
        chars = 0
        sizes = []
        for span in spans:
            text = "".join(chr(c[0]) for c in span["chars"] if c[0] >= 0)
            if not text.strip():
                continue
            chars += len(text)
            sizes.append(float(span["size"]))
            bbox = pymupdf.Rect(span["bbox"])
            clipped = bbox & body
            area += max(0.0, clipped.get_area())
            tolerance = pymupdf.Rect(bounds.x0 - 1, bounds.y0 - 1,
                                     bounds.x1 + 1, bounds.y1 + 1)
            if not tolerance.contains(bbox):
                issue("text_out_of_bounds", "error", number,
                      "Visible text extends beyond the page crop box.", bbox)
        occupancy = min(1.0, area / body.get_area()) if body.get_area() else 0.0
        smallest = min(sizes) if sizes else None
        pages.append({"page": number, "chars": chars, "body_occupancy": round(occupancy, 5),
                          "min_font_size": round(smallest, 3) if smallest is not None else None})
        if occupancy < 0.03 and chars < 200:
            issue("sparse_page", "warning", number,
                  "Page has little body text; visually review intentional whitespace or graphics.")
        if smallest is not None and smallest < min_font_size:
            issue("small_font", "warning", number,
                  f"Smallest visible text is {smallest:.2f}pt (threshold {min_font_size:g}pt).")
        for link in page.get_links():
            link = dict(link)
            kind = link.get("kind")
            if kind == pymupdf.LINK_NAMED and link.get("nameddest"):
                # get_links exposes named destination points in PDF coordinates;
                # resolve_link returns the top-left coordinates used for text.
                resolved = doc.resolve_link("#nameddest=" + link["nameddest"])
                if resolved and len(resolved) == 3 and 0 <= resolved[0] < len(doc):
                    link.update(kind=pymupdf.LINK_GOTO, page=resolved[0],
                                to=pymupdf.Point(resolved[1], resolved[2]))
                    kind = pymupdf.LINK_GOTO
            if kind in (pymupdf.LINK_URI, pymupdf.LINK_GOTOR, pymupdf.LINK_LAUNCH):
                external_links += 1
                continue
            internal_links += 1
            source_text = page.get_textbox(link["from"])
            links.append((number, link, source_text))
            target = link.get("page", -1)
            bad = _bad_raw_destination(doc, link.get("xref", 0), page_xrefs)
            if kind == pymupdf.LINK_GOTO:
                bad = bad or not 0 <= target < len(doc)
                point = link.get("to")
                if not bad and point is not None:
                    target_bounds = doc[target].rect * doc[target].derotation_matrix
                    bad = not pymupdf.Rect(target_bounds.x0 - 1, target_bounds.y0 - 1,
                                          target_bounds.x1 + 1, target_bounds.y1 + 1).contains(point)
            else:
                # Unresolved named/internal actions are not proven valid destinations.
                bad = True
            if bad:
                issue("invalid_link_destination", "error", number,
                      "Internal PDF link has an invalid or unresolved destination.", link["from"])

    for entry in doc.get_toc(simple=False):
        _, title, page_number, destination = entry
        kind = destination.get("kind")
        if kind in (pymupdf.LINK_URI, pymupdf.LINK_GOTOR, pymupdf.LINK_LAUNCH):
            continue
        if (not 1 <= page_number <= len(doc)
                or _bad_raw_destination(doc, destination.get("xref", 0), page_xrefs)):
            issue("invalid_bookmark_destination", "error", None,
                  f"Bookmark {title!r} has an invalid destination.")

    expectation_targets: dict[str, set[str]] = {}
    for expectation in expected_links or []:
        expectation_targets.setdefault(_normalize(expectation.get("text", "")), set()).add(
            expectation.get("target_id") or expectation.get("target_text", ""))
    warned_labels: set[str] = set()
    for expectation in expected_links or []:
        text = expectation.get("text", "")
        target_text = expectation.get("target_text", "")
        label = expectation.get("target_id", target_text)
        candidates = [(number, link) for number, link, source in links
                      if _contains(source, text)]
        if not candidates:
            # Long wrapping anchors may be split into multiple annotation boxes.
            fragments = [(number, link) for number, link, source in links
                         if len(_normalize(source)) >= 4 and _contains(text, source)]
            if fragments:
                candidates = fragments
            else:
                wrapped = len(_normalize(text)) > 60
                issue("unverified_pdf_link" if wrapped else "missing_pdf_link",
                      "warning" if wrapped else "error", None,
                      f"No PDF internal link matches source text {text!r} for {label!r}."
                      + (" Wrapped annotation text requires visual review." if wrapped else ""))
                continue
        results = []
        for number, link in candidates:
            target = link.get("page", -1)
            if link.get("kind") != pymupdf.LINK_GOTO or not 0 <= target < len(doc):
                continue  # Already reported as an invalid destination.
            if not target_text:
                continue
            state = _target_status(doc[target], link.get("to", pymupdf.Point(0, 0)), target_text)
            results.append((number, link, state))
        ambiguous = len(expectation_targets[_normalize(text)]) > 1
        if ambiguous and any(state == "valid" for _, _, state in results):
            if text not in warned_labels:
                issue("ambiguous_pdf_link", "warning", None,
                      f"Repeated source label {text!r} has plausible target links; "
                      "individual source occurrences require visual review.")
                warned_labels.add(text)
            continue
        for number, link, state in results:
            if state == "mismatch":
                issue("link_target_mismatch", "error", number,
                      f"Link for {label!r} does not land at expected text {target_text!r}.",
                      link["from"])
            elif state == "unverified":
                issue("unverified_pdf_link", "warning", number,
                      f"Destination geometry for {label!r} requires visual review.", link["from"])

    return {"schema_version": 1, "pages": pages, "issues": issues, "summary": {
        "errors": sum(i["severity"] == "error" for i in issues),
        "warnings": sum(i["severity"] == "warning" for i in issues),
        "internal_links": internal_links, "external_links": external_links,
    }}
