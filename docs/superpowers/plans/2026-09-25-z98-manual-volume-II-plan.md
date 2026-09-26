# Z98 Manual — Volume II (Learning Z98) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author all 21 chapters of Volume II (Learning Z98), English, into the Phase 0 website under `docs/sf/manuals/`, each chapter carrying a runnable example (where the blueprint gives one), a "Common mistakes" list, and cross-references to Reference and HOWTO, every example compile+run verified against the seed-built compiler.

**Architecture:** One plan, 21 chapter tasks plus a read-only capability inventory (Task 0) and a whole-set closeout (Task 22). Chapters 12 (expand the Phase 0 slice), 14, and 15 ship first — the blueprint's mental shifts; the rest follow in numeric order. Each chapter task: read its contract from the spec, author the example under `src/vol2/`, capture the real transcript, write the page from the Phase 0 template, cross-check every claim against `docs/reference/Language_Spec_Z98.md` and source, add the figure placeholder and matching `todo-figures-list.html` row, wire the chapter's navigation, verify with `check.sh`/`build.sh`, and commit. The site is correct after every commit; Task 22 is the whole-set review and verification sweep. The plan is website-only **except** operator-ruled scoped compiler I/F amendments (§ below).

**Tech Stack:** Hand-authored HTML 4.0 Transitional, CSS1, 1998-era vanilla JavaScript (`doc.js`), GIF assets, Python 3 standard library (`check.py`), the seed-built `zig1` + `gcc -m32` for example verification, git.

