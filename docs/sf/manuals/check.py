#!/usr/bin/env python3
"""Mechanical validator for the Z98 manual static site.

Python 3 standard library only; no network. Exits nonzero on the first
failure and names the offending file. Checks, in order:

  1. every local href/src resolves to an existing file;
  2. every en/ page carries rel=home/up/prev/next;
  3. the language bar links only to shipped language roots;
  4. lang="en" and the ISO-8859-1 charset meta are present;
  5. the forbidden list (HTML5 tags, <div>, PNG/SVG/web fonts, http(s):// in
     href/src, inline <style>, <script src> other than doc.js, and CSS2/CSS3
     tokens in the two stylesheets);
  6. the figure-placeholder 1:1 match with todo-figures-list.html;
  7. the no-CSS baseline (heading and prev/contents/next footer survive with
     the stylesheet links stripped).

Controller rulings honoured: R1 search-data.js, R2 the style guide's example
placeholder, R3 parsed-tag scanning that skips <pre> and escaped entities,
R4 the generated dist/ tree.
"""

import os
import re
import sys
from collections import Counter
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.abspath(__file__))
DIST_DIR = os.path.abspath(os.path.join(ROOT, "dist"))
FIGURE_LIST = "todo-figures-list.html"
FIGURE_SCAN_EXCLUDE = frozenset(("en/vol4-24-html-style.html",))
CSS_FILES = ("en/z98.css", "en/z98-print.css")
SHIPPED_LANGS = frozenset(("en",))

HTML5_TAGS = frozenset((
    "section", "article", "nav", "header", "footer", "main", "figure",
))
FORBIDDEN_ASSET_EXT = (".png", ".svg", ".woff", ".woff2", ".ttf", ".otf", ".eot")
CSS_FORBIDDEN = (
    ("page-break", r"page-break"),
    ("position:", r"position\s*:"),
    ("flex", r"\bflex\b"),
    ("grid", r"\bgrid\b"),
    ("@media", r"@media"),
    ("@font-face", r"@font-face"),
    (":nth", r":nth"),
    (":hover", r":hover"),
    ("rgb(", r"rgba?\("),
    ("@import", r"@import"),
)

FIGURE_RE = re.compile(
    r"Figure\s+([A-Za-z0-9][A-Za-z0-9._-]*)\s*"
    r"(?:&mdash;|\u2014|--|\u2013)\s*Win9x screenshot pending",
    re.IGNORECASE,
)
LANG_ROOT_RE = re.compile(r"^(?:\.\./|/)*([a-z]{2}(?:-[a-z]{2})?)/")
SCHEME_RE = re.compile(r"^[a-z][a-z0-9+.-]*:", re.IGNORECASE)
LINK_TAG_RE = re.compile(r"<link\b[^>]*>", re.IGNORECASE)
REL_STYLESHEET_RE = re.compile(r"""rel\s*=\s*["']?stylesheet""", re.IGNORECASE)
FOOTER_RE = re.compile(r"<p>\s*Previous:.*?Next:", re.IGNORECASE | re.DOTALL)
CONTENTS_LINK_RE = re.compile(r"<a\b[^>]*>\s*Contents\s*</a>", re.IGNORECASE)


class CheckError(Exception):
    pass


def fail(path, message):
    raise CheckError("%s: %s" % (path, message))


