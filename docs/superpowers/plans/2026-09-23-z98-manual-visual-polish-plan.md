# Z98 Manual — Visual/UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Volume I manual site centered, legible, contrast-separated, B/W + 256-color + 16-bit-display safe, with block-distinct code and image nav buttons at the page end.

**Architecture:** A single CSS pair carries the palette/typography/layout; the 28 pages get a uniform, hand-edited markup wave (centered fixed-width table, updated presentational baseline colors, the language bar moved above the layout table, and rollover GIF nav buttons above the text footer); the existing GIF/XBM asset set is regenerated in the new palette.

**Spec:** the operator-approved design (chat, 2026-09-23) + `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` §4/§6/§7 (page tree, restrictions, figures).

## Global Constraints

- **Website only** — all changes under `docs/sf/manuals/**`; never `sf/src/**`, `scripts/**`, `repro/**`, `release/seed/**`.
- **No compression** during the build; **STOP** on any issue/confusion; operator is the sole authority.
- **Era constraints (spec §6):** HTML 4.0 Transitional in the 3.2/4.0 intersection; **no HTML5 structural tags**; **no `<div>`** for structure; ISO-8859-1 (ASCII-only bytes); baseline appearance via presentational attributes; CSS1 only, external `z98.css`/`z98-print.css`, **no inline `<style>`**; only `<script src="doc.js">`; **GIF only** (+ the 1-bit XBM alternates under `gfx/xbm/`); no external resources.
- **Luminance hierarchy (B/W-safe):** the palette below is luminance-separated; links stay **underlined**.
- **16-bit-safe:** every colour channel is a multiple of 8 (5-6-5 rounding + 8-bit palettes are lossless for these values).
- **No-CSS baseline:** with both stylesheets removed every page remains legible, navigable, correctly ordered.
- **Edits via `edit`/`fastedit` only** (`docs/sf/AGENTS.md` §X.7: re-read the region before each edit; edit bottom-to-top; insert-before = replace the anchor line with new content + the original line verbatim). No bulk/sed/python transforms.
- Every binary wrapped in `timeout 120`; never `pkill`/`kill`/`killall`.
- `check.sh` and `build.sh` must be green and `build.sh` idempotent after every task.

### Palette (Option 2, approved)

| role | value |
|---|---|
| body bg / text | `#FFFFF0` / `#000000` |
| sidebar bg / text | `#C8C0A0` / `#000000` |
| sidebar + code border / h2 rule | `#A09878` |
| code (pre/tt) bg | `#F8F0D8` |
| links / visited | `#000080` / `#800080` (underlined) |
| headings h1/h2 | `#003366` |
| callout hues (keep, nudged to ×8) | `#FFFFCC` `#E0F0E0` `#FFE8CC` `#FFD8D8` `#E8E0E0` |

### Typography / layout

- body 12pt serif; `pre` 10pt monospace; sidebar 10pt (via `.sidebar font`), `line-height: 1.35`.
- h1 26pt, h2 20pt (+ `border-bottom: 1px solid #A09878; padding-bottom: 2pt`), h3 15pt, h4 12pt — all bold with real top/bottom margins.
- `pre { background-color: #F8F0D8; border: 1px solid #A09878; padding: 6pt; margin-top/bottom: 6pt; }`; `tt { background-color: #F8F0D8; }`.
- Layout table: `width="760" align="center"` (was `width="100%"`).
- Language bar: a full-width bar **above** the layout table (moved out of the 160px sidebar).
- Bottom nav: `Prev` / `Contents` / `Next` rollover GIF buttons **above** the existing text footer.

---

### Task 1: CSS pair (palette + typography + layout)

**Files:** Modify `docs/sf/manuals/en/z98.css`, `docs/sf/manuals/en/z98-print.css`.

- [ ] **Step 1:** Rewrite `z98.css` with the palette + typography/`pre`/`tt`/`.sidebar`/`.langbar`/`.placeholder` rules above (CSS1 only; hex colours only — the checker rejects `rgb(`/`rgba(`).
- [ ] **Step 2:** Update `z98-print.css`: black-on-white overrides (`body { color: #000000; background-color: #ffffff; }`, `pre { background-color: #ffffff; border: 1px solid #000000; }`), keep the existing sidebar/langbar hiding and `pre` border rule.
- [ ] **Step 3:** Verify: `bash docs/sf/manuals/check.sh` OK; `build.sh` idempotent; no forbidden tokens (CSS2/3, `page-break`, `@media`, `rgba?\(`).
- [ ] **Step 4:** Commit `style(manual): apply the option-2 palette and typography`.

### Task 2: Page markup wave (28 pages)

**Files:** every `docs/sf/manuals/*.html` and `docs/sf/manuals/en/*.html` (28 pages).

