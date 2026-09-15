"""htmlpdf — turn rich HTML or Markdown into a readable, bookmarked PDF.

Renders with Chrome through Playwright, so everything a browser draws prints as it
looks on screen: CSS grid layouts, web fonts, SVG/canvas charts, Mermaid diagrams,
MathJax. Then it prepares the page for paper and finishes the PDF:

  * light theme, white ground, and a legible link color with a soft underline;
  * no sticky/fixed chrome, expanded <details>, scroll containers opened up,
    long code lines wrapped, over-wide tables and media scaled to the page;
  * tall single-column grids re-flowed as block layout so keep-together and
    keep-with-next rules work (Chrome ignores them inside grid containers);
  * Mermaid rendered with a print theme when the page has not rendered it, and
    left-to-right flowcharts too wide for the page redrawn top-to-bottom;
  * bookmarks mirroring the document's own contents list (or its headings),
    each pointing at the heading's exact position on the page;
  * an audit: fonts Chrome actually used (web font or fallback), bookmark tree,
    link contrast, and preview PNGs of chosen pages.

Usage:
  htmlpdf convert page.html [-o out.pdf] [options]
  htmlpdf convert notes.md  [-o out.pdf] [options]
  htmlpdf.py inspect out.pdf [--preview 1,3-4]

Documents can steer the result with ordinary CSS: an `@media print` block, a
`.page-break` (or `[data-htmlpdf-break]`) element to start a new page, and
`.no-print` (or `[data-htmlpdf-hide]`) to drop screen-only controls.
"""

from __future__ import annotations

import argparse
import base64
import html
import os
import re
import shutil
import sys
import tempfile
import unicodedata
from collections import defaultdict, deque
from collections.abc import Collection, Iterator
from contextlib import contextmanager, nullcontext
from functools import cache
from importlib import resources
from pathlib import Path
from typing import cast

import pymupdf

MERMAID_VERSION = "11.4.1"
MERMAID_ASSET = f"mermaid-{MERMAID_VERSION}.min.js"
DEFAULT_LINK_COLOR = "#1A5FB4"  # 6.3:1 on white: reads as a link, not as body text
PAPER_INCHES = {"letter": (8.5, 11.0), "a4": (8.27, 11.69), "legal": (8.5, 14.0), "tabloid": (11.0, 17.0)}
UNIT_PX = {"px": 1.0, "in": 96.0, "mm": 96 / 25.4, "cm": 96 / 2.54, "pt": 96 / 72}
SANS_STACK = "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif"
MARKDOWN_FONT_FACES = (
    ("IBM Plex Mono", "normal", "400", "ibm-plex-mono-regular-latin.woff2"),
    ("IBM Plex Mono", "normal", "500", "ibm-plex-mono-medium-latin.woff2"),
    ("Public Sans", "normal", "400 700", "public-sans-latin.woff2"),
    ("Source Serif 4", "normal", "400 600", "source-serif-4-roman-latin.woff2"),
    ("Source Serif 4", "italic", "400", "source-serif-4-italic-latin.woff2"),
)
CALLOUT_TITLES = {"note": "Note", "tip": "Tip", "important": "Important", "warning": "Warning", "caution": "Caution"}

MERMAID_CONFIG = {
    "startOnLoad": False,
    "securityLevel": "strict",
    "theme": "base",
    "fontFamily": '"Public Sans", "Helvetica Neue", Arial, sans-serif',
    "themeVariables": {
        "fontSize": "15px",
        "textColor": "#1F2933",
        "lineColor": "#52606D",
        "primaryColor": "#F3F6FA",
        "primaryBorderColor": "#9FB1C5",
        "primaryTextColor": "#1F2933",
        "actorBkg": "#F3F6FA",
        "actorBorder": "#9FB1C5",
        "actorTextColor": "#1F2933",
        "signalColor": "#3E4C59",
        "signalTextColor": "#1F2933",
        "labelBoxBkgColor": "#F3F6FA",
        "labelBoxBorderColor": "#9FB1C5",
        "labelTextColor": "#1F2933",
        "loopTextColor": "#1F2933",
        "noteBkgColor": "#FFF4D6",
        "noteBorderColor": "#E3C26F",
        "noteTextColor": "#1F2933",
        "activationBkgColor": "#E4ECF5",
    },
    "sequence": {
        "wrap": True,
        "width": 140,
        "actorMargin": 36,
        "boxMargin": 8,
        "messageMargin": 30,
        "mirrorActors": False,
        "actorFontSize": 14,
        "messageFontSize": 14,
        "noteFontSize": 13,
        "useMaxWidth": True,
    },
    "flowchart": {"htmlLabels": True, "useMaxWidth": True, "curve": "basis"},
}

# --------------------------------------------------------------------------- page scripts


@contextmanager
def mermaid_script_tag(override_url: str | None) -> Iterator[dict[str, str]]:
    if override_url:
        yield {"url": override_url}
        return

    asset = resources.files("htmlpdf").joinpath("assets", MERMAID_ASSET)
    with resources.as_file(asset) as path:
        yield {"path": str(path)}