**Spec:** `docs/superpowers/specs/2026-09-25-z98-manual-volume-II-design.md` (binding for this plan). Program-level spec: `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (binding for every volume). Blueprint: `docs/sf/manuals/manuals_blueprint.txt` (Part 4 for this volume).

**Sequence:** PREVIOUS plan: `docs/superpowers/plans/2026-09-22-z98-print-formatting-plan.md` (print-formatting parity + Amendment 1; COMPLETE, seed v88). NEXT plan: the Volume III plan (Phase 3).

**Compiler amendments (operator-ruled, inserted when a defect is found):** an amendment appends an I/F pair to this plan — **Task Na (I)** read-only investigation, **Task Nb (F)** fix with a `repro/mi_matrix/` fixture, a standalone `repro/` program, the QUICK_REF gate battery verbatim (STOP on unexpected movement), tech-doc updates, a two-hop closure verification with the moved fixed point recorded, and a commit. Amendment tasks are the **only** tasks permitted to touch `sf/src`, `scripts/`, `repro/`, or `release/seed/`, or to run the compiler gate battery. **Seed rotation is closeout-only:** F tasks verify the closure and record the moved fixed point; Task 22 rotates the seed once (iff the fixed point moved) via `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`.

## Global Constraints

- **Website only, with scoped exceptions (spec §5).** Do NOT edit `sf/src/**`, `scripts/**`, `repro/**`, or `release/seed/**` — EXCEPT tasks inserted by an operator-ruled compiler amendment. Only those tasks may edit the compiler, add fixtures/repros, run the compiler gate battery, or verify a moved fixed point. Every other task leaves the compiler fixed point and the seed untouched.
- **STOP on a real compiler defect** found while verifying a claim — report it with a minimal reproduction; do not fix `sf/src`, do not document around it, do not re-scope the chapter (spec §4; phase0 §9/§11). Compiler correctness takes priority over the manual; a defect becomes its own amendment.
- **All files under `docs/sf/manuals/`** except this plan and its spec.
- **Blueprint-vs-reality rule (phase0 §3).** The manual documents the current compiler only. When a claim cannot be verified against `docs/reference/Language_Spec_Z98.md` and source, fix the page or drop the claim. Never ship an unreproducible claim.
- **HTML restrictions (phase0 §6.1).** HTML 4.0 Transitional doctype, authored in the HTML 3.2/4.0 intersection. No HTML5 structural tags (`<section>`, `<article>`, `<nav>`, `<header>`, `<footer>`, `<main>`, `<figure>`). **No `<div>` for structure** — layout uses `<table>`. ISO-8859-1 only, declared `<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">`. Baseline appearance via presentational attributes (`bgcolor`, `align`, `width`, `border`, `cellpadding`, `cellspacing`, `valign`) and `<font>`/`<b>`/`<i>`/`<center>`. Every page carries `<link rel="home|up|prev|next">`, a sidebar TOC, a language bar, and a prev/contents/next footer.
- **CSS restrictions (phase0 §6.2).** CSS1 only. `z98.css` (screen) and `z98-print.css` (print) are **external linked stylesheets**. **No inline `<style>` blocks.** CSS carries no meaning and no layout — with both stylesheets removed the site must remain legible, navigable, and correctly ordered. No CSS2/CSS3.
- **JS restrictions (phase0 §6.3).** One file `doc.js`, ≤ 2048 bytes, four functions (`swap`, `tocToggle`, `doSearch`, `preload`), no `document.write`, no browser sniffing.
- **Asset restrictions (phase0 §6.4).** GIF only — no PNG, no SVG, no web fonts. XBM alternates under `gfx/xbm/`.
- **Forbidden list (phase0 §6.5, checker-enforced).** HTML5 structural tags; `<div>` structure; PNG/SVG/web fonts; external resources (any `http://`/`https://` in `href`/`src`); inline `<style>`; `<script src>` other than `doc.js`; > 2048 bytes of JS; CSS2/CSS3 properties or selectors.
- **Figures (phase0 §7).** Terminal transcripts are AI-produced from real runs and rendered in `<pre>`. Win9x screenshots are reserved placeholder boxes plus an entry in `docs/sf/manuals/todo-figures-list.html`; `check.sh` enforces a 1:1 match by figure number. The operator captures the screenshots on real Win9x after the plan. The next free figure number is **17** (16 is used by `vol2-12-error-unions.html`); Task 0 confirms.
- **Content verification (phase0 §8; spec §6).** Every example is compiled with the seed-built `zig1` and `gcc -m32`, actually run, and its transcript matched to the prose; `-osw`/Win9x claims are run under `wine`; every syntax/builtin claim is cross-checked against `docs/reference/Language_Spec_Z98.md` and source.
- **Chapter shape (spec §3.2).** 8–14 pages of prose; a runnable example with its transcript where the page index gives a sample; a "Common mistakes" subsection wherever the chapter has code; a "Where to go next" cross-reference subsection; one honesty callout wherever the chapter touches a limit, a friction point, or an era alternative. Volume II does not require Volume I's "Check yourself".
- **Cross-references (spec §3.3).** Only files that exist may be `<a>`-linked. Planned targets (most of Volume IV, all of Volume V) are named in prose with `(planned)` and no link.
- **Navigation, non-contiguous shipping (spec §3.4).** Sidebar lists all 21 chapters on every shipped Volume II page (shipped = link, unshipped = `<i>(planned)</i>`). `rel` prev/next and the footer point at the **nearest shipped page** in that direction; Task 22 restores the continuous chain. The last chapter's `next` remains `vol4-00-title.html`.
- **English only.** The language bar carries English plus the "not yet available" plain-text entries, exactly as the existing pages do.
- **Edits via `edit`/`fastedit` only**; no bulk transforms. Never stage `mnemoria/`, `.opencode/`, or `.zig1_*.tmp`.
- **Reference compiler rebuilt per the seed model** (`release/seed/`). The seed is rotated **only** by Task 22, and only if a compiler amendment moved the fixed point.

## Compiler under test (for example verification)

Build the seed compiler once per session (repo root, relative path required):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
```

Compile and run an example (recipe in `docs/sf/QUICK_REF.md`):

```bash
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out docs/sf/manuals/src/vol2/<prog>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

Capture stdout, stderr, and `rc` as the transcript. For a `-osw`/Win9x claim, emit with `-osw` and run the `.exe` under `wine`. If the emitted script's argument order or default name differs, use the recipe in `docs/sf/QUICK_REF.md` verbatim.

---

## File Structure

**Create (pages, flat in `docs/sf/manuals/en/`):**
- `vol2-01-honest-comparison.html` … `vol2-11-defer.html` (chapters 1–11)
- `vol2-13-optionals.html`, `vol2-14-arena.html`, `vol2-15-builtins.html`
- `vol2-16-no-methods.html` … `vol2-20-whats-next.html` (chapters 16–20)

**Create (examples, `docs/sf/manuals/src/vol2/`):**
- `types2.z98`, `pointers.z98`, `shapes.z98`, `wire.z98`, `color.z98`, `variant.z98`, `pair.z98`, `strings.z98`, `control.z98`, `defer.z98`, `lookup.z98`, `arena.z98`, `builtins.z98`, `shapes2.z98`, `stdio.z98`, `print.z98`
- helper modules only where an example needs one (named in the task that creates it)

**Modify (existing):**
- `docs/sf/manuals/en/vol2-00-title.html` — expand to the full chapter-0 shape (Task 4); flip shipped chapter entries to links on every later task.
- `docs/sf/manuals/en/vol2-12-error-unions.html` — expand to the full chapter shape (Task 1).
- `docs/sf/manuals/en/toc.html` — link each shipped Volume II chapter.
- `docs/sf/manuals/en/index.html`, `docs/sf/manuals/en/search.html` — link shipped chapters where those pages list them.
- `docs/sf/manuals/en/search-data.js` — regenerated by `build.sh` (never hand-edited).
- `docs/sf/manuals/todo-figures-list.html` — one row per new placeholder.
- Every shipped `docs/sf/manuals/en/vol2-*.html` — flip this chapter's sidebar entry from `(planned)` to a link; keep rel/footer nearest-shipped links correct.
- `docs/superpowers/specs/2026-09-25-z98-manual-volume-II-design.md` — status line at closeout (Task 22).

**Reference (read-only):** `docs/sf/manuals/manuals_blueprint.txt` (Part 4), `docs/reference/Language_Spec_Z98.md`, `docs/reference/builtins.md`, `docs/sf/QUICK_REF.md`, `docs/sf/manuals/en/vol4-24-html-style.html` (the template/contract), the existing `en/vol2-00-title.html` and `en/vol2-12-error-unions.html`, and the closed parity-plan residuals in `repro/mi_matrix/EXPECTED_FAIL.md`.

---

## How each chapter task works

Every chapter task follows this shape. Steps are written out per task below; the shared rules are:

1. **Read the sources** — the chapter's contract in spec §2.2 and the blueprint Part 4 row; list the exact claims to verify.
2. **Verify feasibility first (STOP if it fails)** where the chapter depends on an API or behavior that may not exist; report to the operator instead of inventing it.
3. **Author the example(s)** under `src/vol2/`, compile+run with the seed compiler, and capture the exact transcript.
4. **Write the page** from the `vol4-24-html-style.html` skeleton — sidebar (all 21 Volume II chapters, shipped ones linked, unshipped `(planned)`), language bar, `rel` home/up/prev/next (nearest shipped), 8–14 pages of prose per the chapter's "Must cover" list, the runnable example(s) with transcripts in `<pre>`, "Common mistakes", "Where to go next" (existing pages only), one honesty callout where warranted, and the Win9x note where the chapter ships a program.
5. **Cross-check every claim** against `docs/reference/Language_Spec_Z98.md` and, for builtins/std, the compiler source.
6. **Figures:** add the placeholder box and the matching `todo-figures-list.html` row (1:1) using the chapter's figure number.
7. **Wire the chapter:** flip this chapter's sidebar entry from `(planned)` to a link on every shipped `en/vol2-*.html` page, in `en/toc.html`, and in `en/vol2-00-title.html`; set the new page's `rel`/footer prev/next to its nearest shipped neighbors and update those neighbors' `rel`/footer; link the chapter from `en/index.html` where the volume index lists chapters (and `en/search.html` if it lists them).
8. **Verify:** `bash docs/sf/manuals/check.sh` passes; `bash docs/sf/manuals/build.sh` succeeds (and `search-data.js` regenerates).
9. **Commit:** `git add docs/sf/manuals && git commit -m "docs(manual): add Volume II chapter NN — <title>"`.

---

### Task 0: Capability inventory (read-only)

**Files:**
- Read-only: `sf/src/**` (as needed), `docs/reference/Language_Spec_Z98.md`, `docs/reference/builtins.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/manuals/**`.
- Create (untracked): `.superpowers/sdd/2026-09-25-z98-manual-volume-II-plan/task-0-report.md`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the spec's chapter contracts (§2.2) and open items (§8).
- Produces: the capability matrix the chapter tasks rely on — for each chapter, every "Must cover" claim marked **verified on seed v88** / **needs a corrected claim** / **defect → amendment**; the exact Z98 builtin names; the actual `std_*` module surface; chapter 14's arena API; chapter 15's builtin list and grouping; chapter 18's accepted/rejected formats; the known residuals from the closed comptime-int and print-formatting plans that touch Volume II topics; the next free figure number; and the predicted compiler I/F pairs.

- [ ] **Step 1: Build the compiler** per "Compiler under test" and record its md5 (`md5sum /tmp/manual_seed/zig1_5_clean`).
- [ ] **Step 2: Build the capability matrix** — for each chapter 0–20, reproduce each "Must cover" item from spec §2.2 against the compiler and the Language Spec (small `.z98` probes; compile+run). Record verdicts with the probe command and output. Cover at minimum: type widths/coercions (ch2), pointer builtin names (ch3), struct/packed offsets (ch4/5), enum builtins and switch ranges (ch6), union forms (ch7), tuple printing (ch8), slicing/coercions (ch9), optional capture / while-continue / labeled loops/blocks (ch10), defer/errdefer rules (ch11), error-union constructs and diagnostics (ch12), `?*T` representation (ch13), arena API (ch14), the §4 builtin inventory (ch15), manual vtables (ch16), the `std_*` module list (ch17), print formats (ch18).
- [ ] **Step 3: Resolve the builtin-name drift** — record the real Z98 spelling for every builtin the blueprint names with modern-Zig spellings (`@intFromPtr`, `@ptrFromInt`, `@intToEnum`, `@enumToInt`, `@bitCast`, `@volatileCast`).
- [ ] **Step 4: Inventory the residuals** — read `repro/mi_matrix/EXPECTED_FAIL.md` and the closed plans' specs for residuals touching Volume II topics; for each, note whether a chapter's "Must cover" item depends on it.
- [ ] **Step 5: Confirm the figure numbering** — the highest used figure number in `todo-figures-list.html` (expected 16; next free 17).
- [ ] **Step 6: Predict the compiler I/F pairs** — the claims most likely to fail (highest risk first), with the probe evidence.
- [ ] **Step 7: Write the report** to the workspace path above and return a summary. No commit.

---

### Task 1: Chapter 12 — Error unions (expand the Phase 0 page)

**Files:**
- Modify: `docs/sf/manuals/en/vol2-12-error-unions.html`
- Modify: every shipped `en/vol2-*.html` sidebar if needed (`vol2-00-title.html`), `en/toc.html`, `en/index.html`, `en/search.html` if they list chapters (chapter 12 is already linked)
- Read: `docs/sf/manuals/src/vol2/error_unions.z98`

**Interfaces:**
- Consumes: spec §2.2 chapter 12; blueprint line 155; the Phase 0 page.
- Produces: the full-shape chapter 12; the first-batch page later chapters cross-reference.

- [ ] **Step 1: Re-run the example first (STOP if it fails)** — compile+run `error_unions.z98` with the seed compiler; confirm the transcript (`5`, `caught: DivideByZero`, rc 0) byte-for-byte.
- [ ] **Step 2: Re-verify every existing claim** — the diagnostics quoted (`error[3051]`, `[3052]`, `[3053]`, `[3054]`, `[3015]`, `[3016]`, `error[3000]` for `anyerror`), the `!void` fall-off rule, `errdefer` on explicit and dynamic error returns, and the `try`-in-`defer` rejection. STOP on any mismatch.
- [ ] **Step 3: Expand to the full chapter shape** — keep the honest callout; add "Common mistakes" (reaching for `-1`/`errno`/`goto cleanup`, `orelse` on an error union, `anyerror`, ignoring an error union, `try` inside cleanup) and "Where to go next" (next shipped chapter; `vol4-15-builtins.html`; planned Volume IV errors page and Volume V `errors` HOWTO named as `(planned)`).
- [ ] **Step 4: Figure audit** — the page's Figure 16 placeholder and its `todo-figures-list.html` row already exist; confirm the 1:1 mapping still holds after the edit.
- [ ] **Step 5: Navigation** — confirm the sidebar, `toc.html`, and the title page link chapter 12; `rel` prev/next remain the nearest shipped (`vol2-00-title.html`, `vol4-00-title.html`); footer matches.
- [ ] **Step 6: Verify** — `bash docs/sf/manuals/check.sh` passes; `bash docs/sf/manuals/build.sh` succeeds.
- [ ] **Step 7: Commit** — `docs(manual): expand Volume II chapter 12 — error unions`.

---

### Task 2: Chapter 14 — The arena (second mental shift)

**Files:**
- Create: `docs/sf/manuals/en/vol2-14-arena.html`
- Create: `docs/sf/manuals/src/vol2/arena.z98`
- Modify: `docs/sf/manuals/todo-figures-list.html`; `en/toc.html`; `en/vol2-00-title.html`; `en/index.html`, `en/search.html` where they list chapters; `en/vol2-12-error-unions.html` (sidebar entry + `rel` next → `vol2-14-arena.html`); every shipped `en/vol2-*.html` sidebar.

**Interfaces:**
- Consumes: spec §2.2 chapter 14; blueprint line 157; Task 0's arena-API verdict.
- Produces: chapter 14; the arena example the idioms chapter later references; `rel` chain `vol2-12 → vol2-14`.

- [ ] **Step 1: Verify the API first (STOP if it fails)** — confirm `std.arena.init`/`alloc`/`reset` and the `ArenaError![*]u8` shape against `sf/src/std_arena.zig` (or the actual module) and the spec; compile a probe. If the blueprint's API does not exist, STOP and report — do not invent an API.
- [ ] **Step 2: Author `arena.z98`** — a single-arena program and a dual-arena program exercising `try`/`catch` (never `orelse`), reset, and the `ArenaError![*]u8` return; compile+run; capture the transcript.
- [ ] **Step 3: Write the page** — why there is no `malloc`/`free`; the API; the dual-arena pattern; the "you will reach for `malloc`; here is the Z98 way" paragraph as an honesty callout; "Common mistakes"; "Where to go next"; 8–14 pages.
- [ ] **Step 4: Cross-check** — every API signature and error-name claim against the module source and the spec; every output value against the run.
- [ ] **Step 5: Figure** — the Win9x placeholder for the build-and-run claim (expected Figure 17) + the matching row.
- [ ] **Step 6: Wire** — sidebar entries on all shipped pages, `toc.html`, title page; `rel` prev `vol2-12-error-unions.html`, next `vol4-00-title.html`; ch12's `rel` next/footer updated.
- [ ] **Step 7: Verify** — `check.sh`; `build.sh`.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 14 — the arena`.

---

### Task 3: Chapter 15 — Builtins, in full

**Files:**
- Create: `docs/sf/manuals/en/vol2-15-builtins.html`
- Create: `docs/sf/manuals/src/vol2/builtins.z98` (plus helper programs under `src/vol2/builtins/` if the examples need isolation)
- Modify: `docs/sf/manuals/todo-figures-list.html`; `en/toc.html`; `en/vol2-00-title.html`; `en/index.html`, `en/search.html` where they list chapters; `en/vol2-14-arena.html` (sidebar entry + `rel` next → `vol2-15-builtins.html`); every shipped `en/vol2-*.html` sidebar.

**Interfaces:**
- Consumes: spec §2.2 chapter 15; blueprint line 158; Task 0's builtin inventory and grouping.
- Produces: chapter 15; the builtin examples the type-system and pointers chapters cross-reference; `rel` chain `vol2-14 → vol2-15`.

- [ ] **Step 1: Verify scope first (STOP if it fails)** — take Task 0's builtin list (every §4 builtin, grouped cast/conversion, introspection, runtime, C varargs, async, declarations, print). If one example per builtin cannot fit 8–14 pages, STOP and present the grouping options; do not silently drop builtins.
- [ ] **Step 2: Author `builtins.z98` and helpers** — one verified example per builtin (grouped), including the unknown-builtin `error[3000]` reject captured as a transcript; compile+run every program; capture transcripts.
- [ ] **Step 3: Write the page** — grouped tables/lists of the builtins with the example and its output; the `error[3000]` rule; "Common mistakes" (modern-Zig spellings that do not exist here, e.g. `@intFromPtr` if the real name differs); "Where to go next" (link `vol4-15-builtins.html`); honesty callout where the set is smaller than modern Zig's.
- [ ] **Step 4: Cross-check** — every builtin name, arity, and behavior against spec §4 and the compiler source; no builtin listed that does not compile.
- [ ] **Step 5: Figure** — Win9x placeholder (expected Figure 18) + matching row.
- [ ] **Step 6: Wire** — sidebars, `toc.html`, title page; `rel` prev `vol2-14-arena.html`, next `vol4-00-title.html`; ch14's `rel` next/footer updated.
- [ ] **Step 7: Verify** — `check.sh`; `build.sh`.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 15 — builtins in full`.

---

### Task 4: Chapter 0 — How to read this (expand the title page)

**Files:**
- Modify: `docs/sf/manuals/en/vol2-00-title.html`
- Modify: `en/toc.html` if its chapter list needs the shipped-state refresh

**Interfaces:**
- Consumes: spec §2.2 chapter 0; blueprint lines 143; the existing title page; Tasks 1–3 shipped state.
- Produces: the expanded chapter 0 whose chapter list later tasks keep flipping.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 0 and blueprint Part 1's reading paths.
- [ ] **Step 2: Expand the page** — keep the title, entry/exit state, and chapter list; add the "how to read this volume" prose: the audience (you program; Volume I otherwise), the reading paths, the chapter shape (example, Common mistakes, callouts), the `src/vol2/` examples, and the seed-compiler recipe pointer. No new example, no figure.
- [ ] **Step 3: Refresh the chapter list** — link every shipped chapter (12, 14, 15 plus this page) and mark the rest `(planned)`, matching every shipped page's sidebar.
- [ ] **Step 4: Cross-check** — no claim about Z98 itself; every reading path matches blueprint Part 1.
- [ ] **Step 5: Verify** — `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume II chapter 0 — how to read this`.

---

### Task 5: Chapter 1 — The honest comparison

**Files:**
- Create: `docs/sf/manuals/en/vol2-01-honest-comparison.html`
- Modify: `en/toc.html`; `en/vol2-00-title.html`; `en/index.html`, `en/search.html` where they list chapters; every shipped `en/vol2-*.html` sidebar.

**Interfaces:**
- Consumes: spec §2.2 chapter 1; blueprint lines 144, 179; the phase0 §3 honesty table.
- Produces: chapter 1; the honesty-callout voice the later honesty passages follow.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 1; blueprint line 144 (the comparison), Part 5 chapter 2 (the honest inventory), and phase0 §3 (blueprint-vs-reality rulings).
- [ ] **Step 2: Write the page** — Z98 vs C89 vs C++98 vs modern Zig vs modern C; what Z98 gives that C89 does not (error unions, coroutines, arena, comptime-introspection builtins) and what it does not (generics, templates, classes, exceptions, threads); the "higher-level C89, not a smaller modern Zig" framing. Comparison statements about other languages are era framing, clearly marked; every Z98 claim is spec-verified. At least one honesty callout. No sample, no figure.
- [ ] **Step 3: Cross-check** — every Z98 capability claim against `docs/reference/Language_Spec_Z98.md`; no claim that Z98 has a feature the spec does not list.
- [ ] **Step 4: Wire** — sidebar entries; `rel` prev `vol2-00-title.html`, next `vol2-02-types.html` if shipped, else the nearest shipped page; update neighbors.
- [ ] **Step 5: Verify** — `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume II chapter 1 — the honest comparison`.

---

### Task 6: Chapter 2 — The type system

**Files:**
- Create: `docs/sf/manuals/en/vol2-02-types.html`
- Create: `docs/sf/manuals/src/vol2/types2.z98`
- Modify: `todo-figures-list.html`; `en/toc.html`; `en/vol2-00-title.html`; `en/index.html`, `en/search.html` where they list chapters; adjacent shipped pages' `rel`/footer; every shipped `en/vol2-*.html` sidebar.

**Interfaces:**
- Consumes: spec §2.2 chapter 2; blueprint line 145; Task 0's width/coercion verdicts.
- Produces: chapter 2; Figure (expected 19); `types2.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 2; blueprint line 145; the Language Spec's type sections.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe primitive widths, arbitrary widths `u1`..`u64`, `isize`/`usize`, `bool`/`void`/`noreturn`/`c_char`, the `@sizeOf`-vs-`@bitSizeOf` distinction, and the "no implicit `i32`↔`usize` coercion" claim. STOP if any claim is false.
- [ ] **Step 3: Author `types2.z98`** — print/observe each type's size, bit-size, and a coercion from each direction; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — 8–14 pages; "Common mistakes" (assuming C's implicit integer conversions; expecting `sizeof` to equal declared width); "Where to go next"; honesty callout where widths surprise.
- [ ] **Step 5: Cross-check** — every type claim against the spec and the emitted run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 19) + row.
- [ ] **Step 7: Wire + verify** — sidebars/`toc`/title/index; `rel` prev `vol2-01-honest-comparison.html`, next nearest shipped; neighbors updated; `check.sh`; `build.sh`.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 2 — the type system`.

---

### Task 7: Chapter 3 — Pointers

**Files:**
- Create: `docs/sf/manuals/en/vol2-03-pointers.html`
- Create: `docs/sf/manuals/src/vol2/pointers.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 3; blueprint line 146; Task 0's builtin-name map.
- Produces: chapter 3; Figure (expected 20); `pointers.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 3; blueprint line 146.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe `*T`, `*const T`, `*volatile T`, `[*]T`, `**T`; `&`/`.*`; `ptr[i]` only on many-item pointers; `ptr.field` auto-deref; `const` frontend-only and `volatile` preserved; each pointer builtin's real Z98 name. STOP on any mismatch.
- [ ] **Step 3: Author `pointers.z98`** — one verified demonstration per form and builtin; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — "Common mistakes" (`ptr[i]` on a one-pointer, assuming `const` reaches C, modern-Zig builtin spellings); "Where to go next"; honesty callout for the limits.
- [ ] **Step 5: Cross-check** — every operator and builtin against the spec and the compiler source.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 20) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6; `check.sh`; `build.sh`.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 3 — pointers`.

---

### Task 8: Chapter 4 — Aggregates I: structs

**Files:**
- Create: `docs/sf/manuals/en/vol2-04-structs.html`
- Create: `docs/sf/manuals/src/vol2/shapes.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 4; blueprint line 147.
- Produces: chapter 4; Figure (expected 21); `shapes.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 4; blueprint line 147.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe field order/layout, `@offsetOf`, `@sizeOf`, `@alignOf`, and nested structs; confirm the printed offsets against the spec's layout rules. STOP if the compiler and the spec disagree.
- [ ] **Step 3: Author `shapes.z98`** — a struct with mixed widths, a nested struct, and printed `@offsetOf`/`@sizeOf`/`@alignOf` values; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — "Common mistakes" (C's padding assumptions; `offsetof` syntax); "Where to go next"; honesty callout for layout guarantees.
- [ ] **Step 5: Cross-check** — every value in the page matches the run and the spec.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 21) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 4 — structs`.

---

### Task 9: Chapter 5 — Aggregates II: packed structs

**Files:**
- Create: `docs/sf/manuals/en/vol2-05-packed-structs.html`
- Create: `docs/sf/manuals/src/vol2/wire.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 5; blueprint line 148.
- Produces: chapter 5; Figure (expected 22); `wire.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 5; blueprint line 148.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe LSB-first packing, the 31-bit field cap, `@bitOffsetOf`, `@bitSizeOf`, and a hardware-register/wire-format example; STOP if any claim is false.
- [ ] **Step 3: Author `wire.z98`** — a wire-format packed struct round-tripped to bytes and a register-style packed struct; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — when to use packed vs plain structs; "Common mistakes" (expecting packed layout savings without the width cap; using `@offsetOf` instead of `@bitOffsetOf`); "Where to go next"; honesty callout for the cap.
- [ ] **Step 5: Cross-check** — every offset/size in the page matches the run and the spec.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 22) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 5 — packed structs`.

---

### Task 10: Chapter 6 — Aggregates III: enums

**Files:**
- Create: `docs/sf/manuals/en/vol2-06-enums.html`
- Create: `docs/sf/manuals/src/vol2/color.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 6; blueprint line 149; Task 0's enum-builtin names.
- Produces: chapter 6; Figure (expected 23); `color.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 6; blueprint line 149.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe `enum`, `enum(uN)`, the enum conversion builtins (real Z98 names), and inclusive/exclusive enum ranges in `switch`. STOP on any mismatch.
- [ ] **Step 3: Author `color.z98`** — a plain enum, a widened enum, conversions both ways, and a `switch` over enum ranges; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — "Common mistakes" (`@enumToInt`/`@intToEnum` spellings; comparing enums as integers; forgetting the mandatory `else`); "Where to go next"; honesty callout for the no-`anyerror`-style limits on enum introspection.
- [ ] **Step 5: Cross-check** — every conversion and range behavior against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 23) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 6 — enums`.

---

### Task 11: Chapter 7 — Aggregates IV: unions

**Files:**
- Create: `docs/sf/manuals/en/vol2-07-unions.html`
- Create: `docs/sf/manuals/src/vol2/variant.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 7; blueprint line 150.
- Produces: chapter 7; Figure (expected 24); `variant.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 7; blueprint line 150.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe bare unions, packed unions, tagged unions, naked tags, and anonymous struct payloads; `switch` on a tagged union with `.tag`/payload capture. STOP on any mismatch.
- [ ] **Step 3: Author `variant.z98`** — one tagged-union variant program with a naked tag and an anonymous struct payload, plus a packed union; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — when each form is right; "Common mistakes" (C's untagged unions; accessing the wrong member; assuming a tag is automatic in a bare union); "Where to go next"; honesty callout on safety.
- [ ] **Step 5: Cross-check** — every form and payload access against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 24) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 7 — unions`.

---

### Task 12: Chapter 8 — Aggregates V: tuples

**Files:**
- Create: `docs/sf/manuals/en/vol2-08-tuples.html`
- Create: `docs/sf/manuals/src/vol2/pair.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 8; blueprint line 151.
- Produces: chapter 8; Figure (expected 25); `pair.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 8; blueprint line 151.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe `struct { T1, T2 }`-style tuples, `.{a, b}` initialization, `t.0`/`t.1` access, `print("{}", .{t})`, and a grouped return. STOP on any mismatch.
- [ ] **Step 3: Author `pair.z98`** — a tuple used for a grouped return and printed with `{}`, plus field access; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — why tuples exist (print, grouped returns) and why not to use them elsewhere; "Common mistakes" (expecting named fields; serializing them like structs); "Where to go next"; honesty callout.
- [ ] **Step 5: Cross-check** — every tuple claim against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 25) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 8 — tuples`.

---

### Task 13: Chapter 9 — Arrays and slices

**Files:**
- Create: `docs/sf/manuals/en/vol2-09-arrays-slices.html`
- Create: `docs/sf/manuals/src/vol2/strings.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 9; blueprint line 152.
- Produces: chapter 9; Figure (expected 26); `strings.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 9; blueprint line 152.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe `[N]T`, `[]T`, `[]const T`, `.ptr`, `.len`, slicing `arr[a..b]`/`arr[a..]`, array→slice coercion, and const propagation. STOP on any mismatch.
- [ ] **Step 3: Author `strings.z98`** — string/array handling with `.ptr`/`.len`, slicing both forms, and a const-propagation demonstration; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — "Common mistakes" (C's decaying array pointers; off-by-one slicing; expecting mutation through `[]const T`); "Where to go next"; honesty callout.
- [ ] **Step 5: Cross-check** — every coercion and slice bound against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 26) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 9 — arrays and slices`.

---

### Task 14: Chapter 10 — Control flow, in full

**Files:**
- Create: `docs/sf/manuals/en/vol2-10-control-flow.html`
- Create: `docs/sf/manuals/src/vol2/control.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 10; blueprint line 153.
- Produces: chapter 10; Figure (expected 27); `control.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 10; blueprint line 153.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe `if` expressions, optional capture `if (x) |v|`, `while` with a continue-expression, `while (opt) |v|`, `for` with index capture, `switch` inclusive/exclusive ranges, the mandatory `else` prong, labeled loops, and value-less labeled blocks. STOP on any mismatch.
- [ ] **Step 3: Author `control.z98`** — one program per construct family in a single runnable program (or a small set of programs, transcripts captured); compile+run; capture the transcripts.
- [ ] **Step 4: Write the page** — "Common mistakes" (C's `for (;;)`, missing `else` prong, a value-labeled block, `continue` reaching the wrong part of a `for`); "Where to go next"; honesty callout.
- [ ] **Step 5: Cross-check** — every construct against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 27) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 10 — control flow in full`.

---

### Task 15: Chapter 11 — `defer` and `errdefer`

**Files:**
- Create: `docs/sf/manuals/en/vol2-11-defer.html`
- Create: `docs/sf/manuals/src/vol2/defer.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 11; blueprint line 154.
- Produces: chapter 11; Figure (expected 28); `defer.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 11; blueprint line 154.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe LIFO ordering on normal and error paths, `break`/`continue`/`return` rejected inside (`error[3051]`–`[3053]`), `try` rejected inside (`error[3054]`), and the `defer`-vs-`errdefer` difference. STOP on any mismatch.
- [ ] **Step 3: Author `defer.z98`** — nested defers on the success and error paths, an `errdefer` with cleanup, and the boundary rejects captured as transcripts; compile+run; capture.
- [ ] **Step 4: Write the page** — "Common mistakes" (C's `goto cleanup`, expecting `defer` inside cleanup to redirect, `return` in cleanup); "Where to go next"; honesty callout.
- [ ] **Step 5: Cross-check** — every ordering and diagnostic against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 28) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 11 — defer and errdefer`.

---

### Task 16: Chapter 13 — Optionals

**Files:**
- Create: `docs/sf/manuals/en/vol2-13-optionals.html`
- Create: `docs/sf/manuals/src/vol2/lookup.z98`
- Modify: `todo-figures-list.html`; nav pages; `en/vol2-12-error-unions.html` and `en/vol2-14-arena.html` `rel`/footer updates (chain `vol2-12 → vol2-13 → vol2-14`).

**Interfaces:**
- Consumes: spec §2.2 chapter 13; blueprint line 156.
- Produces: chapter 13; Figure (expected 29); `lookup.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 13; blueprint line 156.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe `?T`, `null`, `orelse`, `if (opt) |v|`, `while (opt) |v|`, and the `?*T` representation claim. STOP on any mismatch.
- [ ] **Step 3: Author `lookup.z98`** — a lookup returning `?*T` consumed with `if`/`orelse`/`while`; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — "Common mistakes" (sentinel pointers, `orelse` on an error union, dereferencing a null optional); "Where to go next"; honesty callout.
- [ ] **Step 5: Cross-check** — every optional form and the representation claim against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 29) + row.
- [ ] **Step 7: Wire + verify** — sidebars/`toc`/title/index; `rel` prev `vol2-12-error-unions.html`, next `vol2-14-arena.html`; update ch12's `rel` next/footer and ch14's `rel` prev/footer; `check.sh`; `build.sh`.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 13 — optionals`.

---

### Task 17: Chapter 16 — No methods, no generics, no `comptime`

**Files:**
- Create: `docs/sf/manuals/en/vol2-16-no-methods.html`
- Create: `docs/sf/manuals/src/vol2/shapes2.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 16; blueprint line 159.
- Produces: chapter 16; Figure (expected 30); `shapes2.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 16; blueprint line 159.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — compile a manual vtable (`struct { fn(*void) void, *void }`), the init-function pattern, and a `comptime`-replacement builtin; STOP if the vtable pattern cannot be expressed.
- [ ] **Step 3: Author `shapes2.z98`** — a shape interface via a manual vtable with an init function; compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — what "no methods/generics/comptime" means in practice; "Common mistakes" (calling `obj.method()`, expecting template instantiation, reaching for `comptime`); "Where to go next"; honesty callout for what is replaced by builtins and manual dispatch.
- [ ] **Step 5: Cross-check** — every claim against the spec and the run.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 30) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 16 — no methods, no generics, no comptime`.

---

### Task 18: Chapter 17 — The standard library tour

**Files:**
- Create: `docs/sf/manuals/en/vol2-17-stdlib.html`
- Create: `docs/sf/manuals/src/vol2/stdio.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 17; blueprint line 160; Task 0's `std_*` module map.
- Produces: chapter 17; Figure (expected 31); `stdio.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 17; blueprint line 160; Task 0's module map against `sf/src/std_*.zig`.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — for each module the chapter will cover, compile a one-line probe; if the blueprint names a module that does not exist, STOP and present the corrected list (or drop with a ruling).
- [ ] **Step 3: Author `stdio.z98`** — a tour program touching the verified modules (I/O, strings/bytes, memory, math, debug, arena, and any networking/async surface verified in Step 2); compile+run; capture the transcript.
- [ ] **Step 4: Write the page** — one page per module, not exhaustive, pointing to `vol4-15-builtins.html` and the planned Reference stdlib page; "Common mistakes" (assuming POSIX/`stdio.h` APIs; assuming more modules than ship); "Where to go next"; honesty callout for the tour's limits.
- [ ] **Step 5: Cross-check** — every signature against the module source.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 31) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 17 — the standard library tour`.

---

### Task 19: Chapter 18 — `print` and the format string

**Files:**
- Create: `docs/sf/manuals/en/vol2-18-print.html`
- Create: `docs/sf/manuals/src/vol2/print.z98`
- Modify: `todo-figures-list.html`; nav pages as in Task 6.

**Interfaces:**
- Consumes: spec §2.2 chapter 18; blueprint line 161; the closed print-formatting plan's verified behavior.
- Produces: chapter 18; Figure (expected 32); `print.z98`.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 18; blueprint line 161; `docs/superpowers/specs/2026-09-22-z98-print-formatting-design.md` and `repro/mi_matrix/EXPECTED_FAIL.md` for the current accepted/rejected forms.
- [ ] **Step 2: Verify feasibility first (STOP if it fails)** — probe `{}`, `{d}`, `{x}`, `{c}`, `{s}` on the supported types, tuple-literal arguments, and `error[3013]` for an unknown specifier. Document the exact accepted set; do not describe behavior the compiler does not implement.
- [ ] **Step 3: Author `print.z98`** — every verified specifier and the unknown-specifier reject captured as a transcript; compile+run; capture.
- [ ] **Step 4: Write the page** — the one variadic form and its restrictions; "Common mistakes" (printf verbs, `{}` on unsupported types, missing tuple); "Where to go next"; honesty callout for the small format set.
- [ ] **Step 5: Cross-check** — every format rule against the compiler and the print-formatting residuals.
- [ ] **Step 6: Figure** — Win9x placeholder (expected Figure 32) + row.
- [ ] **Step 7: Wire + verify** — as in Task 6.
- [ ] **Step 8: Commit** — `docs(manual): add Volume II chapter 18 — print and the format string`.

---

### Task 20: Chapter 19 — Idioms and best practices

**Files:**
- Create: `docs/sf/manuals/en/vol2-19-idioms.html`
- Modify: `en/toc.html`; `en/vol2-00-title.html`; `en/index.html`, `en/search.html` where they list chapters; every shipped `en/vol2-*.html` sidebar.

**Interfaces:**
- Consumes: spec §2.2 chapter 19; blueprint line 162; the shipped chapters it summarizes.
- Produces: chapter 19; the cross-reference hub for the shipped examples.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 19; blueprint line 162.
- [ ] **Step 2: Write the page** — arena ownership, init functions, manual vtables, dual arenas, runtime initialization, `undefined` is not zero; cite the shipped `src/vol2/` examples by name (path references, not new code); "Common mistakes" (reaching for constructors/destructors, zeroing by default, hidden allocations); "Where to go next". No sample, no figure.
- [ ] **Step 3: Cross-check** — every idiom against the chapters that taught it and the spec; no new unverified claims.
- [ ] **Step 4: Wire + verify** — sidebars/`toc`/title/index; `rel` prev `vol2-18-print.html`, next `vol2-20-whats-next.html` if shipped, else nearest; neighbors updated; `check.sh`; `build.sh`.
- [ ] **Step 5: Commit** — `docs(manual): add Volume II chapter 19 — idioms and best practices`.

---

### Task 21: Chapter 20 — What you've learned, what's next

**Files:**
- Create: `docs/sf/manuals/en/vol2-20-whats-next.html`
- Modify: `en/toc.html`; `en/vol2-00-title.html`; `en/index.html`, `en/search.html` where they list chapters; every shipped `en/vol2-*.html` sidebar.

**Interfaces:**
- Consumes: spec §2.2 chapter 20; blueprint line 163; the volume's shipped chapters.
- Produces: chapter 20; the Volume III handoff.

- [ ] **Step 1: Read the sources** — spec §2.2 chapter 20; blueprint line 163; the Volume III blueprint row (Part 5).
- [ ] **Step 2: Write the page** — what the reader can now do; the handoff to Volume III (no shipped page yet: name it in prose, footer/`rel` next stays `vol4-00-title.html` as chapter 12 does); the honesty callout. No sample, no figure.
- [ ] **Step 3: Cross-check** — the summary claims match what the volume actually taught; no overselling.
- [ ] **Step 4: Wire + verify** — sidebars/`toc`/title/index; `rel` prev `vol2-19-idioms.html`, next `vol4-00-title.html`; neighbors updated; `check.sh`; `build.sh`.
- [ ] **Step 5: Commit** — `docs(manual): add Volume II chapter 20 — what you have learned`.

---

### Task 22: Volume II closeout — whole-set review and verification sweep

**Files:**
- Review: all `docs/sf/manuals/**`; modify as needed.
- Modify: `docs/superpowers/specs/2026-09-25-z98-manual-volume-II-design.md` (status line).
- Rotate (iff a compiler amendment moved the fixed point): `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md`, `release/seed/SEED_README.txt` via the archive script.

**Interfaces:**
- Consumes: all 21 chapters and every example.
- Produces: the reviewed, verified volume; the final seed state.

- [ ] **Step 1: Whole-set mechanical gate** — `bash docs/sf/manuals/check.sh` passes (links, `rel`, lang bar, charset, forbidden list, figure 1:1, no-CSS baseline); `bash docs/sf/manuals/build.sh` succeeds and is idempotent; `serve.sh` serves and the pages fetch.
- [ ] **Step 2: Re-run every example** — rebuild the seed compiler; compile+run every `src/vol2/*.z98` and confirm each page's embedded transcript still matches byte-for-byte; re-run any `-osw`/`wine` claim.
- [ ] **Step 3: Navigation continuity** — every shipped chapter is linked in every shipped page's sidebar, `en/toc.html`, and `en/vol2-00-title.html`; no `(planned)` marker remains for a shipped chapter; the `rel` prev/next chain is continuous `vol2-00 → vol2-01 → … → vol2-20 → vol4-00-title`; footers match.
- [ ] **Step 4: Figure workflow** — placeholder↔`todo-figures-list.html` is 1:1 with unique numbers and each row names a concrete capture.
- [ ] **Step 5: Spec status** — mark the design spec's status implemented; record any operator rulings and residuals.
- [ ] **Step 6: Seed** — if a compiler amendment moved the fixed point, verify the two-hop closure from the committed seed, rotate via `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`, and re-verify the post-rotation closure. If nothing moved, record that the seed is unchanged (no rotation).
- [ ] **Step 7: Fix** any failure found (website only; a compiler defect found here is a new amendment, not a fix).
- [ ] **Step 8: Commit** — `git add docs/sf/manuals docs/superpowers/specs/2026-09-25-z98-manual-volume-II-design.md && git commit -m "docs(manual): Volume II closeout — whole-set review and verification sweep"`.

---

## Self-Review

- **Spec coverage:** spec §1 (scope) → File Structure + the 21 chapter tasks; §2 (chapter contracts) → spec §2.1/§2.2 consumed by every chapter task; §3.2 (chapter shape) → the chapter-task steps 4–5; §3.3 (cross-refs) → step 4 and the honesty/`Where to go next` requirements; §3.4 (non-contiguous navigation) → step 7 and Task 22 step 3; §3.5 (figures) → step 6 and Task 22 step 4; §4 (accuracy/defect policy) → Global Constraints + the per-chapter STOP steps; §5 (amendments + closeout-only rotation) → the plan header and Task 22 step 6; §6 (verification) → "Compiler under test" + steps 3/5/8 + Task 0 + Task 22; §7 (task sequence) → Tasks 0–22; §8 (open items) → Task 0; §9 (plan index) → this header's Sequence.
- **Placeholder scan:** every chapter task names its page file, sample file, figure number, nav targets, and observable transcript; the only values left to runs are the captured transcripts and offset/size numbers, which the tasks mandate be produced by real runs and cross-checked. No `TBD`/`TODO`.
- **Type/name consistency:** page filenames match spec §2.1 and are unique; sample filenames match the blueprint Part 4 names (chapter 12's deviation recorded); `rel` targets are existing files; figure numbers are assigned uniquely (Tasks 2/3 = 17/18, Tasks 6–15 = 19–28, Task 16 = 29, Tasks 17–19 = 30–32; Task 0 confirms the base); the figure row columns match Phase 0 (`Page | Figure | Caption | Claim | What to capture`).
- **Open risks the tasks must verify (STOP if they fail):** the arena API (Task 2), the builtin inventory's fit (Task 3), every chapter's feasibility step, chapter 17's module list, chapter 18's format set. Each STOP escalates to an operator-ruled amendment; the plan's phase order means Task 0 and the three mental-shift chapters surface the highest-risk findings earliest.
- **Scope discipline:** the plan is website-only; the seed is not rotated except by Task 22 after an amendment; any compiler defect found while verifying a claim is a STOP, not a fix.

---

## Defect intake (operator-ruled 2026-09-26)

Task 0's capability inventory (review-verified) found 12 real compiler-defect candidates that block chapters 3, 6, 7, 8, 9, 10, 11, 12, and 18. The operator ruled the intake order below: repros first (one task, every defect, including cross-module and sibling shapes), then one read-only investigation per defect, **then STOP** for the operator's fix-grouping ruling before any fix task is appended. These tasks are the authorized exception to the website-only constraint for `repro/**`; none of them may touch `sf/src/**`, `scripts/**`, or `release/seed/**`.

**Defect list (source: Task 0 report + its independent review):**
- D1 — one module holding a plain-`defer` function and a `defer`-in-`for` function SIGSEGVs the compiler (ch11)
- D2 — enum `switch` inclusive/exclusive range prongs emit no `case` labels (silent wrong branch; ch6/ch10)
- D3 — missing mandatory `else` accepted; the unmatched value reads an uninitialized temp (ch6/ch10)
- D4 — tuple type `struct { T1, T2 }` / `t.0` / `t[0]` unusable (ch8)
- D5 — slice→`[*]T` implicit coercion emits gcc-invalid C (ch9)
- D6 — annotated float tagged-union payload emits gcc-invalid C (ch7)
- D7 — non-tuple `print(fmt, 5)` silently prints nothing (ch18)
- D8 — error-set `catch |e|` capture prints numeric instead of `error.Name` (ch12)
- D9 — bare-union `@offsetOf` internal error `[3043]` (ch7)
- D10 — single-pointer `p[0]` accepted though the Language Spec says it is rejected (ch3)
- D11 — qualified-prong capture `Shape.circle => |r|` resolves `r` unbound (ch7)
- D12 — `[]const T`→`[]T` const-discarding coercion is warning-only (ch9)

- **Task D0 (F) — the complete defect repro set.** Create committed repros for D1–D12 under `repro/vol2_defects/<NN>_<slug>/` (each self-contained: `main.zig` plus helper modules where a cross-module variant is needed, and a `NOTES.md`), plus `repro/vol2_defects/README.md` (index: defect → directory → module-scope claim → minimal repro command) and `repro/vol2_defects/run_all.sh` (rebuild-free runner that compiles each case with the seed-built `zig1_5_clean` and records rc/stdout/stderr). Requirements: every case must reproduce its defect on the seed v88 compiler (RED evidence captured); each defect must carry the in-module shape plus the cross-module (`_xmod`) shape and the sibling shapes that plausibly share the root cause (and passing controls where a sibling does not fail, so the investigation has a boundary); wrong-code cases must include the emitted-C excerpt or gcc error that shows the failure; the Zig 0.15.2 oracle comparison is recorded where it clarifies expected semantics. No compiler changes, no `sf/src` edits. Commit: `test(repro): add the Volume II defect repro set`.

- **Tasks D1–D12 (I) — one read-only investigation per defect.** Each investigation consumes its repro directory and writes `.superpowers/sdd/2026-09-25-z98-manual-volume-II-plan/task-D<N>-report.md` with: exact root cause (file/function/line), the full failing shape family (from the repros and any additional probes), what stays correct (passing controls), candidate fix approach(es) with trade-offs, blast radius (which gate programs/fixtures could move), predicted gate impact, and a proposed fix group (which other defects would naturally be fixed together). No `sf/src` edits, no commits; probes stay under `/tmp`.

- **STOP after D1–D12.** No fix task (F) may be dispatched until the operator reads the investigations and rules on the fix grouping.

---
