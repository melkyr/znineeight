# Z98 Manual — Phase 0 (infrastructure + first slice) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Z98 manual as a local, offline, era-accurate static website under `docs/sf/manuals/`, and prove the pipeline end-to-end with three verified content pages (tutorial, mental-shift, reference) plus their example programs.

**Architecture:** One plan, fifteen tasks. Tasks 1–8 build the manual infrastructure (skeleton, CSS pair, `doc.js`, GIF assets, page template + style guide, `build.sh`, `check.sh`, `serve.sh` + tree README). Tasks 9–12 author the cross-archetype slice (hello tutorial, error-unions mental-shift, builtins reference, title/TOC/index/search wiring) with every example compile+run verified. Task 13 is the whole-set review, verification sweep, and closeout.

**AMENDMENT 1 (operator ruling 2026-09-20):** verifying Task 10 found a real compiler defect — `errdefer` bodies are dropped on explicit error returns (`return error.X;`), running only on `try` propagation. Per the operator, compiler correctness takes priority over the manual. **Task 10A (I, investigate)** and **Task 10B (F, fix)** were inserted before Task 11 and landed (fixed point `36c04ebf…`, seed v42). Task 10 was re-verified and committed.

**AMENDMENT 2 (operator ruling 2026-09-20):** Task 10's review found a second real compiler defect — the compiler accepts `break`/`continue`/`return` inside `defer`/`errdefer`, contradicting `docs/reference/Language_Spec_Z98.md` §3.1, and `errdefer { continue; }` swallows an explicit error return. **Task 10C (I, investigate)** and **Task 10D (F, fix)** were inserted after Task 10B and landed (fixed point `1c4f6765…`, seed v43; spec §3.1/§3.2 amended to Zig's scope-aware rule).

**AMENDMENT 3 (operator ruling 2026-09-20):** Task 11 found a third real compiler defect — `@floatCast` is accepted by the front end (`sf/src/semantic_analyzer.zig:306`) but never lowered (`sf/src/lower.zig` has no dispatch), emitting a poison-filled temp (silent miscompile). **Task 11A (I)** and **Task 11B (F)** are inserted before Task 11; together with 10A/10B/10C/10D they are the **only** tasks permitted to touch `sf/src`, add fixtures/repros, run the compiler gate battery, and rotate the seed. Task 11 stays BLOCKED until 11B lands. Except for Tasks 10A–10D and 11A/11B, the plan remains website-only.

**AMENDMENT 4 (operator ruling 2026-09-20):** the final whole-branch review found the `errdefer` fix (Task 10B) still misses the dynamic case — `return <error-union variable>;` where the source and destination error-union types are identical (`src==dst`, no coercion recorded) still drops `errdefer`, and Task 10 shipped that as a page Note. Spec §11 says "do not document around it", so the operator ruled to fix it. **Task 10E (I)** and **Task 10F (F)** are inserted after Task 10D; together with the other inserted pairs they are the only tasks permitted to touch `sf/src`, add fixtures/repros, run the compiler gate battery, and rotate the seed. After 10F, Task 10 gets a fix round to remove the page Note, and Task 13's closeout is re-run.

**AMENDMENT 5 (operator ruling 2026-09-20):** `@floatCast` (and `@intToFloat`) are not constant-folded by `comptime_eval.zig`, so a compile-time-known `@floatCast` cannot be used where a comptime value is required. The operator ruled this is a real gap that "can and should be corrected", not a documented limitation. **Task 11C (I)** and **Task 11D (F)** are inserted after Task 11B; together with the other inserted pairs they are the only tasks permitted to touch `sf/src`, add fixtures/repros, run the compiler gate battery, and rotate the seed. After 11D, Task 11's builtins page is re-verified for the fold claim. (11C found Z98's comptime-required positions are integer-only *today*; the operator ruled to fold anyway because "comptime-required positions will eventually include floats", with fixtures.)

**AMENDMENT 6 (operator ruling 2026-09-20):** Task 11C's investigation found a separate real defect — array sizes that use a builtin (`[@intCast(...)]`, `[@sizeOf(...)]`, `[@intToFloat(...)]`) hard-error `ERR_3050`, because `evalConstU32Full`/`evalConstI64Full` have no `builtin_call` arm. The operator ruled it must be addressed ("both are defects need addressing"). **Task 11E (I)** and **Task 11F (F)** are inserted after Task 11D; together with the other inserted pairs they are the only tasks permitted to touch `sf/src`, add fixtures/repros, run the compiler gate battery, and rotate the seed.

**AMENDMENT 7 (operator ruling 2026-09-20):** Task 11E found the fix is not uniform and surfaced a separate enum silent miscompile. Operator ruled: aim for **full** scope, but add an I task before each fix that is not crystal clear. So: **11F (F)** implements the clear integer-valued array-size builtins (`@intCast`, primitive/alias `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf`); **11G (I)** investigates struct introspection in array sizes and **11H (F)** fixes it (layout timing / `state == 2`); **11I (I)** investigates the `evalConstI64Full` enum silent miscompile (`enum(u8){A=1+2}` → A=0) and **11J (F)** fixes it. These four join the other inserted tasks in the scoped `sf/src` exception.

**AMENDMENT 8 (operator ruling 2026-09-20):** Task 11F's review surfaced two more defects, both valid Zig — (a) `@sizeOf(bool)`/`@alignOf(bool)` fold to 4 while Zig's `bool` is 1 byte/align 1; (b) `.len` on a struct-field array does not lower (`zT_N` undeclared). Operator ruled to plan I/F pairs for both. **11K (I) + 11L (F)** fix the bool size/align; **11M (I) + 11N (F)** fix the struct-field-array `.len`. Note: changing `bool` to 1 byte is an ABI/representation change — if 11K finds existing programs/tests depend on bool=4, STOP and present before changing it.

**AMENDMENT 9 (operator ruling 2026-09-20):** Task 11M found a separate defect — `for (0..s.a.len)` fails because `semanticAnalyzerResolveForHeader` resolves only `node.child_0` and `range_exclusive` returns `TYPE_U32` without resolving its children, so the range end is never resolved. Verified official Zig supports it (`for (0..5)` range syntax + `.len` expressions are documented), so this is a real defect, not an overextension. **11O (I) + 11P (F)** fix the for-range end expression. Operator standing instruction: for every defect, verify against official Zig before treating it as a defect (not an overextension).

**Tech Stack:** Hand-authored HTML 4.0 Transitional, CSS1, vanilla 1998-era JavaScript, GIF assets (generated with ImageMagick `convert`), Python 3 standard library for the checker, the seed-built `zig1` + `gcc -m32` for example verification, git.

**Spec:** `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md`.

**Sequence:** PREVIOUS plan: none (a new documentation program). NEXT plan: the first full-volume plan (Volume I), authored after this slice is reviewed.

## Global Constraints

- **Website only, with scoped exceptions (AMENDMENTS 1–17).** Do NOT edit `sf/src/**`, `scripts/**`, fixtures, or `release/seed/**` — EXCEPT Tasks 10A–10F and 11A–11U, which investigate and fix the compiler defects found while verifying the manual. Only those tasks may edit `sf/src/**`, add regression fixtures/repros, run the compiler gate battery, and rotate the seed. Every other task leaves the compiler fixed point and seed untouched.
- **All files under `docs/sf/manuals/`** except this plan/spec and the one `.gitignore` line that ignores `docs/sf/manuals/dist/`.
- **Blueprint-vs-reality rule (spec §3).** The manual documents the current compiler only. When a claim cannot be verified against `docs/reference/Language_Spec_Z98.md` and source, fix the page or drop the claim. Never ship an unreproducible claim.
- **HTML restrictions (spec §6.1).** HTML 4.0 Transitional doctype, authored in the HTML 3.2/4.0 intersection. No HTML5 structural tags (`<section>`, `<article>`, `<nav>`, `<header>`, `<footer>`, `<main>`, `<figure>`). **No `<div>` for structure** — layout uses `<table>`. ISO-8859-1 only, declared `<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">`. Baseline appearance via presentational attributes (`bgcolor`, `align`, `width`, `border`, `cellpadding`, `cellspacing`, `valign`) and `<font>`/`<b>`/`<i>`/`<center>`. Every page carries `<link rel="home|up|prev|next">`, a sidebar TOC, a language bar, and a prev/contents/next footer.
- **CSS restrictions (spec §6.2).** CSS1 only. `z98.css` (screen) and `z98-print.css` (print) are **external linked stylesheets**. **No inline `<style>` blocks.** CSS carries no meaning and no layout — with both stylesheets removed the site must remain legible, navigable, and correctly ordered. No CSS2/CSS3: no `page-break-before`/`page-break-after`, no `position`, no `@media` beyond `media="print"`, no web fonts. The print stylesheet is limited to `display: none` for navigation, a `pt` font size, and a hairline `border` on `<pre>`.
- **JS restrictions (spec §6.3).** One file `doc.js`, ≤ 2048 bytes, four functions (`swap`, `tocToggle`, `doSearch`, `preload`), no `document.write`, no browser sniffing; every feature degrades to working HTML.
- **Asset restrictions (spec §6.4).** GIF only — no PNG, no SVG, no web fonts. Logo 240×48, bullets 8×8, icons 16×16 (`note`, `tip`, `warn`, `caution`, `era`, `honest`), buttons 88×24 plus `-over` pairs, navrule 150×8. XBM alternates under `gfx/xbm/`.
- **Forbidden list (spec §6.5, checker-enforced).** HTML5 structural tags; `<div>` structure; PNG/SVG/web fonts; external resources (any `http://`/`https://` in `href`/`src`); inline `<style>`; `<script src>` other than `doc.js`; > 2048 bytes of JS; CSS2/CSS3 properties or selectors.
- **Figures (spec §7).** Terminal transcripts are AI-produced from real runs and rendered in `<pre>`. Win9x screenshots are reserved placeholder boxes plus an entry in `docs/sf/manuals/todo-figures-list.html`; `check.sh` enforces a 1:1 match.
- **Content verification (spec §8).** Every example is compiled with the seed-built `zig1` and `gcc -m32`, actually run, and its transcript matched to the prose; `-osw` claims run under `wine`; every syntax/builtin claim is cross-checked against `docs/reference/Language_Spec_Z98.md` and source.
- **English only.** The language bar lists only shipped languages (English).
- **Edits via `edit`/`fastedit` only**; no bulk transforms. Never stage `mnemoria/`, `.opencode/`, or `.zig1_*.tmp`.
- **STOP on a real compiler defect** found while verifying a claim — report it; do not fix `sf/src`, do not document around it. (The Task 10 `errdefer` defect triggered this rule and is handled by the inserted Tasks 10A/10B, not by a manual workaround.)