WAIT_JS = """
async () => {
  for (const img of document.images) img.loading = 'eager';
  // Walk the page so lazy images and scroll-triggered content load.
  const step = Math.max(200, window.innerHeight * 0.8);
  for (let y = 0; y < document.documentElement.scrollHeight; y += step) {
    window.scrollTo(0, y);
    await new Promise((resolve) => setTimeout(resolve, 30));
  }
  window.scrollTo(0, 0);
  await Promise.all([...document.images].map((img) => img.complete ? null : new Promise((resolve) => {
    img.addEventListener('load', resolve, { once: true });
    img.addEventListener('error', resolve, { once: true });
  })));
  if (window.MathJax?.startup?.promise) await window.MathJax.startup.promise;
  if (typeof window.MathJax?.typesetPromise === 'function') await window.MathJax.typesetPromise();
  await document.fonts.ready;
}
"""

NEEDS_MERMAID_JS = """
() => [...document.querySelectorAll('pre.mermaid, div.mermaid, code.language-mermaid')]
  .some((el) => !el.querySelector('svg'))
"""

RENDER_MERMAID_JS = """
async ({ config, reorient }) => {
  for (const code of document.querySelectorAll('code.language-mermaid')) {
    const holder = code.closest('pre') ?? code;
    const pre = document.createElement('pre');
    pre.className = 'mermaid';
    pre.textContent = code.textContent;
    holder.replaceWith(pre);
  }
  const nodes = [...document.querySelectorAll('.mermaid:not([data-processed="true"])')];
  const sources = new Map(nodes.map((el) => [el, el.textContent]));
  window.mermaid.initialize(config);
  await window.mermaid.run({ nodes });

  // A left-to-right flowchart much wider than the page shrinks to unreadable
  // text when scaled to fit; the same graph drawn top-to-bottom stays legible.
  const again = [];
  if (reorient) {
    for (const [el, source] of sources) {
      const svg = el.querySelector('svg');
      if (!svg) continue;
      const natural = svg.viewBox?.baseVal?.width || svg.getBoundingClientRect().width;
      const available = el.parentElement?.clientWidth || document.documentElement.clientWidth;
      if (natural <= available * 1.5) continue;
      if (!/^\\s*(flowchart|graph)\\s+(LR|RL)\\b/i.test(source)) continue;
      el.removeAttribute('data-processed');
      el.textContent = source.replace(/^(\\s*(?:flowchart|graph)\\s+)(LR|RL)\\b/i, '$1TB');
      again.push(el);
    }
    if (again.length) {
      await window.mermaid.run({ nodes: again });
      again.forEach((el) => el.setAttribute('data-htmlpdf-reoriented', ''));
    }
  }
  return { rendered: nodes.length, reoriented: again.length };
}
"""

NORMALIZE_JS = """
(opts) => {
  const report = { themeHooks: 0, hidden: 0, detailsOpened: 0, unstuck: 0, scrollBoxesOpened: 0,
                   codeWrapped: 0, gridsReflowed: 0, scaledToFit: [] };
  const root = document.documentElement;
  const px = (value) => parseFloat(value) || 0;
  const all = () => [...document.body.querySelectorAll('*')];

  // Light-theme hooks used by common frameworks and design systems.
  if (opts.forceLight) {
    for (const el of [root, document.body]) {
      if (!el) continue;
      for (const cls of ['dark', 'dark-mode', 'theme-dark']) {
        if (el.classList.contains(cls)) { el.classList.remove(cls); report.themeHooks++; }
      }
      for (const attr of ['data-theme', 'data-bs-theme', 'data-color-mode', 'data-mode']) {
        if (el.getAttribute(attr) === 'dark') { el.setAttribute(attr, 'light'); report.themeHooks++; }
      }
    }
    if (!root.hasAttribute('data-theme')) root.setAttribute('data-theme', 'light');
  }

  for (const selector of ['.no-print', '[data-htmlpdf-hide]', ...opts.hide]) {
    document.querySelectorAll(selector).forEach((el) => {
      el.style.setProperty('display', 'none', 'important');
      report.hidden++;
    });
  }

  document.querySelectorAll('details:not([open])').forEach((d) => { d.open = true; report.detailsOpened++; });

  // Sticky or fixed elements would repeat or overlap content on every page.
  for (const el of all()) {
    const position = getComputedStyle(el).position;
    if (position === 'fixed' || position === 'sticky') {
      el.style.setProperty('position', 'static', 'important');
      report.unstuck++;
    }
  }

  // Scroll containers clip on paper; let them grow to their content.
  for (const el of all()) {
    const cs = getComputedStyle(el);
    if (!/(auto|scroll)/.test(`${cs.overflowX} ${cs.overflowY}`)) continue;
    el.style.setProperty('overflow', 'visible', 'important');
    if (/(auto|scroll)/.test(cs.overflowY)) {
      el.style.setProperty('max-height', 'none', 'important');
      el.style.setProperty('height', 'auto', 'important');
    }
    report.scrollBoxesOpened++;
  }

  // Long code lines wrap instead of running off the page.
  for (const pre of document.querySelectorAll('pre')) {
    if (pre.classList.contains('mermaid') || pre.querySelector('svg')) continue;
    if (pre.scrollWidth > pre.clientWidth + 1) {
      pre.style.setProperty('white-space', 'pre-wrap', 'important');
      pre.style.setProperty('overflow-wrap', 'anywhere', 'important');
      report.codeWrapped++;
    }
  }

  // Chrome does not honor break-inside/break-after inside grid formatting contexts,
  // so tall single-column grids split figures and orphan headings. Re-flow them as
  // block layout, carrying the row gap over as margins. This runs before the fit
  // pass: an auto-sized grid track can be wider than its container until re-flow.
  for (const el of all()) {
    const cs = getComputedStyle(el);
    if (cs.display !== 'grid' || cs.gridAutoFlow.startsWith('column')) continue;
    const tracks = cs.gridTemplateColumns === 'none' ? 1 : cs.gridTemplateColumns.trim().split(/\\s+/).length;
    if (tracks !== 1 || el.getBoundingClientRect().height < opts.reflowMinHeight) continue;
    if (!/^(normal|stretch|legacy)/.test(cs.justifyItems)) continue;
    const kids = [...el.children]
      .map((kid) => ({ kid, cs: getComputedStyle(kid) }))
      .filter(({ cs: k }) => k.display !== 'none' && k.position !== 'absolute' && k.position !== 'fixed');
    if (kids.some(({ cs: k }) => /^(start|end|center|self-|flex-|left|right)/.test(k.justifySelf))) continue;
    const gap = px(cs.rowGap);
    const snapshot = kids.map(({ kid, cs: k }) => ({ kid, display: k.display, marginTop: px(k.marginTop) }));
    el.style.setProperty('display', 'block', 'important');
    snapshot.forEach(({ kid, display, marginTop }, index) => {
      if (display === 'inline') kid.style.setProperty('display', 'block', 'important');
      else if (display.startsWith('inline-')) kid.style.setProperty('display', display.slice(7), 'important');
      if (index > 0 && gap) kid.style.setProperty('margin-top', `${marginTop + gap}px`, 'important');
    });
    report.gridsReflowed++;
  }

  // Anything still wider than its container is scaled down to fit the page.
  for (const el of document.querySelectorAll('table, svg, img, canvas, video, iframe, figure, [data-htmlpdf-fit]')) {
    if (el.parentElement?.closest('[data-htmlpdf-scaled]')) continue;
    const parent = el.parentElement;
    if (!parent) continue;
    const pcs = getComputedStyle(parent);
    const available = parent.clientWidth - px(pcs.paddingLeft) - px(pcs.paddingRight);
    // The element's own box, not scrollWidth: absolutely positioned descendants
    // (chart labels, tooltips) inflate scrollWidth without widening the layout.
    const needed = el.getBoundingClientRect().width;
    if (available <= 0 || needed <= available + 1) continue;
    if (/^(img|canvas|video|svg)$/i.test(el.tagName)) {
      el.style.setProperty('max-width', '100%', 'important');
      if (!/^svg$/i.test(el.tagName)) el.style.setProperty('height', 'auto', 'important');
    } else {
      el.style.setProperty('zoom', String(Math.max(opts.minZoom, available / needed)));
    }
    el.setAttribute('data-htmlpdf-scaled', '');
    report.scaledToFit.push(`${el.tagName.toLowerCase()} ${Math.round(needed)}→${Math.round(available)}px`);
  }

  return report;
}
"""

