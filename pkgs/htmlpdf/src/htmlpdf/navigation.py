"""Repair browser named destinations only when target identity is proven."""

from __future__ import annotations

import re
from typing import Any

import pymupdf


def _heading_occurrences(doc: Any, text: str) -> list[tuple[int, Any]]:
    """Group search rectangles belonging to one whole-word heading occurrence."""
    normalized = " ".join(text.split())
    if not normalized:
        return []
    pattern = re.compile(r"(?<!\w)" + re.escape(normalized) + r"(?!\w)", re.IGNORECASE)
    occurrences = []
    for page_number, page in enumerate(doc):
        words = page.get_text("words")
        fragments: list[str] = []
        first_box = None
        for box in page.search_for(text):
            # Search can match a prefix of a word; whole extracted words retain
            # boundary evidence (S1 must not be confused with S10).
            fragment = " ".join(word[4] for word in words
                                if box.intersects(pymupdf.Rect(word[:4])))
            if first_box is None:
                first_box = box
            fragments.append(fragment)
            combined = " ".join(" ".join(fragments).split())
            if pattern.search(combined):
                occurrences.append((page_number, first_box))
                fragments = []
                first_box = None
            elif not normalized.casefold().startswith(combined.casefold()):
                # Never stitch unrelated, incomplete search matches together.
                fragments = []
                first_box = None
    return occurrences


def repair_named_links(doc: Any, expected_links: list[dict[str, str]]) -> dict[str, Any]:
    """Replace known named links with unique heading-based explicit GoTo links.

    Native destination IDs identify targets independently of repeated source
    labels. Missing or ambiguous target evidence leaves the original annotation
    intact for quality checks and emits an advisory warning.
    """
    expectations: dict[str, set[str]] = {}
    for expected in expected_links:
        target_id = expected.get("target_id", "")
        if target_id:
            expectations.setdefault(target_id, set()).add(expected.get("target_text", ""))
    locations: dict[str, list[tuple[int, Any]]] = {}
    issues: list[dict[str, Any]] = []
    repaired = 0
    for page_number in range(len(doc)):
        page = doc[page_number]
        changed = False
        for link in page.get_links():
            target_id = link.get("nameddest")
            if link.get("kind") != pymupdf.LINK_NAMED or target_id not in expectations:
                continue
            texts = expectations[target_id]
            if len(texts) == 1:
                text = next(iter(texts))
                if text not in locations:
                    locations[text] = _heading_occurrences(doc, text)
                matches = locations[text]
            else:
                matches = []
            if len(matches) != 1:
                issues.append({
                    "code": "named_link_target_unverified", "severity": "warning",
                    "page": page_number + 1,
                    "message": f"Named destination {target_id!r} has no unique target heading; "
                               "original link retained for review.",
                })
                continue
            target_page, box = matches[0]
            updated = dict(link)
            updated.update(kind=pymupdf.LINK_GOTO, page=target_page,
                           to=pymupdf.Point(box.x0, max(0, box.y0 - 2)))
            page.update_link(updated)
            repaired += 1
            changed = True
        if changed:
            doc.reload_page(page)
    return {"repaired": repaired, "issues": issues}