def relpath(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


class PageParser(HTMLParser):
    def __init__(self):
        HTMLParser.__init__(self, convert_charrefs=True)
        self.start_tags = []
        self.links = []
        self.tables = []
        self.text = []
        self.has_html = False
        self.has_head = False
        self.has_body = False
        self.h1_count = 0
        self.style_count = 0
        self._pre_depth = 0
        self._table_stack = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        line = self.getpos()[0]
        if tag == "pre":
            self._pre_depth += 1
            return
        if self._pre_depth > 0:
            return
        self.start_tags.append((tag, attrs, line))
        for name, value in attrs.items():
            if name in ("href", "src") and value is not None:
                self.links.append((name, value, line))
        if tag == "html":
            self.has_html = True
        elif tag == "head":
            self.has_head = True
        elif tag == "body":
            self.has_body = True
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "style":
            self.style_count += 1
        if tag == "table":
            self._table_stack.append([attrs, line, []])

    def handle_endtag(self, tag):
        if tag == "pre":
            if self._pre_depth > 0:
                self._pre_depth -= 1
            return
        if self._pre_depth > 0:
            return
        if tag == "table" and self._table_stack:
            attrs, line, text = self._table_stack.pop()
            self.tables.append((attrs, line, "".join(text)))

    def handle_data(self, data):
        if self._pre_depth > 0:
            return
        self.text.append(data)
        for frame in self._table_stack:
            frame[2].append(data)


class RowParser(HTMLParser):
    def __init__(self):
        HTMLParser.__init__(self, convert_charrefs=True)
        self.rows = []
        self._row = None
        self._cell = None
        self._tbody_depth = 0

    def handle_starttag(self, tag, attrs):
        if tag == "tbody":
            self._tbody_depth += 1
        elif tag == "tr" and self._tbody_depth > 0:
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []

    def handle_endtag(self, tag):
        if tag == "tbody":
            if self._tbody_depth > 0:
                self._tbody_depth -= 1
        elif tag in ("td", "th") and self._cell is not None:
            if self._row is not None:
                self._row.append((tag, "".join(self._cell).strip()))
            self._cell = None
        elif tag == "tr" and self._row is not None:
            if any(kind == "td" for kind, _ in self._row):
                self.rows.append([text for _, text in self._row])
            self._row = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell.append(data)


def iter_html_pages():
    pages = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        if os.path.abspath(dirpath) == DIST_DIR:
            dirnames[:] = []
            continue
        for name in filenames:
            if name.endswith(".html"):
                pages.append(os.path.join(dirpath, name))
    pages.sort()
    return pages


def parse_pages(paths):
    parsed = []
    for path in paths:
        with open(path, "r", encoding="latin-1") as handle:
            raw = handle.read()
        parser = PageParser()
        try:
            parser.feed(raw)
            parser.close()
        except Exception as exc:
            fail(relpath(path), "does not parse: %s" % exc)
        parsed.append((path, raw, parser))
    return parsed


def check_links(parsed):
    for path, _raw, page in parsed:
        name = relpath(path)
        for attr, value, line in page.links:
            target = value.strip()
            if not target or target.startswith("#"):
                continue
            if target.lower().startswith("mailto:"):
                continue
            if SCHEME_RE.match(target):
                continue
            local = target.split("#", 1)[0].split("?", 1)[0]
            if not local:
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), local))
            if not os.path.exists(resolved):
                fail(name, "line %d: %s=%r does not resolve" % (line, attr, value))


def check_rel(parsed):
    for path, _raw, page in parsed:
        name = relpath(path)
        if not name.startswith("en/"):
            continue
        rels = set()
        for tag, attrs, _line in page.start_tags:
            if tag == "link" and attrs.get("rel"):
                rels.add(attrs["rel"].strip().lower())
        for needed in ("home", "up", "prev", "next"):
            if needed not in rels:
                fail(name, 'missing <link rel="%s">' % needed)


def check_langbar(parsed):
    for path, _raw, page in parsed:
        name = relpath(path)
        for _attr, value, line in page.links:
            target = value.strip().split("#", 1)[0].split("?", 1)[0]
            match = LANG_ROOT_RE.match(target)
            if match and match.group(1) not in SHIPPED_LANGS:
                fail(
                    name,
                    "line %d: language bar links to unshipped language %r"
                    % (line, match.group(1)),
                )


def check_lang_charset(parsed):
    for path, _raw, page in parsed:
        name = relpath(path)
        html_tag = None
        for tag, attrs, _line in page.start_tags:
            if tag == "html":
                html_tag = attrs
                break
        if html_tag is None:
            fail(name, "missing <html> element")
        if (html_tag.get("lang") or "").strip().lower() != "en":
            fail(name, 'missing lang="en" on <html>')
        charset_ok = False
        for tag, attrs, _line in page.start_tags:
            if tag != "meta":
                continue
            equiv = (attrs.get("http-equiv") or "").strip().lower()
            content = (attrs.get("content") or "").lower()
            if equiv == "content-type" and "charset=iso-8859-1" in content:
                charset_ok = True
                break
        if not charset_ok:
            fail(name, "missing ISO-8859-1 charset <meta>")