TOC_JS = """
(selector) => {
  const pick = () => {
    if (selector) return document.querySelector(selector);
    const candidates = [...document.querySelectorAll(
      'nav, [role="navigation"], .toc, #toc, .table-of-contents, [class*="toc"]')];
    return candidates.find((node) => node.querySelectorAll('a[href^="#"]').length >= 3) ?? null;
  };
  const nav = pick();
  if (!nav) return null;
  const clean = (text) => (text ?? '').replace(/\\s+/g, ' ').trim();
  return [...nav.querySelectorAll('a[href^="#"]')].map((link) => {
    const id = decodeURIComponent(link.getAttribute('href').slice(1));
    const target = id ? document.getElementById(id) : null;
    if (!target) return null;
    const heading = target.matches('h1, h2, h3, h4, h5, h6')
      ? target : target.querySelector('h1, h2, h3, h4, h5, h6');
    let depth = 0;
    for (let node = link.parentElement; node && node !== nav; node = node.parentElement) {
      if (node.matches('li')) depth++;
    }
    return {
      title: clean(link.textContent),
      heading: heading ? clean(heading.textContent) : null,
      headingLevel: heading ? Number(heading.tagName[1]) : null,
      depth,
    };
  }).filter(Boolean);
}
"""

WEB_FONT_FAMILIES_JS = """
() => [...document.fonts].filter((face) => face.status === 'loaded')
  .map((face) => face.family.replace(/^["']|["']$/g, ''))
"""


def print_css(link_color: str | None) -> str:
    links = ""
    if link_color:
        links = f"""
  a[href]:not(:is(h1, h2, h3, h4, h5, h6) a) {{ color: {link_color} !important; }}
  a[href] code {{ color: inherit !important; }}
  a[href] {{
    text-decoration-line: underline;
    text-decoration-thickness: max(1px, 0.06em);
    text-underline-offset: 0.16em;
    text-decoration-color: color-mix(in srgb, {link_color} 40%, transparent);
  }}
  :is(nav, [role="navigation"], .toc, #toc) a[href], a[href]:has(img, svg) {{ text-decoration: none !important; }}"""
    return f"""
@media print {{
  html, body {{ background: #ffffff !important; }}
  * {{ -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }}
  h1, h2, h3, h4, h5, h6 {{ break-after: avoid-page; page-break-after: avoid; }}
  figure, pre, blockquote, img, svg, canvas, video, .mermaid, tr {{ break-inside: avoid-page; page-break-inside: avoid; }}
  thead {{ display: table-header-group; }}
  tfoot {{ display: table-footer-group; }}
  caption {{ break-after: avoid-page; }}
  p, li, dd {{ orphans: 3; widows: 3; }}
  .page-break, [data-htmlpdf-break] {{ break-before: page; page-break-before: always; }}
  .mermaid svg {{ max-width: 100%; height: auto; }}
  .mermaid[data-htmlpdf-reoriented] svg {{ max-height: 6.5in; width: auto; }}
  details > summary {{ list-style: none; }}
  details > summary::-webkit-details-marker {{ display: none; }}{links}
}}
"""