## Compiler under test (for example verification)

Build the seed compiler once per session (repo root, relative path required):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
```

Compile and run an example (the current emission recipe, `docs/sf/QUICK_REF.md` "User-facing emission + companion build scripts"):

```bash
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out docs/sf/manuals/src/<vol>/<prog>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

If the emitted script's argument order or default name differs, use the recipe in `docs/sf/QUICK_REF.md` verbatim. Capture stdout, stderr, and `rc` as the transcript.

---

## File Structure

**Create (infrastructure):**
- `docs/sf/manuals/index.html` — language selector.
- `docs/sf/manuals/readme.html` — what this is / how to read / colophon.
- `docs/sf/manuals/todo-figures-list.html` — pending Win9x screenshots.
- `docs/sf/manuals/en/index.html`, `readme.html`, `toc.html`, `search.html`, `search-data.js`
- `docs/sf/manuals/en/doc.js`, `z98.css`, `z98-print.css`
- `docs/sf/manuals/en/gfx/` (GIFs) and `en/gfx/xbm/` (XBM alternates)
- `docs/sf/manuals/en/vol4-24-html-style.html` — the HTML contract + copyable template
- `docs/sf/manuals/build.sh`, `check.sh`, `check.py`, `serve.sh`
- `docs/sf/manuals/README.md` — contributor/build README

**Create (slice):**
- `docs/sf/manuals/src/vol1/hello.z98`, `src/vol2/error_unions.z98`, `src/build_linux.sh`, `src/build_owc.bat`
- `docs/sf/manuals/en/vol1-00-title.html`, `vol1-05-first-program.html`
- `docs/sf/manuals/en/vol2-00-title.html`, `vol2-12-error-unions.html`
- `docs/sf/manuals/en/vol4-00-title.html`, `vol4-15-builtins.html`

**Modify:** `.gitignore` (add `docs/sf/manuals/dist/`).

**Reference (read-only):** `docs/sf/manuals/manuals_blueprint.txt` (Parts 3–7, 11), `docs/reference/Language_Spec_Z98.md`, `docs/reference/builtins.md`, `docs/sf/QUICK_REF.md`, `examples/z98/*`.

---

### Task 1: Manual tree skeleton + top-level pages

**Files:**
- Create: `docs/sf/manuals/index.html`, `docs/sf/manuals/readme.html`, `docs/sf/manuals/todo-figures-list.html`
- Create: `docs/sf/manuals/en/index.html`, `en/readme.html`, `en/toc.html`, `en/search.html`, `en/search-data.js`

**Interfaces:**
- Produces: the directory skeleton and the page set every later task writes into.

- [ ] **Step 1: Create the skeleton** — `en/`, `en/gfx/`, `en/gfx/xbm/`, `src/`, `dist/`.
- [ ] **Step 2: Write `index.html`** — the language selector: an HTML 3.2-style page with three links; English links to `en/index.html`, Spanish and Chinese shown as plain text marked "(not yet available)". Valid HTML 4.0 Transitional, ISO-8859-1, presentational attributes only.
- [ ] **Step 3: Write `readme.html`** — what the manual is, the reading paths from blueprint Part 1, and a colophon. Presentational attributes only.
- [ ] **Step 4: Write `todo-figures-list.html`** — a table with columns `Page | Figure | Caption | Claim | What to capture` and an empty tbody (the 1:1 check in Task 7 requires the table to exist).
- [ ] **Step 5: Write `en/` stubs** — `index.html` (title page, links to `toc.html`), `readme.html`, `toc.html` (master TOC listing the six volumes, with shipped pages linked and the rest marked "planned"), `search.html` (a form plus a noscript A-Z fallback linking `toc.html`), `search-data.js` (empty array placeholder: `var z98SearchData = [];`).
- [ ] **Step 6: Verify** — no HTML5 structural tags and no structural `<div>`: `grep -nE '<(section|article|nav|header|footer|main|figure)[ >]|<div[ >]' docs/sf/manuals/index.html docs/sf/manuals/readme.html docs/sf/manuals/todo-figures-list.html docs/sf/manuals/en/*.html` returns nothing.
- [ ] **Step 7: Commit** — `git add docs/sf/manuals && git commit -m "docs(manual): add the Z98 manual tree skeleton and top-level pages"`.

---

### Task 2: CSS pair (screen + print), CSS1 only

**Files:**
- Create: `docs/sf/manuals/en/z98.css`, `docs/sf/manuals/en/z98-print.css`

**Interfaces:**
- Consumes: the page skeleton from Task 1.
- Produces: `z98.css` and `z98-print.css`, linked by every later page.

- [ ] **Step 1: Write `z98.css`** — CSS1 only. Typography (`body { font-family: serif; }`, `pre { font-family: monospace; }`), link colors (`a:link`, `a:visited`), heading sizes in `pt`/`em`, and nothing that carries layout or meaning. No `position`, no `display`-based layout, no `float`-based page structure.
- [ ] **Step 2: Write `z98-print.css`** — CSS1 only: `display: none` for `.sidebar` and `.langbar`, a `pt` body font size, and `pre { border: 1px solid #000000; }`. **No `page-break-before`/`page-break-after`** (they are CSS2).
- [ ] **Step 3: Verify** — `grep -nE 'page-break|position:|flex|grid|@media|@font-face|:nth|:hover|rgba?\(' docs/sf/manuals/en/z98.css docs/sf/manuals/en/z98-print.css` returns nothing.
- [ ] **Step 4: Verify the no-CSS baseline by inspection** — every rule in both files is optional decoration; the pages from Task 1 use presentational attributes for all layout and color.
- [ ] **Step 5: Commit** — `git add docs/sf/manuals/en/z98.css docs/sf/manuals/en/z98-print.css && git commit -m "docs(manual): add the CSS1 screen and print stylesheets"`.

---

### Task 3: `doc.js`

**Files:**
- Create: `docs/sf/manuals/en/doc.js`

**Interfaces:**
- Produces: `swap(id)`, `tocToggle()`, `doSearch()`, `preload()` — the only JavaScript in the site.

- [ ] **Step 1: Write `doc.js`** — ≤ 2048 bytes, four functions: `swap(imgId)` for rollover images (swaps `src` to the `-over` GIF and back), `tocToggle()` to show/hide the sidebar TOC, `doSearch()` to filter `z98SearchData` into `search.html`, `preload()` to warm the `-over` GIFs. No `document.write`, no browser sniffing, no external calls.
- [ ] **Step 2: Verify** — `wc -c docs/sf/manuals/en/doc.js` ≤ 2048; `grep -nE 'document\.write|navigator\.|XMLHttpRequest|fetch\(' docs/sf/manuals/en/doc.js` returns nothing.
- [ ] **Step 3: Commit** — `git add docs/sf/manuals/en/doc.js && git commit -m "docs(manual): add the doc.js behaviour script"`.

---

### Task 4: GIF asset set

**Files:**
- Create: `docs/sf/manuals/en/gfx/logo.gif`, `bullet.gif`, `navrule.gif`, `icon-{note,tip,warn,caution,era,honest}.gif`, `btn-{home,prev,next,up,index,search}.gif`, `btn-{home,prev,next,up,index,search}-over.gif`
- Create: `docs/sf/manuals/en/gfx/xbm/` (XBM alternates of the button GIFs)

**Interfaces:**
- Produces: the asset set referenced by every later page.

- [ ] **Step 1: Generate the GIFs** with ImageMagick `convert` at the exact sizes (spec §6.4). Example commands:
  ```bash
  convert -size 240x48 xc:'#003366' -fill '#f5f0e1' -pointsize 20 -gravity center -annotate 0 'Z98 Manual' gfx/logo.gif
  convert -size 8x8   xc:'#003366' gfx/bullet.gif
  convert -size 150x8 xc:'#e8e0cc' -fill '#000000' -draw 'line 0,4 150,4' gfx/navrule.gif
  convert -size 16x16 xc:'#ffffcc' -fill '#003366' -pointsize 12 -gravity center -annotate 0 'N' gfx/icon-note.gif   # tip/warn/caution/era/honest likewise
  convert -size 88x24 xc:'#e8e0cc' -fill '#003366' -pointsize 12 -gravity center -annotate 0 'Home' gfx/btn-home.gif
  convert -size 88x24 xc:'#003366' -fill '#ffffff' -pointsize 12 -gravity center -annotate 0 'Home' gfx/btn-home-over.gif  # prev/next/up/index/search likewise
  ```
  Icons: `note`, `tip`, `warn`, `caution`, `era`, `honest` (the honesty icon gets the warmer background `#ece0e0`).
- [ ] **Step 2: Generate XBM alternates** — `for f in gfx/btn-*.gif; do convert "$f" "gfx/xbm/$(basename "${f%.gif}").xbm"; done`.
- [ ] **Step 3: Verify** — `file docs/sf/manuals/en/gfx/*.gif` shows GIF for every file; `identify -format '%f %wx%h\n' docs/sf/manuals/en/gfx/*.gif` matches the spec sizes; no PNG/SVG exists (`find docs/sf/manuals -name '*.png' -o -name '*.svg'` empty).
- [ ] **Step 4: Commit** — `git add docs/sf/manuals/en/gfx && git commit -m "docs(manual): add the GIF asset set and XBM alternates"`.

---

### Task 5: Page template + HTML style guide

**Files:**
- Create: `docs/sf/manuals/en/vol4-24-html-style.html`

**Interfaces:**
- Consumes: `z98.css`, `z98-print.css`, `doc.js`, the GIFs.
- Produces: the canonical page skeleton every later page copies.

- [ ] **Step 1: Write the page** — `vol4-24-html-style.html` documents the §6 restrictions in prose and contains, inside a `<pre>` block, the copyable skeleton:

```html
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN"
  "http://www.w3.org/TR/REC-html40/loose.dtd">
<html lang="en">
<head>
<title>Z98 Manual: &lt;TITLE&gt;</title>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
<meta name="generator" content="z98doc 0.1">
<meta name="keywords" content="&lt;KEYWORDS&gt;">
<link rel="stylesheet" type="text/css" href="z98.css">
<link rel="stylesheet" type="text/css" href="z98-print.css" media="print">
<link rel="home" href="index.html">
<link rel="up" href="toc.html">
<link rel="prev" href="&lt;PREV&gt;">
<link rel="next" href="&lt;NEXT&gt;">
</head>
<body bgcolor="#f5f0e1" text="#000000" link="#003366" vlink="#551a8b" alink="#cc0000">
<table width="100%" cellpadding="0" cellspacing="0" border="0">
<tr>
<td width="160" valign="top" bgcolor="#e8e0cc" class="sidebar">
  <!-- language bar + volume TOC -->
</td>
<td width="1" bgcolor="#000000"><img src="gfx/bullet.gif" width="1" height="1" alt=""></td>
<td valign="top">
  <h1>&lt;TITLE&gt;</h1>
  <!-- body -->
  <p>Previous: &lt;PREV&gt; | <a href="toc.html">Contents</a> | Next: &lt;NEXT&gt;</p>
</td>
</tr>
</table>
<script type="text/javascript" src="doc.js"></script>
</body>
</html>
```

