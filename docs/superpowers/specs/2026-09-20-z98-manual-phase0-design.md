# Z98 Manual — Phase 0 (infrastructure + first slice) — Design

> **Status:** Approved 2026-09-20 (operator). Program-level spec for the Z98
> manual website. The Phase 0 plan argues from this document; later volume
> plans argue from it too, amending it only by operator ruling.

**Goal:** Stand up the Z98 manual as a local, offline, era-accurate static
website under `docs/sf/manuals/`, and prove the whole pipeline end-to-end with
three verified content pages (one tutorial, one mental-shift, one reference),
so the remaining volumes can be authored against a proven template.

## §1 The gap this closes

The blueprint `docs/sf/manuals/manuals_blueprint.txt` describes a six-volume,
multi-language, offline manual (~830 pages) for Z98 targeting 1998-era
machines, delivered as static HTML on CD and diskette. **None of it exists.**
There is no HTML, CSS, JS, GIF asset set, page template, build script, check
script, figure workflow, or example tree under `docs/sf/manuals/`.

The blueprint is a vision document written against a presumed feature set;
parts of it do not match the current compiler (§3). It cannot be executed
as-is. This program turns it into an executable series, beginning here.

## §2 Scope of Phase 0

**In scope:** the website skeleton; the era-accurate HTML/CSS/JS conventions;
the GIF asset set; the page template; the build/check/serve scripts; the
figure/screenshot workflow; and three verified content pages plus their
example programs.

**Out of scope (later plans):** the full Volumes I–VI, the remaining ~800
pages, Volume IV/VI generators, translations (`es/`, `zh-cn/`), and the
diskette/CD distribution builds.

## §3 Blueprint vs. reality (binding)

The manual documents the **current** compiler only. Verified mismatches:

| Blueprint says | Reality (verified 2026-09-20) | Ruling |
|---|---|---|
| `.z98dbg` sidecar debugger (III.15) | does not exist anywhere in the repo | drop |
| emitter-level socket builtins (III.12) | socket builtins were removed; `net_runtime.c` is dead; sockets are the `std_net` extern surface | rewrite to `std.net` |
| `platform_win98.h`, `WINVER=0x0410`, `_MBCS` (III.8) | bootstrap-era only | rewrite to the current `-osw` target + `net_prelude.h` |
| DirectX 7/8 `ddraw-mini.z98` (III.14) | no DirectX headers or example exist | drop the example; keep era-context prose only if verifiable |
| "the 70 `error[30xx]` codes" (IV.21) | 26 `ERR_30xx` members in `sf/src/diagnostics.zig` | correct the count; Reference derives from source |
| named samples `types.z98`, `arena.z98`, `http-mini.z98`, … | only `hello` exists; real examples are `mandelbrot`, `mud_server`, `lisp_interpreter`, `rogue_mud`, … | new pedagogical examples authored in `docs/sf/manuals/src/`, using only real features, compile+run verified |

**Rule:** when a page's claim cannot be verified against the current compiler
and `docs/reference/Language_Spec_Z98.md`, fix the page or drop the claim.
Never ship a claim that does not reproduce.

## §4 Location & layout (binding)

Root: `docs/sf/manuals/`.

```
docs/sf/manuals/
  index.html              language selector (English active)
  readme.html             what this is / how to read / colophon
  todo-figures-list.html  every pending Win9x screenshot
  en/
    index.html  readme.html  toc.html  search.html  search-data.js
    doc.js  z98.css  z98-print.css
    gfx/  gfx/xbm/
    vol1-00-title.html  vol1-05-first-program.html
    vol2-00-title.html  vol2-12-error-unions.html
    vol4-00-title.html  vol4-15-builtins.html
    vol4-24-html-style.html
  src/  vol1/hello.z98  vol2/error_unions.z98  build_linux.sh  build_owc.bat
  build.sh  check.sh  serve.sh
  dist/                   generated (gitignored)
```

Flat within `en/`: every page is a sibling, assets are `gfx/…`, depth is
always 1. This is what makes the diskette build a file-copy operation.

## §5 Authoring model (binding)