# --------------------------------------------------------------------------- inputs


def load_asset(name: str) -> str:
    try:
        return resources.files("htmlpdf.assets").joinpath(name).read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise SystemExit(f"htmlpdf: missing packaged asset {name}") from error


@cache
def markdown_font_css() -> str:
    try:
        assets = resources.files("htmlpdf.assets")
        return "\n".join(
            f"""@font-face {{
  font-family: "{family}";
  font-style: {style};
  font-weight: {weight};
  font-display: swap;
  src: url(data:font/woff2;base64,{base64.b64encode(assets.joinpath(filename).read_bytes()).decode("ascii")}) format("woff2");
}}"""
            for family, style, weight, filename in MARKDOWN_FONT_FACES
        )
    except FileNotFoundError as error:
        raise SystemExit(f"htmlpdf: missing packaged font {error.filename}") from error


def markdown_to_document(path: Path) -> str:
    from markdown_it import MarkdownIt
    from mdit_py_plugins.anchors import anchors_plugin
    from mdit_py_plugins.deflist import deflist_plugin
    from mdit_py_plugins.footnote import footnote_plugin
    from mdit_py_plugins.front_matter import front_matter_plugin
    from mdit_py_plugins.tasklists import tasklists_plugin
    from pygments import highlight
    from pygments.formatters import HtmlFormatter
    from pygments.lexers import get_lexer_by_name
    from pygments.util import ClassNotFound

    formatter = HtmlFormatter(style="friendly", nowrap=True)

    def fence(code: str, lang: str, _attrs) -> str:
        name = (lang or "").strip().split(" ")[0]
        if name == "mermaid":
            return f'<pre class="mermaid">{html.escape(code)}</pre>'
        try:
            lexer = get_lexer_by_name(name) if name else None
        except ClassNotFound:
            lexer = None
        body = highlight(code, lexer, formatter) if lexer else html.escape(code)
        return f'<pre class="highlight"><code class="language-{html.escape(name)}">{body}</code></pre>'

    text = path.read_text(encoding="utf-8")
    front = re.match(r"\A---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    title = None
    if front:
        found = re.search(r"^title:\s*[\"']?(.+?)[\"']?\s*$", front.group(1), re.MULTILINE)
        title = found.group(1) if found else None
    if not title:
        heading = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
        title = heading.group(1).strip() if heading else path.stem

    md = (
        MarkdownIt("commonmark", {"html": True, "typographer": True, "highlight": fence})
        .enable(["table", "strikethrough"])
        .use(front_matter_plugin)
        .use(footnote_plugin)
        .use(deflist_plugin)
        .use(tasklists_plugin)
        .use(anchors_plugin, min_level=1, max_level=4, permalink=False)
    )
    body = md.render(text)

    # GitHub / Obsidian callouts: > [!NOTE] Optional title
    def callout(match: re.Match) -> str:
        kind = match.group(1).lower()
        label = (match.group(2) or "").strip() or CALLOUT_TITLES.get(kind, kind.title())
        return f'<blockquote class="callout callout-{kind}">\n<p class="callout-title">{label}</p>\n<p>'

    body = re.sub(r"<blockquote>\s*<p>\[!(\w+)\][ \t]*([^\n<]*)\n?", callout, body)

    # Syntax colors first, theme second: the theme owns the code block's ground.
    css = "\n".join((markdown_font_css(), HtmlFormatter(style="friendly").get_style_defs(".highlight"), load_asset("markdown.css")))
    return (
        "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        f"<title>{html.escape(title)}</title>\n<style>\n{css}\n</style>\n</head>\n"
        f"<body>\n<main class=\"doc\">\n{body}\n</main>\n</body>\n</html>\n"
    )


def wrap_fragment(fragment: str) -> str:
    # The HTML parser files <title>/<style>/<link> into <head> and the rest into <body>.
    return f"<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n{fragment}\n</html>\n"


def find_chrome(explicit: str | None) -> str | None:
    candidates = [
        explicit,
        os.environ.get("HTMLPDF_CHROME"),
        shutil.which("google-chrome"),
        shutil.which("google-chrome-stable"),
        shutil.which("chromium"),
        shutil.which("chromium-browser"),
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    ]
    return next((c for c in candidates if c and Path(c).exists()), None)


def stage_html(source: Path, document: str) -> Path:
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=f".{source.stem}.htmlpdf-",
        suffix=".html",
        dir=source.parent,
        delete=False,
    ) as staged:
        staged.write(document)
        return Path(staged.name)


def save_pdf_atomically(doc: pymupdf.Document, output: Path) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.stem}.htmlpdf-",
        suffix=output.suffix,
        dir=output.parent,
    )
    temporary = Path(temporary_name)
    try:
        os.close(descriptor)
        temporary.unlink()
        doc.save(temporary, garbage=3, deflate=True)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)