- [ ] **Step 2: Document the conventions** — the admonition boxes (note/tip/warn/caution/honest, each a `<table>` with its icon), the terminal-transcript convention (`<pre>`), the Win9x figure placeholder convention (a dashed-border `<table>` with `Figure N — Win9x screenshot pending`), and the CSS/JS/asset rules.
- [ ] **Step 3: Verify** — no forbidden construct (Task 2 Step 3 grep plus the Task 1 Step 6 grep); `<link rel>` present; `lang="en"` and the charset meta present.
- [ ] **Step 4: Commit** — `git add docs/sf/manuals/en/vol4-24-html-style.html && git commit -m "docs(manual): add the page template and HTML style guide"`.

---

### Task 6: `build.sh`

**Files:**
- Create: `docs/sf/manuals/build.sh`
- Modify: `.gitignore` (add `docs/sf/manuals/dist/`)

**Interfaces:**
- Consumes: the whole `en/` tree.
- Produces: `dist/` (assembled site) and a regenerated `en/search-data.js`.

- [ ] **Step 1: Write `build.sh`** — bash, `set -e`, no network. It (a) clears and recreates `docs/sf/manuals/dist/`, (b) copies `index.html`, `readme.html`, `todo-figures-list.html`, and `en/` into `dist/`, (c) regenerates `en/search-data.js` by scanning `en/*.html` for `<title>`, `<meta name="keywords">`, and the first `<h1>`, emitting `var z98SearchData = [{file,title,keywords}, …];`, and (d) prints a summary count. Idempotent.
- [ ] **Step 2: Add the gitignore line** — append `docs/sf/manuals/dist/` to `.gitignore`.
- [ ] **Step 3: Verify** — run `bash docs/sf/manuals/build.sh`; assert `dist/en/index.html` and `dist/en/z98.css` exist; assert `en/search-data.js` is non-empty and syntactically valid (`python3 -c "import re,sys; s=open('docs/sf/manuals/en/search-data.js').read(); assert s.startswith('var z98SearchData')"`); run it twice and confirm the output is identical.
- [ ] **Step 4: Commit** — `git add docs/sf/manuals/build.sh .gitignore && git commit -m "docs(manual): add the site build script and ignore dist"`.

---

### Task 7: `check.sh` + `check.py` (validator)

**Files:**
- Create: `docs/sf/manuals/check.sh`, `docs/sf/manuals/check.py`

**Interfaces:**
- Consumes: the whole `docs/sf/manuals/` tree.
- Produces: `check.sh` — exits nonzero on the first failure; the mechanical gate for every later task.

- [ ] **Step 1: Write `check.py`** — Python 3 standard library only, no network. It parses every `*.html` under `docs/sf/manuals/` and asserts:
  1. Every local `href`/`src` resolves to an existing file.
  2. Every `en/` page has `rel="home"`, `rel="up"`, `rel="prev"`, `rel="next"`.
  3. The language bar links only to shipped languages.
  4. `lang="en"` and the ISO-8859-1 charset meta are present.
  5. The forbidden list (spec §6.5): no HTML5 structural tags, no `<div>` structure, no PNG/SVG/web fonts, no `http(s)://` in `href`/`src`, no inline `<style>`, no `<script src>` other than `doc.js`, no CSS2/CSS3 tokens in the CSS files.
  6. Every on-page `Figure N — Win9x screenshot pending` placeholder has exactly one matching row in `todo-figures-list.html`, and vice versa (1:1).
  7. The no-CSS baseline: with `<link rel="stylesheet">` tags stripped, each page still parses and contains its heading and footer.
- [ ] **Step 2: Write `check.sh`** — `exec python3 "$(dirname "$0")/check.py" "$@"`.
- [ ] **Step 3: Verify** — `bash docs/sf/manuals/check.sh` passes on the current tree. Then deliberately break one link in a scratch copy and confirm `check.sh` exits nonzero naming the file.
- [ ] **Step 4: Commit** — `git add docs/sf/manuals/check.sh docs/sf/manuals/check.py && git commit -m "docs(manual): add the link/HTML/figure validator"`.

---

### Task 8: `serve.sh` + contributor README

**Files:**
- Create: `docs/sf/manuals/serve.sh`, `docs/sf/manuals/README.md`

**Interfaces:**
- Consumes: the tree and the scripts.
- Produces: the local browsing entry point and the contributor guide.

- [ ] **Step 1: Write `serve.sh`** — `exec python3 -m http.server "${1:-8000}" --directory "$(dirname "$0")"`.
- [ ] **Step 2: Write `README.md`** — the tree layout, `build.sh`/`check.sh`/`serve.sh` usage, the seed compiler recipe, the example-verification workflow (spec §8), the figure/screenshot workflow (spec §7), and the HTML/CSS/JS restrictions (spec §6).
- [ ] **Step 3: Verify** — start `bash docs/sf/manuals/serve.sh 8765` in the background, `curl -sf http://127.0.0.1:8765/en/index.html >/dev/null` succeeds, then kill it; confirm port released.
- [ ] **Step 4: Commit** — `git add docs/sf/manuals/serve.sh docs/sf/manuals/README.md && git commit -m "docs(manual): add the local server and contributor README"`.

---

### Task 9: `hello` example + first-program page (tutorial archetype)

**Files:**
- Create: `docs/sf/manuals/src/vol1/hello.z98`, `docs/sf/manuals/src/build_linux.sh`, `docs/sf/manuals/src/build_owc.bat`
- Create: `docs/sf/manuals/en/vol1-05-first-program.html`
- Modify: `docs/sf/manuals/todo-figures-list.html` (add the Win9x run figure)

**Interfaces:**
- Consumes: the Task 5 template, the Task 7 checker, the Task 4 GIFs.
- Produces: the first content page and the canonical example-build scripts.

- [ ] **Step 1: Write `hello.z98`** — modelled on the working idiom in `examples/z98/tco_defer/main.zig`:
  ```zig
  const std = @import("std");

  pub fn main() !void {
      std.io.print("Hello from Z98!\n");
  }
  ```
  Verify it compiles and runs; if the compiler rejects a construct, correct the example to the syntax that actually works (that correction is the point of the task).
- [ ] **Step 2: Compile and run** — `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed`, then the Compiler-under-test recipe for `hello.z98`. Capture stdout, stderr, and `rc`.
- [ ] **Step 3: Write `build_linux.sh` and `build_owc.bat`** — the example-tree build scripts (one `.z98` → executable on Linux; the OpenWatcom companion for Win9x). `build_linux.sh` uses the Compiler-under-test recipe; `build_owc.bat` follows the emitted `build_target.bat`/`build_owc.bat` conventions.
- [ ] **Step 4: Write `vol1-05-first-program.html`** from the Task 5 template — explain `fn main`, `std.io.print`, the compile command, and the output. Embed the **real captured transcript** in `<pre>`. Add one Win9x screenshot placeholder ("Figure 1 — running `hello` under Windows 98") and one matching `todo-figures-list.html` row (what to capture: a Win98 command prompt showing `hello.exe` output).
- [ ] **Step 5: Verify** — `bash docs/sf/manuals/check.sh` passes; the transcript in the page matches the captured run byte-for-byte; every syntax claim is checked against `docs/reference/Language_Spec_Z98.md`.
- [ ] **Step 6: Commit** — `git add docs/sf/manuals/src docs/sf/manuals/en/vol1-05-first-program.html docs/sf/manuals/todo-figures-list.html && git commit -m "docs(manual): add the first-program tutorial page and hello example"`.

---

### Task 10: `error_unions` example + page (mental-shift archetype)

> **BLOCKED (AMENDMENT 1):** verification found a real compiler defect — `errdefer` is dropped on explicit error returns. The page/example are parked uncommitted. Tasks 10A/10B must land first; then this task is re-verified (the errdefer claim corrected to the fixed behaviour) and committed.

**Files:**
- Create: `docs/sf/manuals/src/vol2/error_unions.z98`
- Create: `docs/sf/manuals/en/vol2-12-error-unions.html`
- Modify: `docs/sf/manuals/todo-figures-list.html`

**Interfaces:**
- Consumes: the Task 5 template, the Task 9 example-build scripts.
- Produces: the mental-shift page the blueprint calls make-or-break.

- [ ] **Step 1: Write `error_unions.z98`**:
  ```zig
  const std = @import("std");

  fn divide(a: i32, b: i32) error{DivideByZero}!i32 {
      if (b == 0) return error.DivideByZero;
      return a / b;
  }

  pub fn main() !void {
      const ok = try divide(10, 2);
      std.io.printInt(@intCast(i32, ok));
      std.io.print("\n");

      const bad = divide(1, 0) catch |err| {
          std.io.print("caught: DivideByZero\n");
          return;
      };
      std.io.printInt(@intCast(i32, bad));
      std.io.print("\n");
  }
  ```
  Verify it compiles and runs; correct to the syntax the compiler actually accepts.
- [ ] **Step 2: Compile and run** — capture stdout, stderr, `rc`. Expected shape: `5` then `caught: DivideByZero`, rc 0.
- [ ] **Step 3: Write `vol2-12-error-unions.html`** from the template — `error{...}`, `!T`, `E!T`, `try`, `catch |err|`, `errdefer`, `error.Tag`; why `orelse` is for optionals; why `anyerror` does not exist; the "you will reach for `errno`/`goto cleanup`; here is the Z98 way" paragraph. Embed the real transcript; add one Win9x figure placeholder + its `todo-figures-list.html` row.
- [ ] **Step 4: Verify** — `check.sh` passes; transcript matches; every claim checked against the spec and, for error-set semantics, source.
- [ ] **Step 5: Commit** — `git add docs/sf/manuals/src/vol2 docs/sf/manuals/en/vol2-12-error-unions.html docs/sf/manuals/todo-figures-list.html && git commit -m "docs(manual): add the error-unions chapter and example"`.

---

### Task 10A (I): Investigate the `errdefer`-on-explicit-return defect

**Files:**
- Read (no edits): `sf/src/lower.zig`, `sf/src/lir.zig`, `sf/src/c89_emit.zig`, and the parser/AST if needed.
- Read: `docs/reference/Language_Spec_Z98.md` §3.1, `docs/design/DESIGN.md`, and the `Design_p2.md` defer/errdefer semantics.
- Create: the findings report (SDD workspace; not committed).