def check_forbidden(parsed):
    for path, _raw, page in parsed:
        name = relpath(path)
        for tag, attrs, line in page.start_tags:
            if tag in HTML5_TAGS:
                fail(name, "line %d: forbidden HTML5 tag <%s>" % (line, tag))
            if tag == "div":
                fail(name, "line %d: forbidden <div>" % line)
            if tag == "style":
                fail(name, "line %d: forbidden inline <style>" % line)
            if tag == "script":
                src = attrs.get("src")
                if src is None:
                    continue
                base = os.path.basename(src)
                allowed = base == "doc.js"
                if not allowed and name == "en/search.html" and base == "search-data.js":
                    allowed = True
                if not allowed:
                    fail(name, "line %d: forbidden <script src=%r>" % (line, src))
        for attr, value, line in page.links:
            low = value.strip().lower()
            if low.startswith("http://") or low.startswith("https://"):
                fail(name, "line %d: external %s=%r" % (line, attr, value))
            bare = low.split("#", 1)[0].split("?", 1)[0]
            for ext in FORBIDDEN_ASSET_EXT:
                if bare.endswith(ext):
                    fail(name, "line %d: forbidden asset %s=%r" % (line, attr, value))


def check_css():
    for name in CSS_FILES:
        path = os.path.join(ROOT, name)
        if not os.path.exists(path):
            fail(name, "missing stylesheet")
        with open(path, "r", encoding="latin-1") as handle:
            text = handle.read()
        for label, pattern in CSS_FORBIDDEN:
            if re.search(pattern, text, re.IGNORECASE):
                fail(name, "forbidden CSS2/CSS3 token %r" % label)


def figure_key(value):
    match = re.search(r"([0-9]+)", value)
    if match:
        return match.group(1)
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def read_todo_rows():
    path = os.path.join(ROOT, FIGURE_LIST)
    if not os.path.exists(path):
        fail(FIGURE_LIST, "missing figure list")
    with open(path, "r", encoding="latin-1") as handle:
        raw = handle.read()
    parser = RowParser()
    parser.feed(raw)
    parser.close()
    return parser.rows


def check_figures(parsed):
    placeholders = []
    for path, _raw, page in parsed:
        name = relpath(path)
        if name in FIGURE_SCAN_EXCLUDE:
            continue
        for attrs, line, text in page.tables:
            classes = (attrs.get("class") or "").split()
            if "placeholder" not in classes:
                continue
            match = FIGURE_RE.search(text)
            if match:
                placeholders.append((name, figure_key(match.group(1)), line))

    rows = read_todo_rows()
    row_keys = []
    for row in rows:
        if len(row) < 2:
            fail(FIGURE_LIST, "figure row has fewer than two columns")
        row_keys.append(figure_key(row[1]))

    page_counts = Counter(key for _name, key, _line in placeholders)
    row_counts = Counter(row_keys)
    problems = []
    for key, count in sorted((page_counts - row_counts).items()):
        pages = sorted({name for name, k, _l in placeholders if k == key})
        problems.append(
            "placeholder Figure %s on %s has no matching row (x%d)"
            % (key, ", ".join(pages), count)
        )
    for key, count in sorted((row_counts - page_counts).items()):
        problems.append(
            "%s row Figure %s has no matching placeholder (x%d)"
            % (FIGURE_LIST, key, count)
        )
    if problems:
        raise CheckError("figure 1:1 check: " + "; ".join(problems))


def strip_stylesheets(raw):
    def replace(match):
        tag = match.group(0)
        if REL_STYLESHEET_RE.search(tag):
            return ""
        return tag

    return LINK_TAG_RE.sub(replace, raw)


def check_nocss(parsed):
    for path, raw, _page in parsed:
        name = relpath(path)
        stripped = strip_stylesheets(raw)
        parser = PageParser()
        try:
            parser.feed(stripped)
            parser.close()
        except Exception as exc:
            fail(name, "does not parse without stylesheets: %s" % exc)
        if not (parser.has_html and parser.has_head and parser.has_body):
            fail(name, "missing html/head/body without stylesheets")
        if parser.h1_count < 1:
            fail(name, "missing <h1> without stylesheets")
        if not FOOTER_RE.search(stripped):
            fail(name, "missing prev/contents/next footer without stylesheets")
        if not CONTENTS_LINK_RE.search(stripped):
            fail(name, "missing Contents link without stylesheets")


def main():
    pages = iter_html_pages()
    if not pages:
        fail(".", "no HTML pages found under %s" % ROOT)
    parsed = parse_pages(pages)
    check_links(parsed)
    check_rel(parsed)
    check_langbar(parsed)
    check_lang_charset(parsed)
    check_forbidden(parsed)
    check_css()
    check_figures(parsed)
    check_nocss(parsed)
    print("check.py: OK - %d HTML pages, links, rel, lang, forbidden list, figures, no-CSS baseline" % len(pages))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as exc:
        sys.stderr.write("check.py: FAIL: %s\n" % exc)
        sys.exit(1)