@contextmanager
def preview_directory_lock(out_dir: Path) -> Iterator[None]:
    import fcntl

    lock_path = out_dir.with_name(f".{out_dir.name}.lock")
    with lock_path.open("a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def save_previews_atomically(
    _document: pymupdf.Document, pdf_path: Path, pages: list[int], dpi: int, *, lock_held: bool = False
) -> Path:
    """Render and publish previews from the PDF state protected by its output lock.

    ``_document`` is deliberately not reused: it may be an older snapshot whose
    path a concurrent converter has atomically replaced.
    """
    out_dir = pdf_path.with_name(f"{pdf_path.stem}-preview")
    staged: Path | None = None
    link: Path | None = None
    published = False
    previous: Path | None = None
    try:
        lock = nullcontext() if lock_held else preview_directory_lock(out_dir)
        with lock:
            staged = Path(tempfile.mkdtemp(prefix=f".{out_dir.name}-", dir=out_dir.parent))
            link = staged.with_name(f"{staged.name}-link")
            current_document = pymupdf.open(pdf_path)
            try:
                for number in pages:
                    current_document[number - 1].get_pixmap(dpi=dpi).save(staged / f"page-{number:02d}.png")
            finally:
                current_document.close()

            os.symlink(staged.name, link)
            if out_dir.exists() and not out_dir.is_symlink():
                previous = Path(tempfile.mkdtemp(prefix=f".{out_dir.name}-previous-", dir=out_dir.parent))
                previous.rmdir()
                os.replace(out_dir, previous)
            elif out_dir.is_symlink():
                candidate = out_dir.resolve()
                if candidate.parent == out_dir.parent and candidate.name.startswith(f".{out_dir.name}-"):
                    previous = candidate
            try:
                os.replace(link, out_dir)
            except OSError:
                if previous and previous.exists() and not out_dir.exists():
                    os.replace(previous, out_dir)
                raise
            published = True
    finally:
        if link:
            link.unlink(missing_ok=True)
        if staged and not published:
            shutil.rmtree(staged, ignore_errors=True)
    if previous:
        shutil.rmtree(previous, ignore_errors=True)
    return out_dir


def length_px(value: str) -> float:
    match = re.fullmatch(r"\s*([\d.]+)\s*(px|in|mm|cm|pt)?\s*", value)
    if not match:
        raise SystemExit(f"htmlpdf: cannot read length {value!r} (use e.g. 14mm, 0.6in, 40px)")
    return float(match.group(1)) * UNIT_PX[match.group(2) or "px"]


def parse_margins(spec: str) -> dict[str, str]:
    parts = [p.strip() for p in spec.split(",") if p.strip()]
    if len(parts) == 1:
        parts *= 4
    elif len(parts) == 2:
        parts = [parts[0], parts[1], parts[0], parts[1]]
    if len(parts) != 4:
        raise SystemExit("htmlpdf: --margin takes 1, 2 or 4 comma-separated lengths (top,right,bottom,left)")
    return dict(zip(["top", "right", "bottom", "left"], parts))


def browser_font_report(page) -> list[tuple[str, int, bool]]:
    """Fonts Chrome actually rendered, by glyph count, flagged web font vs system."""
    web_families = {name.casefold() for name in page.evaluate(WEB_FONT_FAMILIES_JS)}
    totals: dict[str, int] = defaultdict(int)
    try:
        cdp = page.context.new_cdp_session(page)
        cdp.send("DOM.enable")
        cdp.send("CSS.enable")
        root = cdp.send("DOM.getDocument")["root"]["nodeId"]
        node_ids = cdp.send("DOM.querySelectorAll", {"nodeId": root, "selector": "body, body *"})["nodeIds"]
        for node_id in node_ids[:6000]:
            try:
                fonts = cdp.send("CSS.getPlatformFontsForNode", {"nodeId": node_id})["fonts"]
            except Exception:  # detached or non-rendered nodes
                continue
            for font in fonts:
                totals[font["familyName"]] += font["glyphCount"]
        cdp.detach()
    except Exception as error:  # the report is advisory; never fail a conversion over it
        print(f"htmlpdf: warning — font report unavailable ({error})", file=sys.stderr)
    return [(family, count, is_web_font_family(family, web_families))
            for family, count in sorted(totals.items(), key=lambda item: -item[1])]


def is_web_font_family(platform_name: str, web_families: Collection[str]) -> bool:
    normalized = platform_name.casefold()
    return any(normalized.startswith(web_family.casefold()) for web_family in web_families)


# --------------------------------------------------------------------------- bookmarks


def norm(text: str | None) -> str:
    return re.sub(r"\s+", " ", unicodedata.normalize("NFKC", text or "")).strip().casefold()


def search_heading(doc: pymupdf.Document, text: str, start_page: int):
    needle = re.sub(r"\s+", " ", text).strip()[:60]
    if not needle:
        return None
    for index in range(max(0, start_page - 1), doc.page_count):
        hits = doc[index].search_for(needle)
        if hits:
            spot = hits[0]
            return index + 1, {"kind": pymupdf.LINK_GOTO, "page": index, "to": pymupdf.Point(spot.x0, max(0, spot.y0 - 6)), "zoom": 0}
    return None