**Context:** Task 10's verification found `errdefer` bodies dropped when a function returns an error explicitly (`return error.Boom;`), while they run on `try` propagation. Suspected locus: `return_stmt` lowering calls `expandDefers(..., is_error_path=0, ...)` (`sf/src/lower.zig` ~6309) whereas `try` passes `1` (`sf/src/lower.zig` ~4749).

- [ ] **Step 1: Reproduce** — write a minimal program exercising `errdefer` on (a) an explicit `return error.X`, (b) a conditional explicit `return error.X`, (c) `try` propagation, and (d) a normal return; compile with the seed `zig1` and inspect the emitted C for each errdefer body. Capture the exact evidence.
- [ ] **Step 2: Locate the root cause** — trace `return_stmt` / `expandDefers` / `is_error_path` in `sf/src/lower.zig` and compare with the `try` path. State the exact condition under which the error path is (not) marked.
- [ ] **Step 3: Establish correct semantics** — quote `docs/reference/Language_Spec_Z98.md` §3.1 and the design doc; state precisely when an `errdefer` must run.
- [ ] **Step 4: Determine the minimal fix and its blast radius** — what changes, which lowering/emission paths are affected, which existing examples/fixtures use `errdefer`, and whether the fix can alter emitted C for existing programs.
- [ ] **Step 5: Recommend the Task 10B verification plan** — the repro, the regression-fixture name/location, and the gates to run.
- [ ] **Step 6: Report** — write the findings to the SDD workspace report file. **No `sf/src` edits, no source commit.**

---

### Task 10B (F): Fix the `errdefer`-on-explicit-return defect

**Files (expected; confirm against the Task 10A report):**
- Modify: `sf/src/lower.zig`.
- Create: a permanent regression fixture under `repro/mi_matrix/` (errdefer-on-explicit-return; name per Task 10A) with `main.zig`, `expected.txt`, and `expected.rc` captured from the FIXED compiler. The corpus enumerator (`scripts/corpus/list_corpus_dirs.sh`) auto-enumerates it; update `repro/mi_matrix/EXPECTED_FAIL.md` if the corpus classification requires it.
- Create: a standalone repro program under `repro/` — the human-readable reproduction left in the repo.
- Modify: the relevant `sf/docs/tech_docs/*.md` per AGENTS.md §1.1.1.
- Rotate: `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` at closeout — the fix moves the self-emission fixed point, so rotation is required.

**Interfaces:**
- Consumes: the Task 10A findings.
- Produces: a compiler whose `errdefer` runs on explicit error returns, plus a permanent `repro/mi_matrix` regression fixture and a standalone repro.