**Hand-authored static HTML** (blueprint-literal). No source→HTML generator in
Phase 0. The AI copies the page template for each page. The build script only
assembles `dist/`, generates `search-data.js`, and copies assets. Generators
for Volume IV (Reference) and Volume VI (Internals) are deferred to their own
plans.

## §6 HTML/CSS/JS restrictions (binding)

The site targets 1998 browsers — Netscape 4.x, Internet Explorer 4, and Lynx —
on Win9x and era Linux.

### 6.1 HTML

- Doctype: HTML 4.0 Transitional. Author in the conservative HTML 3.2/4.0
  intersection.
- **No HTML5 elements** (`<section>`, `<article>`, `<nav>`, `<header>`,
  `<footer>`, `<main>`, `<figure>`). **No `<div>` for structure** — layout uses
  `<table>`.
- Encoding: ISO-8859-1, declared as
  `<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">`.
  No UTF-8 for English.
- Layout: a three-column `<table>` (sidebar 160px, 1px gutter, content).
  Baseline appearance is carried by presentational attributes — `bgcolor`,
  `align`, `width`, `border`, `cellpadding`, `cellspacing`, `valign` — and by
  `<font>`, `<b>`, `<i>`, `<center>`.
- Every page carries `<link rel="home|up|prev|next">`, a sidebar TOC of the
  current volume, a language bar, and a prev/contents/next footer.

### 6.2 CSS — verdict: allowed only as progressive enhancement

Verified 2026-09-20: **CSS1 is era-valid.** It is a W3C Recommendation dated
17 December 1996; Internet Explorer 4 (September 1997, shipped with Windows 95
OSR 2.5 and Windows 98) explicitly added CSS support; Netscape 4 supports a
buggy subset. Therefore CSS ships, under these binding rules:

- `z98.css` (screen) and `z98-print.css` (print) are **external linked
  stylesheets**, **CSS1 properties only**. Old UAs ignore the `<link>`
  entirely — no content leak.
- **No inline `<style>` blocks.** A pre-CSS UA would render their text as body
  content. If one is ever unavoidable it MUST be wrapped in SGML comments
  (`<style type="text/css"><!-- … --></style>`).
- **CSS carries no meaning and no layout.** With both stylesheets removed the
  site must remain legible, navigable, and correctly ordered. A "CSS disabled"
  review is mandatory.
- **No CSS2/CSS3.** No `page-break-before`/`page-break-after` (CSS2), no
  `position`, no `display`-based layout beyond CSS1 `display: none`, no
  `@media` beyond a `media="print"` link attribute, no web fonts.
- The print stylesheet is limited to CSS1: `display: none` for navigation
  elements, a `pt` font size, and a hairline `border` on `<pre>`. Page breaks
  are dropped (they are CSS2).

### 6.3 JavaScript

One file `doc.js`, ≤ 2 KB, four functions (`swap`, `tocToggle`, `doSearch`,
`preload`), no `document.write`, no browser sniffing; every feature degrades
to working HTML. JavaScript is optional.

### 6.4 Assets

GIF only — no PNG, no SVG, no web fonts. Sizes: logo 240×48, bullets 8×8,
icons 16×16 (`note`, `tip`, `warn`, `caution`, `era`, `honest`), buttons 88×24
plus `-over` rollover pairs, navrule 150×8. XBM alternates under `gfx/xbm/`.

### 6.5 Forbidden list (checker-enforced)

HTML5 structural tags; `<div>` structure; PNG/SVG/web fonts; external resources
(any `http://`/`https://` in `href`/`src`); inline `<style>`; `<script src>`
other than `doc.js`; more than 2 KB of JS; CSS2/CSS3 properties or selectors.

## §7 Figures & screenshots (binding)

Every illustrative figure is one of two kinds:

- **Terminal transcript** — AI-produced, captured from a *real* `*nix`/`wine`
  run, rendered in `<pre>`.
- **Win9x screenshot** — a reserved era-styled placeholder box on the page
  (`Figure N — Win9x screenshot pending`) naming the exact claim it
  illustrates. The operator captures these on real Win9x after the plan.