- [ ] **Step 1:** Outer layout table `width="100%" cellpadding="0" cellspacing="0" border="0"` → `width="760" align="center" cellpadding="0" cellspacing="0" border="0"` (line ~17 of each page; do not touch inner tables).
- [ ] **Step 2:** Update the presentational baseline: `<body bgcolor="#f5f0e1" text="#000000" link="#003366" vlink="#551a8b" alink="#cc0000">` → `bgcolor="#fffff0" text="#000000" link="#000080" vlink="#800080" alink="#800080"`; the sidebar td `bgcolor="#e8e0cc"` → `#c8c0a0`; the langbar table `bgcolor="#e8e0cc"` → `#c8c0a0`.
- [ ] **Step 3:** Move the language-bar block (the `<table … class="langbar">…</table>` inside the sidebar cell) to a full-width bar **immediately before** the layout table; keep `class="langbar"`, the same content, `align="right"`, and set its table `width="100%"`.
- [ ] **Step 4:** Add the bottom nav buttons immediately **before** the existing text footer paragraph: three links, each `<a href="…"><img src="gfx/btn-prev.gif" width="88" height="24" border="0" alt="Previous" onmouseover="swap(this)" onmouseout="swap(this)"></a>` etc. — `btn-prev` → the page's `rel="prev"` target, `btn-index` → `toc.html`, `btn-next` → the page's `rel="next"` target; separated by two non-breaking spaces.
- [ ] **Step 5:** Verify per page: `check.sh` OK (whole set); `build.sh` idempotent; ASCII-only; no `<div>`/inline style/new external refs; the no-CSS baseline intact.
- [ ] **Step 6:** Commit `style(manual): center the layout, move the language bar, add nav buttons`.

### Task 3: GIF + XBM regeneration (Option 2 palette)

**Files:** `docs/sf/manuals/en/gfx/*.gif`, `docs/sf/manuals/en/gfx/xbm/*.xbm`.

- [ ] **Step 1:** Regenerate the 12 button GIFs (88×24, GIF89a, same names): normal `btn-<name>.gif` = `#C8C0A0` bg + `#003366` label; over/highlighted `btn-<name>-over.gif` = `#003366` bg + `#FFFFF0` label (the approved rollover effect). Names: `home prev next up index search`.
- [ ] **Step 2:** Regenerate `logo.gif` (240×48, `#003366` bg + `#FFFFF0` text), `bullet.gif` (8×8 `#003366`), `navrule.gif` (150×8, `#A09878` bg + `#000000` line), and the 6 icons (16×16: `#FFFFCC`/`#E0F0E0`/`#FFE8CC`/`#FFD8D8`/`#E8E0E0` backgrounds, letters N/T/W/C/E/H).
- [ ] **Step 3:** Regenerate the 12 XBM alternates (1-bit, 88×24, same names, matching geometry).
- [ ] **Step 4:** Verify with ImageMagick (`identify`): every size/format exact; GIF89a; no PNG/SVG anywhere.
- [ ] **Step 5:** Commit `style(manual): regenerate the gif/xbm assets in the option-2 palette`.

### Task 4: Hygiene + whole-set verification

**Files:** the manual tree; `docs/superpowers/plans/2026-09-23-z98-manual-visual-polish-plan.md` (progress notes).

- [ ] **Step 1:** Move the three operator screenshots (`docs/sf/manuals/vol1a.png|vol1b.png|vol1c.png`) out of the tree to `/tmp/manual_screens/`.
- [ ] **Step 2:** Whole-set gates: `check.sh` OK (28 pages); `build.sh` twice → byte-identical `en/search-data.js`; `serve.sh` serves a page; all pages ASCII-only; no-CSS baseline; figures/rows 1:1 unchanged.
- [ ] **Step 3:** Palette verification: a grayscale luminance check of the palette (body/sidebar/code/text/links distinct) and the ×8 channel check.
- [ ] **Step 4:** Commit `style(manual): visual-polish closeout — verification sweep`.

---

## Self-Review

- **Coverage:** centering (T2.1), sidebar size (T1), contrast/palette (T1+T2.2+T3), headings (T1), code background (T1), nav buttons (T2.4+T3.1), language bar (T2.3), GIF regeneration (T3), hygiene (T4.1).
- **Placeholders:** none; every value is exact above.
- **Consistency:** the palette table is the single source; T2's attributes and T3's GIF fills use the same values.
- **Risks the tasks must verify (STOP if they fail):** `check.py` rejects a CSS token we need (then STOP and present); re-tinting GIFs changes geometry (then STOP); any page becomes non-ASCII (then STOP).

### Task 5: Style the entry pages + static-openability note

**Files:** Modify `docs/sf/manuals/index.html`, `docs/sf/manuals/readme.html`, `docs/sf/manuals/todo-figures-list.html`, `docs/sf/manuals/README.md`.

- [ ] **Step 1:** Add the two stylesheet links to the 3 root pages, immediately before the existing `<script type="text/javascript" src="en/doc.js"></script>` line: `<link rel="stylesheet" type="text/css" href="en/z98.css">` and `<link rel="stylesheet" type="text/css" href="en/z98-print.css" media="print">` — so the entry page matches the manual's look (it currently loads only `doc.js`).
- [ ] **Step 2:** In `docs/sf/manuals/README.md`, state that the site is fully static: double-click `index.html` (or `en/index.html`) — no server needed; `serve.sh` is only a local-preview convenience.
- [ ] **Step 3:** Verify: `bash docs/sf/manuals/check.sh` → `OK - 28 HTML pages…`; ASCII-only; **no** new root-relative/absolute/external `href`/`src`; `build.sh` on a copy twice → `en/search-data.js` byte-stable; the no-CSS baseline still holds.
- [ ] **Step 4:** Commit `style(manual): style the entry pages and note the static workflow`.