def repair_levels(entries: list[list]) -> list[list]:
    fixed, previous = [], 0
    for level, title, page, dest in entries:
        level = max(1, min(level, previous + 1))
        fixed.append([level, title, page, dest])
        previous = level
    return fixed


def outline_from_contents(doc: pymupdf.Document, entries: list[dict]) -> tuple[list[list], list[str]]:
    pool: dict[str, deque] = defaultdict(deque)
    for _level, title, page, dest in doc.get_toc(simple=False):
        pool[norm(title)].append((page, dest))

    depths = [e["depth"] for e in entries]
    basis = depths if len(set(depths)) > 1 else [e["headingLevel"] or 9 for e in entries]
    rank = {value: i + 1 for i, value in enumerate(sorted(set(basis)))}

    toc, unmatched, last_page = [], [], 1
    for entry, key_value in zip(entries, basis):
        key = norm(entry["heading"] or entry["title"])
        hit = pool[key].popleft() if pool.get(key) else None
        if hit is None and key:
            for candidate, queue in pool.items():
                if queue and (candidate.startswith(key[:40]) or key.startswith(candidate[:40])):
                    hit = queue.popleft()
                    break
        if hit is None:
            hit = search_heading(doc, entry["heading"] or entry["title"], last_page)
        if hit is None:
            unmatched.append(entry["title"])
            continue
        page, dest = hit
        toc.append([rank[key_value], entry["title"], page, dest])
        last_page = page
    return repair_levels(toc), unmatched


def outline_from_headings(doc: pymupdf.Document, depth: int) -> list[list]:
    toc = doc.get_toc(simple=False)
    if sum(1 for entry in toc if entry[0] == 1) == 1 and len(toc) > 1:
        toc = [[level - 1, title, page, dest] for level, title, page, dest in toc if level > 1]
    return repair_levels([entry for entry in toc if entry[0] <= depth])


# --------------------------------------------------------------------------- audit


def _linear(channel: int) -> float:
    c = channel / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def contrast_on_white(rgb: tuple[int, int, int]) -> float:
    r, g, b = (_linear(x) for x in rgb)
    return 1.05 / (0.2126 * r + 0.7152 * g + 0.0722 * b + 0.05)


def parse_pages(spec: str, count: int) -> list[int]:
    if spec in ("", "none"):
        return []
    if spec == "all":
        return list(range(1, count + 1))
    pages: list[int] = []
    for part in spec.split(","):
        if "-" in part:
            start, end = part.split("-", 1)
            pages.extend(range(int(start), int(end) + 1))
        elif part.strip():
            pages.append(int(part))
    return [p for p in pages if 1 <= p <= count]


def audit(pdf_path: Path, preview: str, dpi: int, pdf_fonts: bool = True, preview_lock_held: bool = False) -> None:
    doc = pymupdf.open(pdf_path)
    size_kb = pdf_path.stat().st_size / 1024
    print(f"\n{pdf_path}\n  {doc.page_count} pages · {size_kb:,.0f} KB · page mode {doc.pagemode}")

    toc = doc.get_toc(simple=True)
    print(f"  bookmarks ({len(toc)}):")
    for level, title, page in toc:
        print(f"    {'  ' * (level - 1)}{title} → p{page}")

    font_chars: dict[str, int] = defaultdict(int)
    colors: dict[str, list] = {}
    for page_number in range(doc.page_count):
        page = doc[page_number]
        link_rects = [pymupdf.Rect(link["from"]) for link in page.get_links()]
        for block in page.get_text("dict")["blocks"]:
            for line in block.get("lines", []):
                for span in line["spans"]:
                    text = span["text"].strip()
                    if not text:
                        continue
                    face = span["font"].split("+", 1)[-1]
                    # Chrome embeds variable web fonts as unnamed Type3 fonts, one per
                    # instance; group them so the named (static or fallback) faces stand out.
                    if not face or face.startswith("Type3"):
                        face = "Type3 — variable web fonts"
                    font_chars[face] += len(text)
                    box = pymupdf.Rect(span["bbox"])
                    if not link_rects or box.is_empty:
                        continue
                    # Link text only when a link covers most of the span; a partial
                    # overlap is usually the body text running up to the link.
                    if max((abs(box & rect) for rect in link_rects), default=0) < 0.6 * abs(box):
                        continue
                    value = span["color"]
                    rgb = ((value >> 16) & 255, (value >> 8) & 255, value & 255)
                    entry = colors.setdefault("#%02X%02X%02X" % rgb, [0, contrast_on_white(rgb), text[:40]])
                    entry[0] += 1

    if pdf_fonts:
        total = sum(font_chars.values()) or 1
        print("  embedded fonts by share of text:")
        for name, count in sorted(font_chars.items(), key=lambda item: -item[1]):
            print(f"    {count / total:6.1%}  {name}")
    print("  link text colors (contrast against white only):")
    for hex_color, (count, ratio, sample) in sorted(colors.items(), key=lambda item: -item[1][0]):
        flag = "" if ratio >= 4.5 else "  ← below 4.5:1"
        print(f"    {hex_color}  {ratio:4.1f}:1 on white  ×{count:<3} e.g. {sample!r}{flag}")

    pages = parse_pages(preview, doc.page_count)
    if pages:
        out_dir = save_previews_atomically(doc, pdf_path, pages, dpi, lock_held=preview_lock_held)
        print(f"  previews: {out_dir}/page-NN.png for pages {preview}")


# --------------------------------------------------------------------------- commands


