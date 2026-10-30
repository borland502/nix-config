"""Pixel-based PDF comparisons and a labeled review contact sheet."""

import hashlib
import json
import math
import os
import re
import tempfile
from collections.abc import Iterable
from pathlib import Path
from typing import Any

import pymupdf

_SCHEMA_VERSION = 1


def _validate_manifest(manifest: Any, dpi: int) -> list[dict[str, Any]]:
    if (not isinstance(manifest, dict)
            or type(manifest.get("schema_version")) is not int
            or manifest["schema_version"] != _SCHEMA_VERSION):
        raise ValueError("Previous manifest has an unsupported or missing schema_version")
    if type(manifest.get("dpi")) is not int or manifest["dpi"] != dpi:
        raise ValueError("Previous manifest dpi is missing or incompatible with requested dpi")
    count = manifest.get("page_count")
    pages = manifest.get("pages")
    if type(count) is not int or count < 0 or not isinstance(pages, list) or len(pages) != count:
        raise ValueError("Previous manifest page_count and pages are inconsistent")
    for number, page in enumerate(pages, 1):
        if (not isinstance(page, dict) or page.get("page") != number
                or not isinstance(page.get("sha256"), str)
                or not re.fullmatch(r"[0-9a-f]{64}", page["sha256"])
                or any(type(page.get(key)) is not int or page[key] <= 0
                       for key in ("width", "height"))):
            raise ValueError(f"Previous manifest contains an invalid page entry at {number}")
    return pages


def _atomic_write(destination: Path, content: bytes) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(content)
        os.replace(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


def build_review(
    doc: pymupdf.Document,
    output_dir: str | Path,
    *,
    previous_manifest: dict[str, Any] | None = None,
    flagged_pages: Iterable[int] = (),
    dpi: int = 72,
) -> dict[str, Any]:
    """Write a contact sheet and atomic manifest; page numbers are one-based.

    Hashes cover RGB pixels, including drawings and images. Width and height are
    rendered pixel dimensions. Comparisons require the same schema and DPI.
    A changed page means pixels or dimensions differ at that page position.
    """
    if type(dpi) is not int or dpi <= 0:
        raise ValueError("dpi must be a positive integer")
    flags = list(flagged_pages)
    if any(type(number) is not int or not 1 <= number <= len(doc) for number in flags):
        raise ValueError("flagged_pages must contain one-based page numbers in this document")
    flags = sorted(set(flags))
    previous = _validate_manifest(previous_manifest, dpi) if previous_manifest is not None else []
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    pages: list[dict[str, Any]] = []
    changed: list[int] = []
    columns = min(3, max(1, len(doc)))
    cell_width, cell_height, padding = 320, 270, 12
    rows = max(1, math.ceil(len(doc) / columns))
    with pymupdf.open() as sheet:
        canvas = sheet.new_page(width=columns * cell_width, height=rows * cell_height)
        if not len(doc):
            canvas.insert_text((padding, 24), "No pages", fontsize=12)
        for index in range(len(doc)):
            page = doc.load_page(index)
            number = index + 1
            pixels = page.get_pixmap(dpi=dpi, colorspace=pymupdf.csRGB, alpha=False)
            entry = {"page": number, "sha256": hashlib.sha256(pixels.samples).hexdigest(),
                     "width": pixels.width, "height": pixels.height}
            pages.append(entry)
            is_changed = index >= len(previous) or entry != previous[index]
            if is_changed:
                changed.append(number)
            left = (index % columns) * cell_width
            top = (index // columns) * cell_height
            labels = [f"Page {number}"]
            if is_changed:
                labels.append("CHANGED")
            if number in flags:
                labels.append("FLAGGED")
            canvas.insert_text((left + padding, top + 23), " | ".join(labels), fontsize=11,
                               color=(0.7, 0.15, 0.08) if number in flags else (0.1, 0.2, 0.3))
            available = pymupdf.Rect(left + padding, top + 36,
                                     left + cell_width - padding, top + cell_height - padding)
            scale = min(available.width / pixels.width, available.height / pixels.height)
            width, height = pixels.width * scale, pixels.height * scale
            thumbnail = pymupdf.Rect(available.x0 + (available.width - width) / 2,
                                     available.y0, available.x0 + (available.width + width) / 2,
                                     available.y0 + height)
            canvas.insert_image(thumbnail, pixmap=pixels)
            canvas.draw_rect(thumbnail, color=(0.4, 0.45, 0.5), width=0.75)
        _atomic_write(output_dir / "contact-sheet.png", canvas.get_pixmap(alpha=False).tobytes("png"))
    manifest = {"schema_version": _SCHEMA_VERSION, "dpi": dpi, "page_count": len(doc),
                "pages": pages, "changed_pages": changed,
                "removed_pages": list(range(len(doc) + 1, len(previous) + 1)), "flagged_pages": flags}
    _atomic_write(output_dir / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode())
    return manifest