`docs/sf/manuals/todo-figures-list.html` enumerates every pending screenshot:
page, figure id, caption, target claim, what to capture, suggested
window/state. `check.sh` enforces a 1:1 match between on-page placeholders and
list entries — no orphan figures in either direction.

## §8 Content verification (binding)

For every content page:

1. Each example exists in `docs/sf/manuals/src/`, is compiled with the
   seed-built `zig1` and `gcc -m32`, and is actually run.
2. The captured transcript matches the prose.
3. `-osw`/Win9x claims are run under `wine`.
4. Every syntax and builtin claim is cross-checked against
   `docs/reference/Language_Spec_Z98.md` and, for builtins, the compiler
   source.

A claim that fails is fixed or removed — never shipped.

## §9 The first slice (cross-archetype)

- `en/vol1-05-first-program.html` + `src/vol1/hello.z98` — tutorial archetype.
- `en/vol2-12-error-unions.html` + `src/vol2/error_unions.z98` — mental-shift
  archetype (the blueprint's stated make-or-break content).
- `en/vol4-15-builtins.html` — reference archetype, grounded in
  `docs/reference/builtins.md`, the spec's §4, and source.
- Volume title pages, `toc.html`, `en/index.html`, `readme.html`,
  `search.html` wiring.

## §10 Scripts (binding)

- `build.sh` — assemble `en/` into `dist/`, generate `search-data.js`, copy
  assets. Idempotent; no network.
- `check.sh` — Python 3 standard library only, no network. Verifies: every
  `href`/`src` resolves; `rel` home/up/prev/next present and consistent;
  language-bar links; charset and per-page `lang`; the §6.5 forbidden list; the
  §7 figure↔todo-list 1:1 match; and the **no-CSS baseline** (structural parse
  with CSS links stripped).
- `serve.sh` — `python3 -m http.server` on the manual root, for local browsing.

## §11 Conventions (binding)

- **Website only, with scoped compiler exceptions (Amendments 1–17).** No
  `sf/src`, `scripts/`, fixture, or `release/seed` change — except the inserted
  compiler tasks **10A/10B** (`errdefer` dropped on explicit error returns),
  **10C/10D** (`break`/`continue`/`return` accepted inside `defer`/`errdefer`),
  **11A/11B** (`@floatCast` accepted but not lowered), **10E/10F** (dynamic
  `return <error-union variable>;` still drops `errdefer`), **11C/11D**
  (`@floatCast`/`@intToFloat` not constant-folded), **11E–11J + 11Q** (array
  sizes using a builtin hard-error `ERR_3050`; struct introspection in array
  sizes; the `evalConstI64Full` enum silent miscompile, fixed via the Option B
  post-layout re-evaluation pass studied in 11Q), **11K–11P** (`bool`
  size/align 4 vs Zig 1; `.len` on a struct-field array not lowering; the
  `for (0..s.a.len)` for-range end not resolved), and **11R–11U** (invalid-Zig
  constructs accepted with poor/no diagnostics: `[@intCast(u8, 300)]` without a
  target-width range check and `for (0..p.len)` on `[*]T`; `@as` not unwrapped
  in float-fold operand signedness), found while verifying the manual. (Task
  **11V** is docs-only and therefore outside this `sf/src` exception.) Only
  those tasks may touch the compiler, run its gates, and rotate the seed;
  compiler correctness takes priority over the manual.
- All files live under `docs/sf/manuals/`. `dist/` is gitignored.
- English content only in Phase 0; the language bar lists only shipped
  languages.
- **Accuracy over volume.** Every claim must reproduce (§3, §8).
- Edits via `edit`/`fastedit` only; no bulk transforms.
- **STOP on a real compiler defect** found while verifying a claim — report it;
  do not fix `sf/src`, do not document around it.

## §12 Plan index

1. `docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md` — Phase 0
   infrastructure plus the cross-archetype slice. **First plan.** Amendment 1
   (2026-09-20) inserts Tasks 10A (I) and 10B (F) to fix the
   `errdefer`-on-explicit-return compiler defect before the error-unions
   chapter is committed.