def convert(args: argparse.Namespace) -> None:
    from playwright.sync_api import Error as PlaywrightError
    from playwright.sync_api import PdfMargins
    from playwright.sync_api import sync_playwright

    source = Path(args.input).expanduser().resolve()
    if not source.exists():
        raise SystemExit(f"htmlpdf: no such file {source}")
    output = Path(args.output).expanduser().resolve() if args.output else source.with_suffix(".pdf")

    paper_w, paper_h = PAPER_INCHES[args.paper.lower()]
    if args.landscape:
        paper_w, paper_h = paper_h, paper_w
    margins = parse_margins(args.margin)
    content_width = round(paper_w * 96 - length_px(margins["left"]) - length_px(margins["right"]))

    scale = args.scale
    layout_width = content_width
    if args.layout_width:
        # Lay the page out at a desktop width, then scale it onto the paper.
        layout_width = args.layout_width
        scale = max(0.1, min(2.0, content_width / layout_width))

    staged: Path | None = None
    if source.suffix.lower() in {".md", ".markdown"}:
        staged = stage_html(source, markdown_to_document(source))
    else:
        text = source.read_text(encoding="utf-8")
        if not re.search(r"<html[\s>]", text, re.IGNORECASE):
            staged = stage_html(source, wrap_fragment(text))
    load = staged or source

    link_color = None if args.link_color == "keep" else args.link_color
    chrome = find_chrome(args.chrome)
    timeout_ms = args.timeout * 1000
    mermaid = {"rendered": 0, "reoriented": 0}

    try:
        with sync_playwright() as playwright:
            try:
                if chrome:
                    browser = playwright.chromium.launch(
                        headless=True,
                        args=["--font-render-hinting=none"],
                        executable_path=chrome,
                    )
                else:
                    browser = playwright.chromium.launch(headless=True, args=["--font-render-hinting=none"])
            except PlaywrightError as error:
                raise SystemExit(
                    f"htmlpdf: could not start Chrome ({error}). Install Google Chrome, set HTMLPDF_CHROME, "
                    "or run `poetry run playwright install chromium`."
                ) from error
            try:
                context = browser.new_context(
                    viewport={"width": layout_width, "height": 1200},
                    device_scale_factor=2,
                    color_scheme="light",
                    reduced_motion="reduce",
                )
                page = context.new_page()
                page.goto(load.as_uri(), wait_until="networkidle", timeout=timeout_ms)
                page.evaluate(WAIT_JS)

                if page.evaluate(NEEDS_MERMAID_JS):
                    try:
                        with mermaid_script_tag(args.mermaid_url) as script_tag:
                            page.add_script_tag(**script_tag)
                        mermaid = page.evaluate(
                            RENDER_MERMAID_JS, {"config": MERMAID_CONFIG, "reorient": not args.keep_diagram_direction}
                        )
                    except PlaywrightError as error:
                        print(f"htmlpdf: warning — Mermaid diagrams left as source ({error})", file=sys.stderr)
                if args.wait_for:
                    page.wait_for_selector(args.wait_for, timeout=timeout_ms)
                page.wait_for_timeout(args.settle)

                page.emulate_media(media="print", color_scheme="light", reduced_motion="reduce")
                page.add_style_tag(content=print_css(link_color))
                report = page.evaluate(
                    NORMALIZE_JS,
                    {
                        "forceLight": not args.keep_theme,
                        "hide": args.hide,
                        "minZoom": args.min_zoom,
                        "reflowMinHeight": args.reflow_min_height,
                    },
                )
                page.wait_for_timeout(150)

                fonts = browser_font_report(page)
                contents = None if args.bookmarks != "auto" else page.evaluate(TOC_JS, args.toc_selector)
                title = args.title or page.title() or source.stem
                footer = (
                    '<div style="box-sizing:border-box;width:100%;'
                    f'padding:0 {margins["right"]} 0 {margins["left"]};'
                    f'font:7.5px {SANS_STACK};color:#6B7785;display:flex;justify-content:space-between;">'
                    f"<span>{html.escape(args.footer if args.footer is not None else title)}</span>"
                    '<span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>'
                )
                pdf_bytes = page.pdf(
                    width=f"{paper_w}in",
                    height=f"{paper_h}in",
                    margin=cast(PdfMargins, margins),
                    print_background=True,
                    display_header_footer=not args.no_footer,
                    header_template="<span></span>",
                    footer_template=footer,
                    prefer_css_page_size=False,
                    outline=True,
                    tagged=True,
                    scale=scale,
                )
            finally:
                browser.close()
    finally:
        if staged and not args.keep_html:
            staged.unlink(missing_ok=True)

    doc = pymupdf.open(stream=pdf_bytes, filetype="pdf")
    toc: list[list]
    unmatched: list[str]
    origin: str
    if args.bookmarks == "none":
        toc, unmatched, origin = [], [], "none"
    elif contents:
        toc, unmatched = outline_from_contents(doc, contents)
        origin = "the document's contents list"
    else:
        toc, unmatched, origin = outline_from_headings(doc, args.depth), [], "headings"
    doc.set_toc(toc, collapse=9)
    if toc:
        doc.set_pagemode("UseOutlines")
    metadata = doc.metadata or {}
    metadata.update({"title": title, "creator": "htmlpdf", "producer": "Chrome via Playwright + PyMuPDF"})
    if args.subject:
        metadata["subject"] = args.subject
    if args.author:
        metadata["author"] = args.author
    doc.set_metadata(metadata)
    output.parent.mkdir(parents=True, exist_ok=True)
    with preview_directory_lock(output.with_name(f"{output.stem}-preview")):
        save_pdf_atomically(doc, output)
        audit(output, args.preview, args.dpi, pdf_fonts=False, preview_lock_held=True)

    orientation = " landscape" if args.landscape else ""
    prepared = ", ".join(f"{key} {value}" for key, value in report.items() if value) or "nothing needed"
    print(f"htmlpdf: {source.name} → {output}")
    print(f"  chrome: {chrome or 'Playwright bundled Chromium'}")
    print(f"  paper: {args.paper}{orientation}, layout width {layout_width}px, scale {scale:.2f}, margins {margins}")
    print(f"  prepared for print: {prepared}")
    if mermaid["rendered"]:
        print(f"  mermaid: {mermaid['rendered']} rendered, {mermaid['reoriented']} redrawn top-to-bottom to fit")
    print(f"  bookmarks from {origin}{'; UNMATCHED: ' + ', '.join(unmatched) if unmatched else ''}")
    total_glyphs = sum(count for _family, count, _web in fonts) or 1
    print("  fonts Chrome rendered (share of glyphs):")
    for family, count, is_web in fonts[:8]:
        kind = "web font" if is_web else "system font — check it is intended"
        print(f"    {count / total_glyphs:6.1%}  {family}  ({kind})")