- [ ] **Step 1: Implement the minimal fix** identified by Task 10A, via `edit`/`fastedit` only.
- [ ] **Step 2: Rebuild from seed and verify the repro** — the four errdefer cases (explicit return, conditional explicit return, `try` propagation, normal return) now behave per spec; capture the emitted C as evidence.
- [ ] **Step 3: Leave the reproductions** — add the permanent `repro/mi_matrix/<name>/` fixture (`main.zig` + `expected.txt` + `expected.rc`, goldens captured from the FIXED compiler) and the standalone `repro/` program; verify the fixture passes deterministically 3×.
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (`docs/sf/QUICK_REF.md`) — self-compile fixed point (hop1 == hop2); the 21-example matrix; the 4-MD5 gates (re-baseline only if byte-affecting, with runtime-identical evidence); the stdlib runtime gate; and the corpus `-s0` sweep with zero class movement except the new fixture. STOP and present if any gate moves unexpectedly.
- [ ] **Step 5: Rotate the seed** — `bash scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> release/seed/zig1-seed.tgz --update-changelog` (required: the fixed point moves); update `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, and `docs/sf/QUICK_REF.md` per repo convention.
- [ ] **Step 6: Update the tech docs** covering the changed lowering (AGENTS.md §1.1.1).
- [ ] **Step 7: Commit** — `fix(lower): run errdefer on explicit error returns` (with the fixture, repro, docs, and seed files).

---

### Task 10C (I): Investigate the `defer`/`errdefer` control-flow defect

**Files:**
- Read (no edits): `sf/src/parser.zig`, `sf/src/ast.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`.
- Read: `docs/reference/Language_Spec_Z98.md` §3.1, the design docs.
- Create: the findings report (SDD workspace; not committed).

**Context:** Task 10's review found the compiler accepts `break`/`continue`/`return` inside `defer`/`errdefer`, contradicting `docs/reference/Language_Spec_Z98.md` §3.1 (`:225`, `:252`). Worse, `errdefer { continue; }` swallows an explicit error return (probe prints nothing instead of `caught`). Reviewer evidence: six probe shapes (`defer_continue`, `defer_return`, `errdefer_continue`, `errdefer_continue2`, `errdefer_return`, `errdefer_return2`) all emit rc=0.

- [ ] **Step 1: Reproduce** all six shapes; capture emitted C and runtime behaviour, including the `errdefer { continue; }` error-swallow.
- [ ] **Step 2: Locate where the prohibition belongs** — parser, semantic analyzer, or static analyzer — and where `errdefer { continue; }` mishandles the error path in `sf/src/lower.zig`.
- [ ] **Step 3: Establish correct semantics** from spec §3.1 and the design docs.
- [ ] **Step 4: Determine the minimal fix** (likely a diagnostic rejection) and its blast radius — which existing programs/tests use `break`/`continue`/`return` inside `defer`/`errdefer`.
- [ ] **Step 5: Recommend the Task 10D verification plan** — repros, regression-fixture name/location, gates.
- [ ] **Step 6: Report** — findings to the SDD workspace report file. **No `sf/src` edits, no source commit.**

---

### Task 10D (F): Fix the `defer`/`errdefer` control-flow defect (match Zig)

**Supersedes Task 10C's recommendation.** Zig research (verified against `AstGen.zig` + Zig's compile-error tests) established the exact rule; Task 10C's lexical `defer_depth` blanket ban is WRONG because it would reject the inner-loop `break`/`continue` that Zig allows. The Z98 spec §3.1/§3.2 is amended to match Zig (see below).

**The Zig rule (binding):**
- `return` anywhere inside a `defer`/`errdefer` body → rejected (`cannot return from defer expression`), **except** inside a nested `fn` declared in the body.
- `break`/`continue` that transfer control **out of** the `defer`/`errdefer` → rejected (`cannot break/continue out of defer expression`).
- `break`/`continue` targeting a loop or labeled block **declared inside** the body → **allowed**.
- `try` inside the body → rejected (`'try' not allowed inside defer expression`).
- Identical for `defer` and `errdefer`. Mechanism: AstGen's `cur_defer_node` (checked by `break`/`continue`) and `any_defer_node` (checked by `return`/`try`); a nested `fn` resets both; an inner block/loop resets only `cur_defer_node`.

**Files (expected; confirm during implementation):**
- Modify: `docs/reference/Language_Spec_Z98.md` §3.1 (`:225`) and §3.2 (`:252`) — replace the blanket ban with the scope-aware rule above (cite the Zig behaviour).
- Modify: `sf/src/semantic_analyzer.zig` (scope-aware defer-context tracking + diagnostics); `sf/src/diagnostics.zig` (new dedicated error codes).
- Create: a permanent `repro/mi_matrix/<name>/` fixture (`main.zig` + `expected.txt` + `expected.rc` from the FIXED compiler) covering **both** the rejected outward cases **and** the accepted inner-loop/labeled-block cases; a standalone `repro/` program.
- Modify: the relevant `sf/docs/tech_docs/*.md` per AGENTS.md §1.1.1.
- Rotate: `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` at closeout iff the fixed point moves.

**Interfaces:**
- Consumes: this task's Zig-matched rule (supersedes the Task 10C report).
- Produces: a compiler that rejects outward `return`/`break`/`continue` and `try` inside `defer`/`errdefer`, while accepting transfers that target constructs inside the body; new dedicated diagnostics; a regression fixture + repro.

- [ ] **Step 1: Add the new dedicated error codes** to `sf/src/diagnostics.zig` (verify free numbers; `3011/3012/3013` and `3019` are taken): `RETURN_INSIDE_DEFER`, `BREAK_OUT_OF_DEFER`, `CONTINUE_OUT_OF_DEFER`, `TRY_INSIDE_DEFER`.
- [ ] **Step 2: Implement scope-aware defer-context tracking** in `sf/src/semantic_analyzer.zig`, mirroring AstGen: a current-defer marker (checked by `break`/`continue`) and an inside-any-defer marker (checked by `return`/`try`); nested `fn` resets both; an inner block/loop resets only the current-defer marker. Emit the new diagnostics at the rejection sites.
- [ ] **Step 3: Amend the Z98 spec** §3.1/§3.2 to the scope-aware rule (cite Zig).
- [ ] **Step 4: Rebuild from seed and verify** — the rejected outward cases now error with the new codes; the accepted inner-loop/labeled-block cases compile and run; `errdefer { continue; }` no longer silently swallows an error. Capture evidence.
- [ ] **Step 5: Leave the reproductions** — the permanent `repro/mi_matrix/<name>/` fixture (goldens from the FIXED compiler, deterministic 3×) and the standalone `repro/` program.
- [ ] **Step 6: Run the QUICK_REF gate battery verbatim** (`docs/sf/QUICK_REF.md`) — self-compile fixed point (hop1 == hop2); the 21-example matrix; the 4-MD5 gates (re-baseline only if byte-affecting, with runtime-identical evidence); the stdlib runtime gate; and the corpus `-s0` sweep with zero class movement except the new fixture. STOP and present if any gate moves unexpectedly.
- [ ] **Step 7: Rotate the seed** iff the fixed point moves; update `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, and `docs/sf/QUICK_REF.md` per repo convention.
- [ ] **Step 8: Update the tech docs** covering the changed analyzer (AGENTS.md §1.1.1).
- [ ] **Step 9: Commit** — `fix(sema): reject outward control flow in defer/errdefer per Zig` (with the fixture, repro, spec, docs, and any seed files).

---

### Task 10E (I): Investigate the dynamic `errdefer` residual

**Files:**
- Read (no edits): `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lir.zig`, `sf/src/c89_emit.zig`.
- Read: `docs/reference/Language_Spec_Z98.md` §3.1, the design docs.
- Create: the findings report (SDD workspace; not committed).

**Context:** the Task 10B fix classifies an explicit return as an error exit only when the return expression carries a `wrap_error_err` coercion or is an `error_literal`. A dynamic `return <error-union variable>;` where the variable's type is already `E!T` (`src==dst`) records no coercion (`tryRecordCoercion` early-returns on `src==dst`), so `ret_is_error` stays 0 and `errdefer` is dropped. This is a silent correctness bug. Task 10 currently documents it as a page Note, which spec §11 forbids.

- [ ] **Step 1: Reproduce** — `fn f() E!T { var x: E!T = error.Boom; errdefer undo(); return x; }`; confirm the errdefer body does not run and the emitted C shows no error-path branch; capture control cases (direct `return error.Boom;` works).
- [ ] **Step 2: Locate the root cause** — trace why no coercion is recorded for the `src==dst` return and how the `try` path handles a dynamic error union (it emits a runtime `is_error` branch).
- [ ] **Step 3: Establish correct semantics** from spec §3.1 and the design docs.
- [ ] **Step 4: Determine the minimal fix and its blast radius** — likely a runtime `is_error` branch on the returned error-union value (mirroring `try`); identify which lowering/emission paths and whether any existing program returns an error-union variable.
- [ ] **Step 5: Recommend the Task 10F verification plan** — repros, fixture name/location, gates.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task 10F (F): Fix the dynamic `errdefer` residual

**Files (expected; confirm against the Task 10E report):**
- Modify: `sf/src/lower.zig` (and any emitter path the fix needs).
- Create: a permanent `repro/mi_matrix/<name>/` fixture (`main.zig` + `expected.txt` + `expected.rc` from the FIXED compiler) + a standalone `repro/` program.
- Modify: the relevant `sf/docs/tech_docs/*.md` per AGENTS.md §1.1.1.
- Rotate: `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` at closeout iff the fixed point moves.

**Interfaces:**
- Consumes: the Task 10E findings.
- Produces: a compiler where `errdefer` runs on a dynamic error-union return, plus a regression fixture and repro.

- [ ] **Step 1: Implement the minimal fix** per Task 10E, via `edit`/`fastedit` only.
- [ ] **Step 2: Rebuild from seed and verify** — the dynamic return now runs `errdefer` on the error path and not on the success path; capture evidence.
- [ ] **Step 3: Leave the reproductions** — the `repro/mi_matrix/<name>/` fixture (goldens from the FIXED compiler, deterministic 3×) and the standalone `repro/` program.
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (`docs/sf/QUICK_REF.md`) — self-compile fixed point (hop1 == hop2); the 21-example matrix; the 4-MD5 gates (re-baseline only if byte-affecting, with runtime-identical evidence); the stdlib runtime gate; and the corpus `-s0` sweep with zero class movement except the new fixture. STOP and present if any gate moves unexpectedly.
- [ ] **Step 5: Rotate the seed** iff the fixed point moves; update `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, and `docs/sf/QUICK_REF.md` per repo convention.
- [ ] **Step 6: Update the tech docs** covering the changed lowering (AGENTS.md §1.1.1).
- [ ] **Step 7: Commit** — `fix(lower): run errdefer on a dynamic error-union return` (with the fixture, repro, docs, and any seed files).
- [ ] **Step 8: Re-run Task 10's chapter fix** — remove the `errdefer` dynamic-return Note (`en/vol2-12-error-unions.html`) now that it is fixed, and re-verify. Then re-run the Task 13 closeout sweep.

---

### Task 11A (I): Investigate the `@floatCast` lowering defect

**Files:**
- Read (no edits): `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/comptime_eval.zig`, `sf/src/c89_emit.zig`.
- Read: `docs/reference/Language_Spec_Z98.md` §4, `docs/reference/builtins.md`.
- Create: the findings report (SDD workspace; not committed).

**Context:** `@floatCast` is accepted by the front end (`sf/src/semantic_analyzer.zig:306`) but `sf/src/lower.zig` has no `floatcast` dispatch prong, so the seed-v43 binary emits a poison-filled temp instead of a conversion (silent miscompile; compiles clean). `@intToFloat`/`@intCast`/`@as` lower correctly.

- [ ] **Step 1: Reproduce** — a minimal `@floatCast` program (f64→f32 and f32→f64); confirm the poison temp in emitted C and the wrong runtime value; capture control cases.
- [ ] **Step 2: Locate the root cause** — trace where `@floatCast` is interned/accepted (sema) and why `lower.zig` never dispatches it; identify the missing prong(s) and the intended LIR/emission path.
- [ ] **Step 3: Establish correct semantics** from spec §4 and `builtins.md`.
- [ ] **Step 4: Determine the minimal fix and its blast radius** — which lowerer/emitter paths; whether any existing program uses `@floatCast`.
- [ ] **Step 5: Recommend the Task 11B verification plan** — repros, fixture name/location, gates.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task 11B (F): Fix the `@floatCast` lowering defect

**Files (expected; confirm against the Task 11A report):**
- Modify: `sf/src/lower.zig` (and any emitter path the fix needs).
- Create: a permanent `repro/mi_matrix/<name>/` fixture (`main.zig` + `expected.txt` + `expected.rc` from the FIXED compiler) + a standalone `repro/` program.
- Modify: the relevant `sf/docs/tech_docs/*.md` per AGENTS.md §1.1.1.
- Rotate: `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` at closeout iff the fixed point moves.

**Interfaces:**
- Consumes: the Task 11A findings.
- Produces: a compiler that lowers `@floatCast` correctly, plus a regression fixture and repro.

- [ ] **Step 1: Implement the minimal fix** per Task 11A, via `edit`/`fastedit` only.
- [ ] **Step 2: Rebuild from seed and verify** — `@floatCast` produces the correct conversion at runtime; capture evidence.
- [ ] **Step 3: Leave the reproductions** — the `repro/mi_matrix/<name>/` fixture (goldens from the FIXED compiler, deterministic 3×) and the standalone `repro/` program.
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (`docs/sf/QUICK_REF.md`) — self-compile fixed point (hop1 == hop2); the 21-example matrix; the 4-MD5 gates (re-baseline only if byte-affecting, with runtime-identical evidence); the stdlib runtime gate; and the corpus `-s0` sweep with zero class movement except the new fixture. STOP and present if any gate moves unexpectedly.
- [ ] **Step 5: Rotate the seed** iff the fixed point moves; update `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, and `docs/sf/QUICK_REF.md` per repo convention.
- [ ] **Step 6: Update the tech docs** covering the changed lowering (AGENTS.md §1.1.1).
- [ ] **Step 7: Commit** — `fix(lower): lower @floatCast` (with the fixture, repro, docs, and any seed files).

---

### Task 11C (I): Investigate the `@floatCast`/`@intToFloat` comptime-fold gap

**Files:**
- Read (no edits): `sf/src/comptime_eval.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/type_registry.zig`.
- Read: `docs/reference/Language_Spec_Z98.md` §4, `docs/reference/builtins.md`.
- Create: the findings report (SDD workspace; not committed).

**Context:** `comptime_eval.zig` has no `@floatCast` (or `@intToFloat`) branch, so a compile-time-known `@floatCast`/`@intToFloat` is not folded and cannot satisfy a comptime-value requirement. Operator ruled this must be corrected, not documented as a limitation.

- [ ] **Step 1: Reproduce** — a program that requires a comptime value from `@floatCast`/`@intToFloat` (e.g. an array size or a comptime `const`), showing it fails or is not folded; capture the current behaviour and the foldable-builtin set in `comptime_eval.zig`.
- [ ] **Step 2: Locate the root cause** — how the foldable set is defined/interned and why these builtins are absent; what the `comptime_values` mechanism expects.
- [ ] **Step 3: Establish correct semantics** from spec §4 and `builtins.md` (and official Zig's comptime `@floatCast`/`@intToFloat`).
- [ ] **Step 4: Determine the minimal fix and its blast radius** — add the fold branch(es) with correct width/precision handling; which paths; whether any existing program relies on the non-folded behaviour.
- [ ] **Step 5: Recommend the Task 11D verification plan** — repros, fixture name/location, gates.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task 11D (F): Add comptime folding for `@floatCast`/`@intToFloat`

**Files (expected; confirm against the Task 11C report):**
- Modify: `sf/src/comptime_eval.zig` (and any semantic/lowering path the fix needs).
- Create: a permanent `repro/mi_matrix/<name>/` fixture (`main.zig` + `expected.txt` + `expected.rc` from the FIXED compiler) + a standalone `repro/` program.
- Modify: the relevant `sf/docs/tech_docs/*.md` per AGENTS.md §1.1.1 (incl. `04_comptime_eval.md`), and correct any remaining stale `builtins.md`/design-doc "constant folding" text to match.
- Rotate: `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` at closeout iff the fixed point moves.

**Interfaces:**
- Consumes: the Task 11C findings.
- Produces: a compiler that constant-folds `@floatCast`/`@intToFloat` on comptime-known values, plus a regression fixture and repro.

- [ ] **Step 1: Implement the minimal fix** per Task 11C, via `edit`/`fastedit` only.
- [ ] **Step 2: Rebuild from seed and verify** — the comptime repro now folds; runtime behaviour unchanged for non-comptime operands; capture evidence.
- [ ] **Step 3: Leave the reproductions** — the `repro/mi_matrix/<name>/` fixture (goldens from the FIXED compiler, deterministic 3×) and the standalone `repro/` program.
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (`docs/sf/QUICK_REF.md`) — self-compile fixed point (hop1 == hop2); the 21-example matrix; the 4-MD5 gates (re-baseline only if byte-affecting, with runtime-identical evidence); the stdlib runtime gate; and the corpus `-s0` sweep with zero class movement except the new fixture. STOP and present if any gate moves unexpectedly.
- [ ] **Step 5: Rotate the seed** iff the fixed point moves; update `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, and `docs/sf/QUICK_REF.md` per repo convention.
- [ ] **Step 6: Update the tech docs** (AGENTS.md §1.1.1) and any now-accurate "constant folding" prose.
- [ ] **Step 7: Commit** — `feat(comptime): fold @floatCast/@intToFloat` (with the fixture, repro, docs, and any seed files).

---

### Task 11E (I): Investigate the array-size builtin gap

**Files:**
- Read (no edits): `sf/src/comptime_eval.zig`, `sf/src/type_resolver.zig`, `sf/src/semantic_analyzer.zig`.
- Read: `docs/reference/Language_Spec_Z98.md` §4/§5, `docs/reference/builtins.md`.
- Create: the findings report (SDD workspace; not committed).

**Context:** array sizes that use a builtin — `[@intCast(...)]`, `[@sizeOf(...)]`, `[@intToFloat(...)]`, etc. — hard-error `ERR_3050`, because `evalConstU32Full`/`evalConstI64Full` have no `builtin_call` arm. The operator ruled this must be addressed.

- [ ] **Step 1: Reproduce** each shape (`[@intCast(u32, n)]`, `[@sizeOf(T)]`, `[@intToFloat(...)]`) and confirm the `ERR_3050`; enumerate which builtins are affected and which fold paths exist.
- [ ] **Step 2: Locate the root cause** — where `evalConstU32Full`/`evalConstI64Full` are called for array sizes, why they lack a `builtin_call` arm, and how the general `comptime_eval` path differs.
- [ ] **Step 3: Establish correct semantics** from spec §4/§5, `builtins.md`, and official Zig (builtin calls in array-size positions must fold).
- [ ] **Step 4: Determine the minimal fix and its blast radius** — route array-size builtin calls through the fold evaluator; which paths; whether any existing program relies on the current error.
- [ ] **Step 5: Recommend the Task 11F verification plan** — repros, fixture name/location, gates.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task 11F (F): Fix the array-size builtin gap

**Files (expected; confirm against the Task 11E report):**
- Modify: `sf/src/comptime_eval.zig` (and any type-resolver path the fix needs).
- Create: a permanent `repro/mi_matrix/<name>/` fixture (`main.zig` + `expected.txt` + `expected.rc` from the FIXED compiler) + a standalone `repro/` program.
- Modify: the relevant `sf/docs/tech_docs/*.md` per AGENTS.md §1.1.1.
- Rotate: `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` at closeout iff the fixed point moves.

**Interfaces:**
- Consumes: the Task 11E findings.
- Produces: a compiler that folds builtin calls in array-size positions, plus a regression fixture and repro.

- [ ] **Step 1: Implement the minimal fix** per Task 11E, via `edit`/`fastedit` only.
- [ ] **Step 2: Rebuild from seed and verify** — the array-size repros now compile and run; capture evidence.
- [ ] **Step 3: Leave the reproductions** — the `repro/mi_matrix/<name>/` fixture (goldens from the FIXED compiler, deterministic 3×) and the standalone `repro/` program.
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (`docs/sf/QUICK_REF.md`) — self-compile fixed point (hop1 == hop2); the 21-example matrix; the 4-MD5 gates (re-baseline only if byte-affecting, with runtime-identical evidence); the stdlib runtime gate; and the corpus `-s0` sweep with zero class movement except the new fixture. STOP and present if any gate moves unexpectedly.
- [ ] **Step 5: Rotate the seed** iff the fixed point moves; update `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, and `docs/sf/QUICK_REF.md` per repo convention.
- [ ] **Step 6: Update the tech docs** covering the changed fold path (AGENTS.md §1.1.1).
- [ ] **Step 7: Commit** — `fix(comptime): fold builtin calls in array-size positions` (with the fixture, repro, docs, and any seed files).

---

### Task 11G (I): Investigate struct introspection in array sizes

**Files:**
- Read (no edits): `sf/src/type_resolver.zig`, `sf/src/type_registry.zig`, `sf/src/comptime_eval.zig`.
- Read: `docs/reference/Language_Spec_Z98.md` §4/§5, `docs/reference/builtins.md`.
- Create: the findings report (SDD workspace; not committed).

**Context:** folding `@sizeOf`/`@alignOf`/etc. of a **struct** in an array-size position is not crystal clear — layout is computed later than the current evaluation point. Task 11E found a direct `ty.size` read without the `state == 2` completeness gate emitted a silently wrong `[1]` for an aggregate field (true size 16). Determine the correct route (`resolveTypeExprFull` + registry, gated on `state == 2`) and the correct layout timing for module-scope array sizes and aggregate fields.

- [ ] **Step 1: Reproduce** `[@sizeOf(S)]` / `[@alignOf(S)]` for a struct at module scope and as an aggregate field; confirm the current failure and the wrong-`[1]` hazard.
- [ ] **Step 2: Locate the root cause** — layout timing vs the type-resolve pass; where `state == 2` is set and how other consumers gate on it.
- [ ] **Step 3: Establish correct semantics** from spec §4/§5 and official Zig.
- [ ] **Step 4: Determine the minimal fix and its blast radius** — which paths; whether the fix risks evaluating layout too early.
- [ ] **Step 5: Recommend the Task 11H verification plan** — repros, fixture name/location, gates.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task 11H (F): Fix struct introspection in array sizes (Option B — one shared, order-independent layout function)

**AMENDMENT 10 (operator ruling 2026-09-20):** the fix must NOT duplicate the layout math — divergence would be a silent size bug, and duplication harms extensibility/maintainability. Operator: "duplicate is as you pointed a silent bug that we need to prevent against also the extensibility and maintainability are real risk". So use ONE shared, order-independent layout function (Option B), not a second on-demand copy.

**Files:** `sf/src/type_resolver.zig`; a `repro/mi_matrix/` fixture + standalone `repro/`; `sf/docs/tech_docs/03_type_resolution.md` (+ `04_comptime_eval.md` only if the general evaluator is touched); seed rotation (the fixed point moves).

- [ ] **Step 1: Refactor the layout math into one order-independent function.** Turn `typeResolverResolveLayout(self: *TypeResolver, tid)` (`type_resolver.zig:199-325`) into `fn layoutEnsure(registry: *TypeRegistry, tid: u32, depth: u32) bool`, keeping a thin `typeResolverResolveLayout(self, tid)` wrapper that calls it. `layoutEnsure`: return true if `state == 2`; return false past a depth cap (mirror `resolveTypeExprFull`'s 16); for each **direct dependency** (struct/packed-struct/union/tagged/packed-union fields; tagged/union tag type; enum backing; tuple elements; array element; optional/error-union payload) return false if its `type_id` is `0`/`TYPE_UNDEFINED`/`TYPE_VOID`, else recurse and false on failure; then compute the layout with the **existing math moved verbatim** (incl. `typeRegistryComputePackedLayout`/`PackedUnionLayout`); mark `state = 2`; return true. The normal `typeResolverResolve` pass keeps calling it — exactly one layout implementation and one dependency walk.
- [ ] **Step 2: Wire the fold in `evalConstU32Full`'s `builtin_call` arm (`:931-976`).** For the in-scope aggregate kind: after `resolveTypeExprFull`, if `state != 2` call `layoutEnsure(registry, bt_tid, 0)`, then fold only when `state == 2`. **Keep `evalConstScalarKind` as the integer whitelist for the non-aggregate path** — do NOT blanket-`state == 2` (that would fold `tuple_type`, which must stay `ERR_3050`). Mirror `comptime_eval.zig:140-246` for the registry reads (`@bitSizeOf` needs the integer/enum/bool/packed overrides). `@offsetOf`/`@bitOffsetOf`: default stay `ERR_3050` with a note.
- [ ] **Step 3: Leave the reproductions.** A permanent `repro/mi_matrix/<name>/` fixture (`main.zig` + `expected.txt` + `expected.rc` from the FIXED compiler, deterministic 3×): module-scope `[@sizeOf(S)]u8`, aggregate-field `struct{ data: [@sizeOf(S)]u8 }`, local `[@sizeOf(S)]u8`, `@alignOf(S)`, `@bitSizeOf(S)`; runtime `@panic` guard. **Negative controls** (must stay `ERR_3050`, never silently wrong): tuple, slice, forward-referenced, mutual/cyclic aggregates; packed `{u4,u4}` → `[1]` (never `[2]`); float/bool builtins rejected. Plus a standalone `repro/` program.
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (`docs/sf/QUICK_REF.md`) — self-compile fixed point (hop1 == hop2); 21-example matrix; 4-MD5 gates **byte-identical expected** (11G verified) else re-baseline with runtime-identical evidence; stdlib runtime gate; corpus `-s0` zero class movement except the new fixtures. **STOP and present on any unexpected movement.**
- [ ] **Step 5: Rotate the seed** (the fixed point moves) via `scripts/seed/archive_seed.sh`; update `release/seed/CHANGELOG.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md` (incl. the authoritative 4-MD5 table if the gates move).
- [ ] **Step 6: Update the tech docs** (`03_type_resolution.md`: the shared `layoutEnsure`, the dependency walk, the array-size fold) per AGENTS.md §1.1.1.
- [ ] **Step 7: Commit** — `fix(types): fold struct introspection in array sizes` (with fixture, repro, docs, seed).

---

### Task 11I (I): Investigate the `evalConstI64Full` enum silent miscompile

**Files:**
- Read (no edits): `sf/src/type_resolver.zig`, `sf/src/symbol_registrator.zig`, `sf/src/comptime_eval.zig`.
- Read: `docs/reference/Language_Spec_Z98.md` §4/§5.
- Create: the findings report (SDD workspace; not committed).

**Context:** enum initializers are silently miscompiled — `enum(u8) { A = 1 + 2 }` yields `A = 0`, and `enum(u8) { A = @sizeOf(u32) }` yields `A = 0`, because `evalConstI64Full` has no binop/builtin arm and `symbol_registrator.zig:187-191` silently auto-increments on a non-foldable explicit value.

- [ ] **Step 1: Reproduce** both shapes and confirm the silent `0`; enumerate which initializer expressions are affected.
- [ ] **Step 2: Locate the root cause** — `evalConstI64Full`'s missing arms and the silent auto-increment fallback.
- [ ] **Step 3: Establish correct semantics** from spec §4/§5 and official Zig.
- [ ] **Step 4: Determine the minimal fix and its blast radius** — fold binops/builtins and/or reject a non-foldable explicit value instead of silently using 0.
- [ ] **Step 5: Recommend the Task 11J verification plan** — repros, fixture name/location, gates.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

**AMENDMENT 11 (operator ruling 2026-09-20):** Task 11I found the enum silent miscompile cannot be fully fixed by folding at registration time (named-aggregate introspection needs post-layout state; field `type_id == TYPE_VOID` at registration) and that the evaluator is not cycle-safe (`const X = X` hangs, rc=124). Operator ruled to use **Option B** — a post-layout re-evaluation pass that overwrites the stored enum member values (including the auto-increment cascade) — but first add **Task 11Q (I)** to evaluate how to avoid cycles and to determine the best placement for the pass. **Task 11Q (I)** precedes **Task 11J (F)**, which implements Option B per 11I + 11Q. Both join the scoped `sf/src` exception.

**AMENDMENT 12 (operator ruling 2026-09-20):** Task 11Q's design plus the operator's official-Zig investigation fix the fold/reject matrix for Task 11J. **Fold** (official Zig accepts, and Z98 can compute it): arithmetic/bitwise/shift/paren, `char_literal`, `@intCast`, `@sizeOf`/`@alignOf`/`@bitSizeOf` (primitive/alias **and** named aggregates, post-layout), `@offsetOf`/`@bitOffsetOf`, `@as`, and module-const references. **Reject with a new dedicated `ERR_3055_ENUM_VALUE_NOT_CONSTANT`:** bitwise NOT `~`; enum-member references (`B = A`, `B = E.A`) — official Zig rejects these (`error: dependency loop detected`); duplicate tag values — official Zig rejects (`error: enum tag value N already taken`); function calls and non-integer-valued builtins (`@isWindows`, `@intToFloat`, `@floatCast`); and any other unfoldable expression. Official-Zig evidence: `test/behavior/enum.zig` accepts arbitrary comptime expressions (`enum(u4){ A = 1 << 0, ... }`, `enum(u64){ min = std.math.minInt(u64), ... }`); `test/cases/compile_errors/enum_value_already_taken.zig` and `enum_field_value_references_enum.zig` reject duplicates and member references.

**AMENDMENT 13 (operator ruling 2026-09-20):** Task 11J's review found two plan-mandated wrong-accepts and one scope gap; the operator ruled to **fold the rejections and address the minors**. Task 11J's fix round must additionally: (a) **reject** `@as`/`@intCast` in an enum initializer when the target type is non-integer (e.g. `@as(f32,3)`) or the value is out of the target's range (e.g. `@as(u8,300)`) — official Zig rejects both — with `ERR_3055`; (b) extend **duplicate-tag rejection to function-local enums** (currently only the module-pass strict mode runs it); (c) correct the report's inaccurate concerns (a forward-referenced module-level struct DOES fold; a function-local `@sizeOf(S)` folds in both the pre- and post-fix compilers).

**AMENDMENT 14 (operator ruling 2026-09-21):** re-evaluating the deferred minors found two **invalid-Zig** constructs accepted with poor/no diagnostics: `[@intCast(u8, 300)]` folds without a target-width range check (a regression introduced by Task 11F), and `for (0..p.len)` on `[*]T` yields a gcc-class failure instead of a clean front-end error. Operator ruled to add fixtures and an I/F round: **11R (I)** + **11S (F)**. Both join the scoped `sf/src` exception. **Ruling on 11R's decision points:** **D1** — use the existing `error[3000]` for all three rejects (no new dedicated code); **D2** — also include the `comptime_eval.zig:247-274` `@intCast` masking case (`const X = @intCast(u8,300)` → `44`, same invalid-Zig class) in Task 11S. **Ruling on the 11S STOP (option A):** D2 stands and AMENDMENT 14 **supersedes** the INTWIDTH design's `@intCast` truncate/mask semantics (`docs/superpowers/specs/2026-09-06-arbitrary-width-ints-design.md` §3.4); re-pin `repro/mi_matrix/intwidth_cast_xmod` to the range-checked (reject) behavior and update that design line; the truncate/mask case remains covered by `intwidth_wrap_xmod`.

**AMENDMENT 15 (operator ruling 2026-09-21):** `comptimeEvalOperandSigned` (`comptime_eval.zig:410-454`; fold arm `:283`) does not unwrap `@as`, so `@intToFloat(f64, @as(u64, X))` misclassifies operand signedness. Valid Z98. Operator ruled an I/F round: **11T (I)** + **11U (F)**. **Ruling on 11T's STOP (2026-09-21):** (1) proceed with the **general fix** — intern `@as` and share the `@intCast` arm in `comptimeEvalBuiltin` and `comptimeEvalOperandSigned` so `@as` folds; the brief's stated mechanism was wrong (`@as` never folds at all, and `comptimeEvalOperandSigned` is never reached with an `@as` node — the gap is pre-existing, reproduced on `ea159fc2`). (2) **Option A:** re-pin the pinned fixture `safe_intcast_widen_sign_xmod` to the range-checked behavior (`@intCast(u16, @as(i8,-1))` is comptime out-of-range, as official Zig rejects).

**AMENDMENT 16 (operator ruling 2026-09-21):** the remaining deferred minors are documentation-only. Operator ruled a single F task: **11V (F)** (docs corrections + a note documenting the `?bool` = 8 / `E!bool` 4-byte-floor divergence). **Accepted residuals (no action):** the dynamic error-union `return x;` rewrap is left as-is; the function-local-enum-referencing-a-function-local-const reject keeps the improvement.

**AMENDMENT 17 (operator ruling 2026-09-21):** the function-local/inline **type emission** defect (valid Zig; `semantic_analyzer.zig:2699-2702` + `lower.zig:6585`) is **out of scope for this plan** and gets its **own separate plan** (I task first, then the plan, covering enum **and** struct/union/error-set if official Zig behaves the same), including the divergence discussion (official Zig allows local types; the C++ bootstrap `type_checker.cpp:3827` rejects).


### Task 11Q (I): Investigate cycle-safe post-layout enum re-evaluation and its placement

**Files:**
- Read (no edits): `sf/src/type_resolver.zig`, `sf/src/symbol_registrator.zig`, `sf/src/comptime_eval.zig`, `sf/src/main.zig`, `sf/src/type_registry.zig`, `sf/src/lower.zig`.
- Create: the findings report (SDD workspace; not committed).

**Context:** Task 11I found the enum silent miscompile cannot be fully fixed by folding at registration time — named-aggregate introspection (`@sizeOf(struct)`) needs post-layout state (field `type_id == TYPE_VOID` at registration) — so the operator chose **Option B**: a post-layout re-evaluation pass that overwrites the stored enum member values (including the auto-increment cascade). The evaluator is not cycle-safe (`const X = X` hangs, rc=124) and the pass placement must be chosen deliberately.

- [ ] **Step 1: Map the data** — where enum member values are stored (`symbol_registrator.zig` `em_items`, `enum_value_table`), when the registration loop writes them, and every consumer (`lower.zig`, `c89_emit.zig`, `semantic_analyzer.zig`).
- [ ] **Step 2: Study the cycle hazard** — how `evalConstI64Full`'s `ident_expr` recursion loops; what depth/visited guard is needed; compare with existing depth handling in `evalConstU32Full`/`comptime_eval.zig`.
- [ ] **Step 3: Evaluate candidate placements** for the re-evaluation pass (e.g. after `typeResolverResolve` layout and before `phase_SemanticAnalysis`, or inside an existing phase) against correctness (post-layout state), cycle safety, ordering vs the sema enum gate, and whether member values can be overwritten in place.
- [ ] **Step 4: Specify the algorithm** — the full member-sequence walk with a fresh `auto_val`; which initializer expressions to fold (integer forms + named-aggregate introspection) vs hard-reject; how the sema gate interacts (must not re-suppress a stale value).
- [ ] **Step 5: Blast radius + recommend the Task 11J verification plan** — fixed-point/seed impact; fixtures (positive + reject controls), gates, and the runtime `@panic` guard.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---


### Task 11J (F): Fix the enum silent miscompile

**Files (expected; confirm against the Task 11I report):** `sf/src/type_resolver.zig` and/or `sf/src/symbol_registrator.zig`; a `repro/mi_matrix/` fixture + standalone `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per 11I + 11Q + AMENDMENT 12 (Option B: post-layout re-evaluation pass; fold/reject matrix and duplicate-tag rejection as specified there); rebuild+verify (enum values correct, or a clean diagnostic instead of silent 0); leave the reproductions; run the QUICK_REF gate battery verbatim (STOP on unexpected gate movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(types): fold enum initializer expressions` (with fixture, repro, docs, seed).

---

### Task 11R (I): Investigate the invalid-Zig diagnostic gaps (array-size `@intCast` range; `[*]T` `.len`)

**Files:**
- Read (no edits): `sf/src/type_resolver.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`.
- Create: the findings report (SDD workspace; not committed).

**Context:** Two invalid-Zig constructs are accepted with poor/no diagnostics. (a) `var a: [@intCast(u8, 300)]u8` folds without a target-width range check (`type_resolver.zig:1043-1048`) — a regression introduced by Task 11F; official Zig rejects an out-of-range comptime `@intCast`. (b) `for (0..p.len)` with `p: [*]T` emits an undeclared C operand (gcc-class failure) instead of a clean front-end error (`semantic_analyzer.zig:759-766`); `[*]T` has no `.len` in Z98 or Zig.

- [ ] **Step 1: Reproduce** both shapes; confirm each is invalid Zig (spec + official Zig).
- [ ] **Step 2: Locate the exact gaps** and the minimal fix sites — `intValueFitsType` (`type_resolver.zig:1096`) for (a); a `.len`-on-many-item-pointer diagnostic for (b).
- [ ] **Step 3: Blast radius** (fixed point / seed, gates) + recommend the Task 11S verification plan (reject-control fixtures).
- [ ] **Step 4: Report.** **No `sf/src` edits, no source commit.**

---

### Task 11S (F): Clean-reject the invalid-Zig diagnostic gaps

**Files (confirm against the 11R report):** `sf/src/type_resolver.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/comptime_eval.zig`; `repro/mi_matrix/` reject-control fixtures; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per 11R with the operator ruling (**D1:** use the existing `error[3000]` for all three rejects; **D2:** include the `comptime_eval.zig:247-274` `@intCast` masking case). All three cases — (a) array-size `@intCast` target-width range check via `intValueFitsType`, (b) `.len` on `[*]T`, (c) the `comptime_eval.zig` `@intCast` masking — must clean-reject (rc=2, 0 `.c`), never a silent value or a gcc-class failure; add fixtures + `expected_dirs.txt` pin; run the QUICK_REF gate battery verbatim (STOP on unexpected gate movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(types): clean-reject invalid @intCast and [*]T .len`.

---

### Task 11T (I): Investigate `comptimeEvalOperandSigned` `@as` unwrapping

**Files:**
- Read (no edits): `sf/src/comptime_eval.zig`.
- Create: the findings report (SDD workspace; not committed).

**Context:** `comptimeEvalOperandSigned` (`comptime_eval.zig:410-454`) unwraps `paren_expr` and `@intCast` but not `@as`, so `@intToFloat(f64, @as(u64, X))` is classified by `cv.sig` instead of the `@as` target's signedness. Valid Z98.

- [ ] **Step 1: Reproduce** the signedness misclassification.
- [ ] **Step 2: Locate the gap** (`@as` is not interned; no `as_id` in `ComptimeEval`).
- [ ] **Step 3: Determine the minimal fix** (intern `@as`; resolve the target type's signedness via the same extra-child layout as `@intCast`) + blast radius.
- [ ] **Step 4: Recommend the Task 11U verification plan** (fixtures, gates).
- [ ] **Step 5: Report.** **No `sf/src` edits, no source commit.**

---

### Task 11U (F): Unwrap `@as` in `comptimeEvalOperandSigned`

**Files (confirm against the 11T report):** `sf/src/comptime_eval.zig`; a `repro/mi_matrix/` fixture + standalone `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per 11T; rebuild+verify; leave the reproductions; run the QUICK_REF gate battery verbatim (STOP on unexpected gate movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(comptime): unwrap @as in float-fold operand signedness`.

---

### Task 11V (F): Documentation corrections (final-review minors)

**Files:** `docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md` (its own `:35` Global Constraints amendment range), `docs/sf/QUICK_REF.md` (11N historical tally), `docs/sf/manuals/README.md` ("seven checks" / "only JavaScript" / "local only" + `serve.sh` bind), the design docs with stale comptime-fold claims (`COMPATIBILITY.md`, `DESIGN.md`, `C89_Codegen.md`, `AST_Parser.md`), `docs/reference/Language_Spec_Z98.md` (`continue`/`break` prose), and the Task 10D call-site comment; `release/seed/SEED_README.txt` (archive metadata — note it is generated, so fix the generator or defer to the next rotation).

- [ ] **Steps 1–7:** correct each; document the `?bool` = 8 / `E!bool` 4-byte-floor divergence as an accepted residual; no compiler change; commit `docs: final-review minor corrections`.

---


### Task 11K (I): Investigate the `bool` size/align divergence

**Files:** read-only `sf/src/type_registry.zig`, `sf/src/c89_emit.zig`, `sf/src/type_resolver.zig`, `sf/src/lower.zig`; read spec §1/§4; create the findings report.

**Context:** `@sizeOf(bool)`/`@alignOf(bool)` yield 4 in Z98 (`type_registry.zig:685`) while Zig's `bool` is 1 byte/align 1. Both are valid Zig.

- [ ] **Step 1: Reproduce** `@sizeOf(bool)`/`@alignOf(bool)` and a bool-field struct layout.
- [ ] **Step 2: Trace** every consumer of bool's size/align (C emission of bool fields/arrays/params, struct layout, ABI, `-fsafe` representation) and **assess the blast radius** of changing to 1 byte/align 1 — including whether any existing program/test depends on bool=4. **STOP and present if so.**
- [ ] **Step 3: Establish the target** (match Zig = 1) and the exact changes needed.
- [ ] **Step 4: Recommend the Task 11L verification plan** (repros, fixture name/location, gates).
- [ ] **Step 5: Report.** No `sf/src` edits, no commit.

---

### Task 11L (F): Fix the `bool` size/align

**Files (per 11K):** `sf/src/type_registry.zig` + any emission path; a `repro/mi_matrix/` fixture + standalone `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per 11K (bool size/align = 1, matching Zig); rebuild+verify; leave reproductions (goldens from the FIXED compiler); run the QUICK_REF gate battery verbatim (STOP on unexpected movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(types): make bool 1 byte to match Zig` (with fixture, repro, docs, seed).

---

### Task 11M (I): Investigate `.len` on a struct-field array

**Files:** read-only `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/c89_emit.zig`; create the findings report.

**Context:** `const S = struct { a: [4]u8 }; var s: S; const n = s.a.len;` fails to lower (`zT_N` undeclared) — valid Zig.

- [ ] **Step 1: Reproduce** and scope which `.len` shapes fail (field of a local/param/global struct; nested; `[*]T`/slice fields).
- [ ] **Step 2: Locate the root cause** — compare field-access `.len` lowering with the working local-array `.len`.
- [ ] **Step 3: Establish correct semantics** (Zig: arrays support `.len`).
- [ ] **Step 4: Determine the minimal fix and its blast radius.**
- [ ] **Step 5: Recommend the Task 11N verification plan.**
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 11N (F): Fix `.len` on a struct-field array

**Files (per 11M):** `sf/src/lower.zig` (+ emitter if needed); a `repro/mi_matrix/` fixture + standalone `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per 11M; rebuild+verify; leave reproductions (goldens from the FIXED compiler); run the QUICK_REF gate battery verbatim (STOP on unexpected movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(lower): lower .len on a struct-field array` (with fixture, repro, docs, seed).

---

### Task 11O (I): Investigate the `for (0..<end>)` range-end gap

**Files:** read-only `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`; create the findings report.

**Context:** `for (0..s.a.len) |i|` yields `0` (the range end is never resolved): `semanticAnalyzerResolveForHeader` resolves only `node.child_0`, and `range_exclusive` returns `TYPE_U32` without resolving its children. Valid Zig.

- [ ] **Step 1: Reproduce** `for (0..s.a.len)`, `for (0..a.len)`, `for (0..n)`, `for (x..y)` and confirm which ends resolve.
- [ ] **Step 2: Locate the root cause** — `semanticAnalyzerResolveForHeader` and the `range_exclusive` typing path; compare with a working resolved expression.
- [ ] **Step 3: Establish correct semantics** (Zig: arbitrary integer range ends, incl. `.len`).
- [ ] **Step 4: Determine the minimal fix and its blast radius.**
- [ ] **Step 5: Recommend the Task 11P verification plan.**
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 11P (F): Fix the `for`-range end resolution

**Files (per 11O):** `sf/src/semantic_analyzer.zig` (+ `lower.zig` if needed); a `repro/mi_matrix/` fixture + standalone `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per 11O; rebuild+verify (range ends fold/resolve, incl. `.len`); leave reproductions (goldens from the FIXED compiler); run the QUICK_REF gate battery verbatim (STOP on unexpected movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(sema): resolve the for-range end expression` (with fixture, repro, docs, seed).

---

### Task 11: Builtins reference page (reference archetype)

> **BLOCKED (AMENDMENT 3):** found the `@floatCast` silent-miscompile defect; Tasks 11A/11B must land first, then this page documents the full spec builtin surface.

**Files:**
- Create: `docs/sf/manuals/en/vol4-15-builtins.html`

**Interfaces:**
- Consumes: the Task 5 template.
- Produces: the reference archetype page.

- [ ] **Step 1: Read the sources** — `docs/reference/Language_Spec_Z98.md` §4, `docs/reference/builtins.md`, and the builtin dispatch in `sf/src/semantic_analyzer.zig` / `sf/src/comptime_eval.zig` / `sf/src/lower.zig`.
- [ ] **Step 2: Write `vol4-15-builtins.html`** from the template — the builtin list grouped as the spec groups them (cast/conversion, introspection, runtime, C varargs, async, declarations, print), one short entry each with a minimal usage snippet. Reference style: lookup, not tutorial. **No claim that is not in the spec or source** (spec §3).
- [ ] **Step 3: Verify** — `check.sh` passes; every builtin name, signature, and behavior is cross-checked against the spec and source; no invented builtin.
- [ ] **Step 4: Commit** — `git add docs/sf/manuals/en/vol4-15-builtins.html && git commit -m "docs(manual): add the builtins reference page"`.

---

### Task 12: Title pages, TOC wiring, search, populated figure list

**Files:**
- Create: `docs/sf/manuals/en/vol1-00-title.html`, `vol2-00-title.html`, `vol4-00-title.html`
- Modify: `docs/sf/manuals/en/toc.html`, `en/index.html`, `en/readme.html`, `en/search.html`, `en/search-data.js`, `docs/sf/manuals/todo-figures-list.html`

**Interfaces:**
- Consumes: all content pages from Tasks 9–11.
- Produces: a navigable site.

- [ ] **Step 1: Write the three title pages** from the template — each names its volume, its audience entry/exit state (blueprint Part 1), and links to its chapters.
- [ ] **Step 2: Wire `toc.html`** — link every shipped page; keep the unshipped volumes listed and marked "planned".
- [ ] **Step 3: Wire `en/index.html`, `readme.html`, `search.html`** — index links `toc.html`; search page uses `doSearch()` over `z98SearchData` and degrades to the TOC; `search-data.js` is regenerated by `build.sh`.
- [ ] **Step 4: Populate `todo-figures-list.html`** — every placeholder added in Tasks 9–11 has exactly one row.
- [ ] **Step 5: Verify** — `bash docs/sf/manuals/check.sh` passes (links, `rel`, figure 1:1, no-CSS baseline); `bash docs/sf/manuals/build.sh` succeeds.
- [ ] **Step 6: Commit** — `git add docs/sf/manuals && git commit -m "docs(manual): wire the volume titles, TOC, index, search, and figure list"`.

---

### Task 13: Whole-set review + verification sweep + closeout

**Files:**
- Review: all `docs/sf/manuals/**`; modify as needed.

- [ ] **Step 1: Run the mechanical gate** — `bash docs/sf/manuals/check.sh` passes; `bash docs/sf/manuals/build.sh` succeeds; `bash docs/sf/manuals/serve.sh` serves and the pages fetch.
- [ ] **Step 2: Re-run every example** — rebuild the seed compiler, compile+run `src/vol1/hello.z98` and `src/vol2/error_unions.z98`, and confirm each page's embedded transcript still matches byte-for-byte.
- [ ] **Step 3: Verify the no-CSS baseline** — fetch each page with the stylesheet links stripped and confirm the content is legible, navigable, and correctly ordered.
- [ ] **Step 4: Verify the figure workflow** — the placeholder↔`todo-figures-list.html` mapping is 1:1 and each row names a concrete capture.
- [ ] **Step 5: Fix** any failure found (website only).
- [ ] **Step 6: Commit** — `git add docs/sf/manuals && git commit -m "docs(manual): Phase 0 closeout — whole-set review and verification sweep"`.

---

## Self-Review

- **Spec coverage:** §3 blueprint-vs-reality → Tasks 9–11 claim verification + Global Constraints; §4 layout → File Structure; §5 hand-authored model → every content task; §6 HTML/CSS/JS/assets → Tasks 2–5 + Global Constraints + Task 7 checker; §7 figures → Tasks 1/5/9/10/12 + Task 7 check; §8 verification → Tasks 9–11/13 + the Compiler-under-test section; §9 slice → Tasks 9–12; §10 scripts → Tasks 6–8; §11 conventions → Global Constraints; §12 plan index → the `Sequence:` line.
- **Placeholder scan:** every task names concrete files and observable results; the two examples are written out and each has an explicit "correct to the syntax the compiler actually accepts" step, which is the verification the spec mandates. The only deferred value is the actual captured transcript, which is produced in-task.
- **Type consistency:** the page filenames match the spec §4 tree; `check.sh`/`build.sh`/`serve.sh`/`doc.js`/`z98.css`/`z98-print.css` are named identically across tasks; the figure-list columns match between Task 1 and Tasks 9–12.
- **Amendment 1:** Tasks 10A (I) and 10B (F) are the only tasks that touch `sf/src`; they are inserted before Task 11, and Task 10 is marked BLOCKED until they land. The plan is otherwise website-only. The manual spec's "website only" convention is amended to carve out this scoped exception.