def inspect(args: argparse.Namespace) -> None:
    pdf_path = Path(args.pdf).expanduser().resolve()
    preview = pdf_path.with_name(f"{pdf_path.stem}-preview")
    with preview_directory_lock(preview):
        audit(pdf_path, args.preview, args.dpi, preview_lock_held=True)


def main() -> None:
    parser = argparse.ArgumentParser(prog="htmlpdf", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    c = sub.add_parser("convert", help="HTML or Markdown → PDF")
    c.add_argument("input", help=".html/.htm (full document or fragment) or .md/.markdown")
    c.add_argument("-o", "--output", help="PDF path (default: next to the input)")
    c.add_argument("--paper", default="letter", choices=sorted(PAPER_INCHES), help="page size (default letter)")
    c.add_argument("--landscape", action="store_true")
    c.add_argument("--margin", default="14mm,14mm,16mm,14mm", help="top,right,bottom,left (default 14mm,14mm,16mm,14mm)")
    c.add_argument("--scale", type=float, default=1.0, help="Chrome print scale 0.1–2 (default 1)")
    c.add_argument("--layout-width", type=int,
                   help="lay the page out this many CSS px wide, then scale onto the paper (for desktop-only layouts)")
    c.add_argument("--title", help="PDF title and footer text (default: the page <title>)")
    c.add_argument("--footer", help="footer text (default: title); page numbers are always shown")
    c.add_argument("--no-footer", action="store_true", help="omit the footer and page numbers")
    c.add_argument("--subject")
    c.add_argument("--author")
    c.add_argument("--link-color", default=DEFAULT_LINK_COLOR, help=f"print link color, or 'keep' (default {DEFAULT_LINK_COLOR})")
    c.add_argument("--keep-theme", action="store_true", help="do not force the page's light theme")
    c.add_argument("--hide", action="append", default=[], help="CSS selector to drop from the PDF (repeatable)")
    c.add_argument("--bookmarks", default="auto", choices=["auto", "headings", "none"],
                   help="auto: mirror the page's contents list if it has one, else headings")
    c.add_argument("--toc-selector", help="CSS selector of the contents list to mirror (default: auto-detect)")
    c.add_argument("--depth", type=int, default=3, help="heading depth for heading bookmarks (default 3)")
    c.add_argument("--wait-for", help="CSS selector that must exist before printing (e.g. a chart's canvas)")
    c.add_argument("--settle", type=int, default=400, help="extra milliseconds for scripted content (default 400)")
    c.add_argument("--timeout", type=int, default=90, help="seconds for load and waits (default 90)")
    c.add_argument("--min-zoom", type=float, default=0.55, help="smallest scale for over-wide tables (default 0.55)")
    c.add_argument("--reflow-min-height", type=int, default=240,
                   help="re-flow single-column grids taller than this many px (default 240; 100000 disables)")
    c.add_argument("--keep-diagram-direction", action="store_true",
                   help="never redraw wide left-to-right Mermaid flowcharts top-to-bottom")
    c.add_argument("--mermaid-url", help="load Mermaid from this URL instead of the bundled runtime")
    c.add_argument("--chrome", help="Chrome/Chromium executable (default: auto-detect)")
    c.add_argument("--keep-html", action="store_true", help="keep the invocation-specific staged HTML beside the input")
    c.add_argument("--preview", default="1", help="pages to render as PNG after conversion: 1,3-4 | all | none")
    c.add_argument("--dpi", type=int, default=110)
    c.set_defaults(func=convert)

    i = sub.add_parser("inspect", help="audit an existing PDF")
    i.add_argument("pdf")
    i.add_argument("--preview", default="1")
    i.add_argument("--dpi", type=int, default=110)
    i.set_defaults(func=inspect)

    argv = sys.argv[1:]
    if argv and argv[0] not in {"convert", "inspect", "-h", "--help"}:
        argv = ["convert", *argv]
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
