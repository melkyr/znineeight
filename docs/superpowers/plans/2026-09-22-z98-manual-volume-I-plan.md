# Z98 Manual — Volume I (Getting Started) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author all sixteen chapters of Volume I (Getting Started), English, into the Phase 0 website under `docs/sf/manuals/`, each chapter carrying a runnable example, a "Common mistakes" list, and a "Check yourself" exercise, every example compile+run verified against the current compiler.

**Architecture:** One plan, sixteen chapter tasks plus a closeout. Each chapter task is the same shape: author the example program(s) under `src/vol1/`, capture the real transcript, write the page from the Phase 0 template (HTML 4.0 Transitional, CSS1, presentational baseline), cross-check every claim against `docs/reference/Language_Spec_Z98.md` and source, add the figure placeholder(s) and matching `todo-figures-list.html` row(s), wire the chapter's navigation incrementally, verify with `check.sh`/`build.sh`, and commit. The site is correct after every commit; Task 17 is the whole-set review and verification sweep. The plan is website-only **except** the scoped compiler I/F pair of AMENDMENT 1 (Tasks 5A/5B).

**Tech Stack:** Hand-authored HTML 4.0 Transitional, CSS1, vanilla 1998-era JavaScript (`doc.js`), GIF assets, Python 3 standard library (`check.py`), the seed-built `zig1` + `gcc -m32` for example verification, git.

**Spec:** `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (program-level; binding for this and every later volume plan). Blueprint: `docs/sf/manuals/manuals_blueprint.txt` (Parts 1, 3, 9, 10).

**Sequence:** PREVIOUS plan: `docs/superpowers/plans/2026-09-20-z98-manual-phase0-plan.md` (infrastructure + cross-archetype slice; Phase 0 COMPLETE). NEXT plan: the Volume II plan (Phase 2).

**AMENDMENT 1 (operator ruling 2026-09-22):** verifying chapter 4 found that the compiler's default standard-library lookup (`<exe_dir>/lib`) fails on Windows: `pal.fileExists` is `fopen(path,"r")` (`sf/src/pal.zig:54-63`), and `fopen` on a directory fails on win32, so `phase_ImportResolution` does not add `<exe_dir>/lib` as a search dir (`sf/src/main.zig:436-438`) and the reader must pass `-I lib`. The operator ruled (option "a") to open a scoped compiler I/F pair to fix it. **Task 5A (I)** investigates the lookup and the minimal fix; **Task 5B (F)** implements it (a directory check for the default lib path), with a regression fixture, the gate battery, and a seed rotation. Tasks 5A/5B are the **only** tasks permitted to touch `sf/src`, add fixtures/repros, run the compiler gate battery, and rotate the seed; every other task remains website-only. After 5B lands, chapter 4 (and chapter 3's inventory) are re-verified to state the compiler's real behavior.

**AMENDMENT 2 (operator ruling 2026-09-22):** verifying chapter 5 found a real compiler defect — a call to an undefined member of a **nested** module (`std.io.printt(...)`) is silently dropped (rc=0, no diagnostic, the call absent from the emitted C), while `std.nope()` correctly reports `error[3042]`; official Zig rejects the call. The operator ruled (option "a") to open a scoped compiler I/F pair. **Task 6A (I)** investigates the nested-module member-call resolution/lowering path; **Task 6B (F)** fixes it to emit an unknown-member diagnostic with 0 `.c`, with a regression fixture, the gate battery, and a seed rotation. Tasks 6A/6B join 5A/5B as the only tasks permitted to touch `sf/src`, add fixtures/repros, run the compiler gates, and rotate the seed.

**AMENDMENT 3 (operator ruling 2026-09-22):** Task 6B's review found a second invalid-construct defect on the same nested-module member-call path — a call to a **defined but non-function** member (`std.io.INVALID_FD()`) is not validated as callable; the compiler emits an indirect call to the value (`(void)zG_…_INVALID_FD();`), which fails gcc, with no diagnostic (rc=0). The operator ruled (option "a") to open a scoped compiler I/F pair. **Task 6C (I)** maps every member-call shape on a nested-module base that produces no diagnostic and decides the correct diagnostics; **Task 6D (F)** implements the fix (diagnose a call whose callee is not a function; 0 `.c`), with a fixture, the gate battery, and a seed rotation. Tasks 6C/6D join 5A/5B/6A/6B as the only tasks permitted to touch `sf/src`, fixtures, and the seed.

**AMENDMENT 4 (operator ruling 2026-09-22):** Task 6's review found a third invalid-construct defect on the call path — a call to an **undefined free function** (`nope()`) compiles rc=0 with no diagnostic and emits an undeclared `nope` in the C (gcc failure); Task 6D's variant-C check skips `TYPE_VOID`/`TYPE_UNDEFINED` callees. The operator ruled (option "a") to open a scoped compiler I/F pair. **Task 6E (I)** investigates the unresolved-free-function call path (and any other unresolved-callee shape that produces no diagnostic); **Task 6F (F)** fixes it (diagnose + 0 `.c`), with a fixture, the gate battery, and a seed rotation. Tasks 6E/6F join 5A/5B/6A/6B/6C/6D as the only tasks permitted to touch `sf/src`, fixtures, and the seed.

**AMENDMENT 5 (operator ruling 2026-09-22):** the operator ruled to fix the undeclared-identifier defect at the **root cause** — **variant S** (`semanticAnalyzerResolveIdent`/sema), not the call-only lowering variant L — and to precede the fix with a dedicated investigation. **Task 6G (I)** investigates the S variant in depth (the exact sema change; the full blast radius including the `diag_excerpt_multifile_xmod` re-baseline; the `nope.foo` double-diagnosis dedup; the `undefined()` residual; the correct diagnostic code; and the interaction with the 6B/6D paths). **Task 6F (F)** then implements **variant S** (re-scoped). Tasks 6G/6F remain in the scoped `sf/src` exception (AMENDMENTS 1–5).

**AMENDMENT 6 (operator ruling 2026-09-22):** verifying chapter 6 found that the compiler does not enforce `const` — a local `const x = 1; x = 2;`, a write through `*const T`, and a module-level const reassignment all compile with no diagnostic (contradicting spec §1.7 `docs/reference/Language_Spec_Z98.md:36`/`:172` and the design of record `docs/sf/Design_p2.md:1375`; `ERR_3002_INVALID_ASSIGNMENT` is reserved but unused). The operator confirmed zig0 (the C++ bootstrap) enforces it (`src/bootstrap/type_checker.cpp:1841`/`:1893`, `isLValueConst`), so zig1's missing check is a regression, and ruled (option "a") to open a scoped compiler I/F pair. **Task 7A (I)** investigates the assignment/compound-assignment paths and zig0's `isLValueConst` semantics; **Task 7B (F)** implements the check (const vars, `*const T` deref, `[]const T` element, params/captures), with a fixture, the gate battery, and a seed rotation. Tasks 7A/7B join the scoped `sf/src` exception (AMENDMENTS 1–6). After 7B lands, Task 7 (chapter 6) resumes.

**AMENDMENT 7 (operator rulings 2026-09-22, m1061 + m1079):** Task 7B's review demanded a "scope-aware" const l-value lookup using **zig0** as the oracle; that fix round (`fa553205`) makes zig1 ACCEPT a program in which an inner-block `const` shadows an outer `var`. The operator ruled that the authority is **official Zig**, not zig0, and to **reject what needs rejecting through the I/F series**. **Task 7B-revert** undoes `fa553205`. **Task 7C (I)** investigated the rule against official Zig 0.15.2: Zig rejects **all** shadowing of an outer identifier — **including function-local → module/global** (so the original "module/global stays legal" assumption was wrong); zig1 currently enforces none. **Operator ruling m1079:** first run the **migration task 7M** — de-shadow the 10 real local-shadow sites in the compiler's own `sf/src` (parser/lower/c89_emit), verify the self-compile still succeeds, and rotate the seed — then use "scope 1" (full Zig fidelity: reject local→container too) for the rejection. **Task 7D (F)** implements the rejection, with a fixture, the gate battery, and a seed rotation. Tasks 7B-revert/7C/7M/7D join the scoped `sf/src` exception (AMENDMENTS 1–7). After 7D lands, Task 7 (chapter 6) resumes.

**AMENDMENT 8 (operator ruling 2026-09-22, m1130):** verifying chapter 6 found that `print` of an `f32` prints a wrong value (`1.5` → `1`): `getPrintFnName` (`sf/src/c89_emit.zig:5474-5502`) has no `f32_type` arm, so an `f32` argument falls through to `std_print_i32` — a silent miscompile of a legal program (spec §1 lists `f32`; §4 `print` supports `{}`/`{d}`). The operator approved a scoped compiler I/F pair and chose approach (a): reuse `std_print_f64` with a `(double)` widening. **Task 7E (I)** investigates the full `print` type-dispatch gap (which type kinds reach the `std_print_i32` default, official Zig's behavior for each, the fix, the blast radius, and the 7F verification plan); **Task 7F (F)** implements the fix (fixture + standalone repro + gate battery + seed rotation) AND, in the same task, updates the chapter-6 page (remove the now-stale f32 workaround note; print the `f32` directly) and fixes the two open Task-7 review findings (`vol1-05-first-program.html:46` restore `<b>Your first program</b>`; `vol1-06-variables-types.html:198` "Four"→"Five"). Tasks 7E/7F join the scoped `sf/src` exception (AMENDMENTS 1–8); after 7F lands, Task 7 (chapter 6) is closed.

**AMENDMENT 9 (operator ruling 2026-09-22, m1146):** after Task 7F fixed the f32 misprint, the operator ruled that the OTHER `print` dispatch/format divergences found by 7E must NOT be left out — extend the scope to fix them all, matching official Zig. **Task 7G (I)** investigates the full set (the `getPrintFnName` fall-through mis-routes: `usize` > 2^31-1, arbitrary-width ints of size 8 (`u40`/`i40`), wide-backed enums, `error_set`, array/pointer/fn-value silent garbage, and aggregate/error-union/tagged-union/tuple/optional gcc hard-errors; plus the `{x}`/`{c}`/`{s}` format divergences on integers and floats, and the integer-valued-float `.0` formatting) and specifies for each whether to FIX the routing/format or CLEAN-REJECT, matching Zig 0.15.2, with the exact fix sites, diagnostic codes, blast radius, and the 7H verification plan. **Task 7H (F)** implements it (fixture + standalone repro + gate battery + seed rotation). Tasks 7G/7H join the scoped `sf/src` exception (AMENDMENTS 1–9). Chapter 6 is already closed by 7F.

**AMENDMENT 10 (operator ruling 2026-09-22, m1202):** verifying chapter 7 (Task 8) found that `@as(<signed>, <negative literal>)` used as a **binary operand** loses its signed target — it is lowered as the `u64` constant `18446744073709551614ULL`, so `v / @as(i32, -2)` prints `0` (Zig: `-3`) and `v * @as(i32, -2)` traps under `-fsafe` (rc 133). The emitted C is `std_print_i32((int)(v / (unsigned int)(18446744073709551614ULL)));`. It is correct when `@as(i32, -2)` is printed directly, when the target is `i64`/`i8`, when a `const` holds the value, and for a literal `7 / -2` — so the defect is specific to `@as(signed, negative)` as an operand (likely the Task 11U `@as` fold). The operator ruled to open a scoped I/F pair: **Task 8A (I)** investigates the `@as`-operand lowering (root cause, the exact fix site, the fix, the blast radius, and the 8B verification plan); **Task 8B (F)** implements the fix (fixture + standalone repro + gate battery + seed rotation). Tasks 8A/8B join the scoped `sf/src` exception (AMENDMENTS 1–10); the seed-rotation list adds 8B. Chapter 7's page does not use the broken form and is unaffected. **Operator ruling m1210:** the 8B fix must cover **every signed width** (`i8`/`i16`/`i32`/`i64`/`isize` and arbitrary-width signed), not only `i32` — the 8A investigation found `i64`/`i8` are also wrong **as operands** (correct only for a direct print). Also: do **not** parallelize subagent dispatches.

**AMENDMENT 11 (operator ruling 2026-09-23, m1231):** verifying chapter 8 (Task 9) found three shapes where zig1 silently ACCEPTS invalid Zig (all rejected by official Zig 0.15.2): (a) `if (a = 3)` — assignment in a condition; (b) `if (cond) 1` used as an expression without `else`; (c) `if (a)` with a non-`bool` condition. The operator ruled to open a scoped I/F pair: **Task 9A (I)** investigates the three gaps (root cause, fix site(s), the exact rejects matching Zig, the blast radius, the 9B plan); **Task 9B (F)** implements the rejects (fixture + standalone repro + gate battery + seed rotation) AND fixes the stale spec example `docs/reference/Language_Spec_Z98.md` §3.1 (the brace-less `if (a) return 1; else return 0;` is rejected by the compiler). Tasks 9A/9B join the scoped `sf/src` exception (AMENDMENTS 1–11); the seed-rotation list adds 9B. Chapter 8's page documents gap (a) honestly and does not rely on (b)/(c). **Operator rulings m1240 (binding):** (1) 9B's scope **includes the manual pages** (`docs/sf/manuals/**` — rewrite the chapter-8 section that documents gap (a) as accepted, + regenerate `dist/`); (2) implement (a) at the **parser** level (upstream), even though it cascades extra `error[2000]`s; (3) (b) must **match Zig** — a value `if` without `else` is rejected only when the then-branch is not void/noreturn and the condition is not comptime-known-true (the comptime fold must produce a bool so a comptime-true condition is suitable for an `if`); (4) the spec §3.1 fix is authorized; (5) the related gaps (`if (a) |v|` non-optional condition; assignment-as-expression `var x = (a = 3);`) fold into 9B.

**AMENDMENT 12 (operator ruling 2026-09-25, m1251):** two residuals from Task 9B. (i) The comptime-true no-`else` allowance relies on Z98's comptime fold, which does **not** fold comparisons, so `const a: i32 = 1; var x: i32 = if (a == 1) 1;` is rejected although Zig accepts — too narrow a downgrade vs Zig. (ii) A pre-existing backend defect: `_ = if (c) foo();` (a void-then value `if`) is front-end-accepted but lowers to an undeclared temp → gcc failure. The operator ruled to keep Zig parity (the narrowing was too narrow a downgrade) and to fold both into a new scoped I/F pair: **Task 9C (I)** investigates (a) extending the comptime fold to comparisons for the `if`-condition case and (b) the void-then value-`if` lowering defect; **Task 9D (F)** implements both (fixtures + standalone repros + gate battery + seed rotation). Tasks 9C/9D join the scoped `sf/src` exception (AMENDMENTS 1–12); the seed-rotation list adds 9D.

**AMENDMENT 13 (operator ruling 2026-09-23, m1318):** verifying chapter 9 (Task 10) found a silent miscompile: `continue` inside a `for` loop (range or array) jumps to the loop's condition instead of its implicit increment, so the loop never advances and the program hangs (emit/build rc=0, no diagnostic, runtime `timeout` rc=124). Spec §3.2 (`docs/reference/Language_Spec_Z98.md:249`) says `continue` jumps to the next iteration of the innermost `while` **or** `for` loop; `continue` in a `while` and `break` in a `for` are correct. The operator ruled (option "a") to open a scoped compiler I/F pair. **Task 10A (I)** investigates the `for` loop's condition/body/step lowering and the `continue` target selection (root cause, fix site, characterization matrix, blast radius, the 10B plan); **Task 10B (F)** implements the fix (the `continue` edge must reach the implicit-step block), with a regression fixture, the gate battery, and a seed rotation. Tasks 10A/10B join the scoped `sf/src` exception (AMENDMENTS 1–13); the seed-rotation list adds 10B. After 10B lands, Task 10 (chapter 9) resumes. **Operator ruling m1336:** 10B covers BOTH defects — the `for`-continue target AND the independent nested-loop label leak (fixing only one is not worth delaying the other); the 4-MD5 lisp/json re-baseline is authorized provided the runtime behavior is proven identical (PRE vs POST) and ANY anomaly is reported as Important even if pre-existing.

**AMENDMENT 14 (operator ruling 2026-09-23, m1347):** Task 10B's work found a **pre-existing** silent miscompile (present in seed v80 and v81): a plain local `var` declared after a same-named `for` capture in a **sibling** scope loses its declaration and initializer in the emitted C and aliases the stale capture temp, so reads/writes hit the old loop variable (Zig 0.15.2 `c7=12` vs Z98 `c7=0` on v80 / `c7=3` on v81). The operator ruled (option "a") to open a scoped compiler I/F pair. **Task 10C (I)** investigates the local-declaration/capture-temp scoping (root cause, fix site, characterization matrix, blast radius, the 10D plan); **Task 10D (F)** implements the fix, with a regression fixture, the gate battery, and a seed rotation. Tasks 10C/10D join the scoped `sf/src` exception (AMENDMENTS 1–14); the seed-rotation list adds 10D. After 10D lands, Task 10 (chapter 9) resumes.

## Global Constraints

- **Website only, with scoped exceptions (AMENDMENTS 1–14).** Do NOT edit `sf/src/**`, `scripts/**`, fixtures, or `release/seed/**` — EXCEPT Tasks 5A/5B (win32 default-lib-path lookup), 6A/6B (nested-module undefined-member silent drop), 6C/6D (nested-module non-function-member call), 6E/6G/6F (undeclared identifier), 7A/7B (const enforcement), 7M (de-shadow the compiler source), 7C/7D (local declaration shadowing), 7E/7F (f32 print dispatch), 7G/7H (remaining print divergences), 8A/8B (`@as(signed, negative)` operand miscompile), and 9A/9B (invalid condition/`if` forms), and 9C/9D (comptime-fold narrowing + void-then value-`if` lowering), and 10A/10B (`for`-loop `continue` target), and 10C/10D (`var`-after-same-named-`for`-capture aliasing). Only those tasks may edit `sf/src`, add regression fixtures/repros, run the compiler gate battery, and rotate the seed. Every other task leaves the compiler fixed point and seed untouched.
- **STOP on a real compiler defect** found while verifying a claim — report it; do not fix `sf/src`, do not document around it (spec §11). Compiler correctness takes priority over the manual; a defect becomes its own plan.
- **All files under `docs/sf/manuals/`** except this plan/spec.
- **Blueprint-vs-reality rule (spec §3).** The manual documents the current compiler only. When a claim cannot be verified against `docs/reference/Language_Spec_Z98.md` and source, fix the page or drop the claim. Never ship an unreproducible claim.
- **HTML restrictions (spec §6.1).** HTML 4.0 Transitional doctype, authored in the HTML 3.2/4.0 intersection. No HTML5 structural tags (`<section>`, `<article>`, `<nav>`, `<header>`, `<footer>`, `<main>`, `<figure>`). **No `<div>` for structure** — layout uses `<table>`. ISO-8859-1 only, declared `<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">`. Baseline appearance via presentational attributes (`bgcolor`, `align`, `width`, `border`, `cellpadding`, `cellspacing`, `valign`) and `<font>`/`<b>`/`<i>`/`<center>`. Every page carries `<link rel="home|up|prev|next">`, a sidebar TOC, a language bar, and a prev/contents/next footer.
- **CSS restrictions (spec §6.2).** CSS1 only. `z98.css` (screen) and `z98-print.css` (print) are **external linked stylesheets**. **No inline `<style>` blocks.** CSS carries no meaning and no layout — with both stylesheets removed the site must remain legible, navigable, and correctly ordered. No CSS2/CSS3.
- **JS restrictions (spec §6.3).** One file `doc.js`, ≤ 2048 bytes, four functions (`swap`, `tocToggle`, `doSearch`, `preload`), no `document.write`, no browser sniffing.
- **Asset restrictions (spec §6.4).** GIF only — no PNG, no SVG, no web fonts. XBM alternates under `gfx/xbm/`.
- **Forbidden list (spec §6.5, checker-enforced).** HTML5 structural tags; `<div>` structure; PNG/SVG/web fonts; external resources (any `http://`/`https://` in `href`/`src`); inline `<style>`; `<script src>` other than `doc.js`; > 2048 bytes of JS; CSS2/CSS3 properties or selectors.
- **Figures (spec §7).** Terminal transcripts are AI-produced from real runs and rendered in `<pre>`. Win9x screenshots are reserved placeholder boxes plus an entry in `docs/sf/manuals/todo-figures-list.html`; `check.sh` enforces a 1:1 match. The operator captures the screenshots on real Win9x after the plan.
- **Content verification (spec §8).** Every example is compiled with the seed-built `zig1` and `gcc -m32`, actually run, and its transcript matched to the prose; `-osw` claims run under `wine`; every syntax/builtin claim is cross-checked against `docs/reference/Language_Spec_Z98.md` and source.
- **Chapter shape (blueprint Part 3).** Every chapter is 6–10 pages, and ends with a runnable program, a "Common mistakes" list, and a "Check yourself" exercise. The no-code chapters (0, 1, 2, 3, 13, 15) end with "Check yourself" (and, where the blueprint shows a sample, a runnable recap); "Common mistakes" appears wherever the chapter has code. The honesty callout is mandatory in chapters 2 and 15.
- **English only.** The language bar lists only shipped languages (English); the other languages remain plain text marked "(not yet available)".
- **Edits via `edit`/`fastedit` only**; no bulk transforms. Never stage `mnemoria/`, `.opencode/`, or `.zig1_*.tmp`.
- **Reference compiler rebuilt per the seed model** (`release/seed/`). The seed is rotated **only** by Tasks 5B, 6B, 6D, 6F, 7B, 7M, 7D, 7F, 7H, 8B, 9B, 9D, 10B, and 10D (the `sf/src` changes of AMENDMENTS 1–14); no other task rotates it.

## Compiler under test (for example verification)

Build the seed compiler once per session (repo root, relative path required):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
```

Compile and run an example (recipe in `docs/sf/QUICK_REF.md`):

```bash
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out docs/sf/manuals/src/vol1/<prog>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

Capture stdout, stderr, and `rc` as the transcript. For a `-osw`/Win9x claim, emit with `-osw` and run the `.exe` under `wine`. If the emitted script's argument order or default name differs, use the recipe in `docs/sf/QUICK_REF.md` verbatim.

---

## File Structure

**Create (pages, flat in `docs/sf/manuals/en/`):**
- `vol1-01-what-is-programming.html`
- `vol1-02-what-is-z98.html`
- `vol1-03-your-machine.html`
- `vol1-04-installing.html`
- `vol1-06-variables-types.html`
- `vol1-07-arithmetic.html`
- `vol1-08-decisions.html`
- `vol1-09-repetition.html`
- `vol1-10-functions.html`
- `vol1-11-structs.html`
- `vol1-12-arrays.html`
- `vol1-13-reading-errors.html`
- `vol1-14-line-counter.html`
- `vol1-15-whats-next.html`

**Create (examples, `docs/sf/manuals/src/vol1/`):**
- `types.z98`, `math.z98`, `classify.z98`, `count.z98`, `functions.z98`, `point.z98`, `scores.z98`, `wc.z98`
- `errors/err1.z98`, `errors/err2.z98`, `errors/err3.z98`, `errors/err4.z98`, `errors/err5.z98` (deliberately-erroneous; the captured diagnostic is the transcript)

**Modify (existing):**
- `docs/sf/manuals/en/vol1-00-title.html` — expand to the full chapter-0 shape; flip shipped chapter entries to links.
- `docs/sf/manuals/en/vol1-05-first-program.html` — expand to the full chapter shape.
- `docs/sf/manuals/en/toc.html` — link each shipped Volume I chapter.
- `docs/sf/manuals/en/index.html`, `en/search.html` — link the shipped chapters as the volume fills in.
- `docs/sf/manuals/en/search-data.js` — regenerated by `build.sh` (never hand-edited).
- `docs/sf/manuals/todo-figures-list.html` — one row per new placeholder.
- Every already-shipped `docs/sf/manuals/en/vol1-*.html` — flip this chapter's sidebar entry from `(planned)` to a link.

**Reference (read-only):** `docs/sf/manuals/manuals_blueprint.txt` (Part 3 for Volume I), `docs/reference/Language_Spec_Z98.md`, `docs/reference/builtins.md`, `docs/sf/QUICK_REF.md`, `docs/sf/manuals/en/vol4-24-html-style.html` (the template/contract), the existing `en/vol1-00-title.html` and `en/vol1-05-first-program.html`.

---

## How each chapter task works

Every task 1–16 follows this shape. Steps are written out per task below; the shared rules are:

1. **Author the example(s)** under `src/vol1/` (skip where the chapter has none), compile+run with the seed compiler, and capture the exact transcript.
2. **Write the page** from the `vol4-24-html-style.html` skeleton — sidebar (the full Volume I chapter list, own chapter linked, later chapters plain `(planned)`), language bar, `rel` home/up/prev/next, 6–10 pages of prose per the chapter's "Must cover" list, the runnable example(s) with their transcripts in `<pre>`, "Common mistakes" (where the chapter has code), "Check yourself", and the honesty callout where mandated.
3. **Cross-check every claim** against `docs/reference/Language_Spec_Z98.md` and, for builtins/std, the compiler source.
4. **Figures:** add the placeholder box(es) and the matching `todo-figures-list.html` row(s) (1:1).
5. **Wire the chapter:** flip this chapter's sidebar entry from `(planned)` to a link on `en/vol1-00-title.html`, `en/toc.html`, and every already-shipped `en/vol1-*.html` page; set the `rel` prev/next of the newly adjacent pages; link the chapter from `en/index.html` where the volume index lists chapters.
6. **Verify:** `bash docs/sf/manuals/check.sh` passes; `bash docs/sf/manuals/build.sh` succeeds.
7. **Commit:** `git add docs/sf/manuals && git commit -m "docs(manual): add Volume I chapter NN — <title>"`.

---

### Task 1: Chapter 0 — How to read this (expand the title page)

**Files:**
- Modify: `docs/sf/manuals/en/vol1-00-title.html`
- Modify: `docs/sf/manuals/en/toc.html`, `en/index.html`

**Interfaces:**
- Consumes: the Phase 0 template (`en/vol4-24-html-style.html`) and the existing title page.
- Produces: the expanded chapter 0; the volume title page every later task flips entries on.

- [ ] **Step 1: Read the sources** — `manuals_blueprint.txt` Part 3 chapter 0 ("What a manual is, how to use the sidebar, the print stylesheet, the conventions (note/tip/warn/honest callouts)") and the Phase 0 template's admonition blocks.
- [ ] **Step 2: Expand `vol1-00-title.html`** — keep the title, entry/exit state, and chapter list; add the "how to read this" prose (the sidebar, the print stylesheet, the reading paths from blueprint Part 1, and one worked example of each callout: note, tip, warn, caution, honest). No new example program.
- [ ] **Step 3: Cross-check** — every callout shown matches the template's markup; every reading-path statement matches blueprint Part 1.
- [ ] **Step 4: Verify** — `bash docs/sf/manuals/check.sh` passes; `bash docs/sf/manuals/build.sh` succeeds.
- [ ] **Step 5: Commit** — `docs(manual): add Volume I chapter 0 — how to read this`.

---

### Task 2: Chapter 1 — What is a program

**Files:**
- Create: `docs/sf/manuals/en/vol1-01-what-is-programming.html`

**Interfaces:**
- Consumes: the template + the Task 1 title page.
- Produces: chapter 1; the `rel` prev/next links from/to chapter 0 and chapter 2.

- [ ] **Step 1: Read the sources** — blueprint Part 3 chapter 1 ("Input → process → output. The machine as a very literal assistant. No code yet.").
- [ ] **Step 2: Write the page** — the input→process→output model and the "very literal assistant" framing; **no code**. End with "Check yourself" (a short, code-free exercise). No "Common mistakes" (no code). No example program, no figure.
- [ ] **Step 3: Cross-check** — no claim about Z98 that is not in the spec; no code snippet.
- [ ] **Step 4: Verify** — `check.sh` passes; `build.sh` succeeds.
- [ ] **Step 5: Commit** — `docs(manual): add Volume I chapter 1 — what is a program`.

---

### Task 3: Chapter 2 — What is Z98, and why 1998

**Files:**
- Create: `docs/sf/manuals/en/vol1-02-what-is-z98.html`

**Interfaces:**
- Consumes: the template + chapter 1.
- Produces: chapter 2; the honesty-callout instance the later honesty chapters reference.

- [ ] **Step 1: Read the sources** — blueprint Part 3 chapter 2 (the one-paragraph honest framing: "a small language that compiles to C89 and targets Pentium-class machines… writing for those machines in C89 is tedious and writing for them in C++98 is fragile") and the blueprint "What this delivers" honesty rules.
- [ ] **Step 2: Write the page** — the honest framing paragraph, expanded to 6–10 pages; what Z98 is and is not; who the era's real languages were (C89, C++98). **Include the mandatory honesty callout.** End with "Check yourself". No example program, no "Common mistakes" (no code).
- [ ] **Step 3: Figure** — one Win9x placeholder (e.g. "Figure 1 — a Pentium-class machine of the era") + the matching `todo-figures-list.html` row.
- [ ] **Step 4: Cross-check** — the framing matches the blueprint's honesty inventory (Part 5 chapter 2); no overselling.
- [ ] **Step 5: Verify** — `check.sh` passes (figure 1:1); `build.sh` succeeds.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 2 — what is Z98, and why 1998`.

---

### Task 4: Chapter 3 — Your machine

**Files:**
- Create: `docs/sf/manuals/en/vol1-03-your-machine.html`

**Interfaces:**
- Consumes: the template + chapter 2.
- Produces: chapter 3; the toolchain prerequisites chapter 4 builds on.

- [ ] **Step 1: Read the sources** — blueprint Part 3 chapter 3 ("Linux with gcc, or Windows 95/98 with OpenWatcom. 86Box/PCem if you don't have real hardware. What's on the disk."); the Phase 0 `src/build_linux.sh` and `src/build_owc.bat`.
- [ ] **Step 2: Write the page** — what the reader needs (era Linux + gcc, or Win95/98 + OpenWatcom; 86Box/PCem for emulation); what ships on the disk; how to verify the machine is ready. End with "Check yourself". No new example program.
- [ ] **Step 3: Figures** — two Win9x placeholders (e.g. "Figure 2 — a Windows 98 desktop" and "Figure 3 — 86Box/PCem configuration") + matching rows.
- [ ] **Step 4: Cross-check** — every toolchain statement matches the actual build scripts and `docs/sf/QUICK_REF.md`; no invented requirement.
- [ ] **Step 5: Verify** — `check.sh` passes; `build.sh` succeeds.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 3 — your machine`.

---

### Task 5: Chapter 4 — Installing the toolchain

**Files:**
- Create: `docs/sf/manuals/en/vol1-04-installing.html`

**Interfaces:**
- Consumes: the template + chapter 3; the existing `src/vol1/hello.z98`.
- Produces: chapter 4; the `zig1 --version` and `hello` transcript claims chapter 5 assumes.

- [ ] **Step 1: Verify the claims first (STOP if they fail).** Confirm `zig1 --version` exists and prints a version (run the seed compiler with `--version`); compile+run `src/vol1/hello.z98` and capture the exact transcript. If `--version` is not a real flag, STOP and present (do not invent it).
- [ ] **Step 2: Write the page** — unpack the seed, confirm the toolchain (`zig1 --version`), and run the bundled `hello.z98`; embed the captured transcript in `<pre>`. End with "Check yourself" (run `hello` and report its output).
- [ ] **Step 3: Figures** — two Win9x placeholders (e.g. "Figure 4 — unpacking the seed" and "Figure 5 — running `hello.exe`") + matching rows.
- [ ] **Step 4: Cross-check** — the install steps match the real seed layout (`release/seed/zig1-seed.tgz` contents) and `scripts/seed/build_from_seed.sh`.
- [ ] **Step 5: Verify** — `check.sh` passes; `build.sh` succeeds.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 4 — installing the toolchain`.

---

### Task 5A (I): Investigate the win32 default-lib-path lookup

**Files:**
- Read-only: `sf/src/main.zig`, `sf/src/pal.zig`, `sf/src/include/zig_pal.c`, `sf/src/module_registry.zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the verified failure (a std-importing program built on win32 with `lib/` beside the compiler and no `-I` fails `error[3048] could not resolve 'std'`).
- Produces: the root cause, the minimal fix recommendation, the blast radius, and the Task 5B verification plan.

- [ ] **Step 1: Reproduce** — build the seed compiler; reproduce the win32 failure under `wine` (a `std`-importing program with `lib/` beside the compiler and no `-I`) and confirm the Linux path succeeds with `lib/` beside the compiler.
- [ ] **Step 2: Locate the root cause** — `phase_ImportResolution` adds `<exe_dir>/lib` only when `pal.fileExists(lib_path)` is true (`sf/src/main.zig:436-438`); `pal.fileExists` uses `fopen(path,"r")` (`sf/src/pal.zig:54-63`), which fails on a directory on win32. Compare with `pal.dirExists`/`pal_dir_exists` (`sf/src/pal.zig:65-77`, `sf/src/include/zig_pal.c`).
- [ ] **Step 3: Establish correct semantics** — the default lib path names a *directory*; the existence check must confirm a directory on every target.
- [ ] **Step 4: Determine the minimal fix and its blast radius** — e.g. use a directory check for the default lib path; which files change; whether the emitted C / self-emission fixed point moves; whether any existing program depends on the current behavior; whether `fileExists` itself should change (and what else calls it).
- [ ] **Step 5: Recommend the Task 5B verification plan** — the fixture/repro, the gate battery, the seed rotation, and the tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 5B (F): Fix the win32 default-lib-path lookup

**Files (per 5A):** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 5A root cause + recommendation.
- Produces: a compiler whose default standard-library lookup finds `<exe_dir>/lib` on win32 as well as Linux.

- [ ] **Step 1: Implement** per 5A.
- [ ] **Step 2: Rebuild + verify** — a `std`-importing program builds with `lib/` beside the compiler and no `-I` on win32 (under `wine`) and Linux is unchanged; leave reproductions (a permanent `repro/mi_matrix/<name>/` fixture with goldens from the FIXED compiler, deterministic 3×, plus a standalone `repro/` program).
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement): self-compile fixed point, 21-example matrix, 4-MD5 emitted-C gates, stdlib runtime gate, corpus `-s0` sweep, `check_emit_support.sh`, `verify_upgraded.sh`.
- [ ] **Step 4: Rotate the seed** (`scripts/seed/archive_seed.sh`) iff the fixed point moves (it will: `sf/src` changed).
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1 (the PAL / pipeline-orchestration docs) and `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `git add sf/src repro scripts docs/sf/QUICK_REF.md release/seed && git commit -m "fix(pal): detect the default lib directory on win32"` (stage only intended files).

---

### Task 6: Chapter 5 — Your first program (expand the existing page)

**Files:**
- Modify: `docs/sf/manuals/en/vol1-05-first-program.html`
- Modify: `docs/sf/manuals/en/vol1-00-title.html`, `en/toc.html`, `en/index.html` (flip chapter 5 to a link; already linked)
- Read: `docs/sf/manuals/src/vol1/hello.z98`

**Interfaces:**
- Consumes: the Phase 0 `vol1-05-first-program.html` (the tutorial archetype) and `hello.z98`.
- Produces: the full-shape chapter 5.

- [ ] **Step 1: Re-verify the example** — compile+run `hello.z98` with the seed compiler; confirm the embedded transcript is still byte-for-byte correct.
- [ ] **Step 2: Expand the page to the full chapter shape** — `fn main() void { ... }`, `std.io.print`, the compile command, the run, the output, and what each piece means, expanded to 6–10 pages; add "Common mistakes" and "Check yourself" (the Phase 0 page is the archetype but not yet the full shape).
- [ ] **Step 3: Cross-check** — every syntax claim matches `docs/reference/Language_Spec_Z98.md` §1/§3; the `std.io.print` claim matches `sf/src/std_io.zig`.
- [ ] **Step 4: Verify** — `check.sh` passes; `build.sh` succeeds; transcript matches.
- [ ] **Step 5: Commit** — `docs(manual): expand Volume I chapter 5 — your first program`.

---

### Task 6A (I): Investigate the nested-module undefined-member silent drop

**Files:**
- Read-only: `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/type_resolver.zig`, `sf/src/import_resolver.zig`, `sf/src/symbol_registrator.zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the reproduced defect (`std.io.printt("y\n")` → rc=0, no diagnostic, call absent from emitted C; `std.nope()` → `error[3042]`; official Zig rejects).
- Produces: the root cause, the minimal fix recommendation, the blast radius, and the Task 6B verification plan.

- [ ] **Step 1: Reproduce** — with the seed compiler, reproduce both the silent drop (`std.io.printt(...)`) and the correct diagnostic (`std.nope()`); capture the emitted C for each.
- [ ] **Step 2: Locate the root cause** — why a member call on a **nested** module base is dropped while a top-level one errors; trace the field-access / member-call resolution and lowering path (semantic analysis records the base type; lowering emits the call). Find the exact divergence.
- [ ] **Step 3: Establish correct semantics** — official Zig rejects an undefined member with a compile error; Z98 should emit the existing unknown-member diagnostic (`error[3042]`-class) and 0 `.c`.
- [ ] **Step 4: Determine the minimal fix and its blast radius** — which files change; whether the emitted C / self-emission fixed point moves; whether any existing program depends on the current behavior.
- [ ] **Step 5: Recommend the Task 6B verification plan** — the fixture/repro, the gate battery, the seed rotation, the tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 6B (F): Reject a call to an undefined member of a nested module

**Files (per 6A):** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 6A root cause + recommendation.
- Produces: a compiler that cleanly rejects an undefined nested-module member call.

- [ ] **Step 1: Implement** per 6A.
- [ ] **Step 2: Rebuild + verify** — the invalid construct now clean-rejects (`error[3042]`-class, 0 `.c`); leave reproductions (a permanent `repro/mi_matrix/<name>/` fixture with goldens from the FIXED compiler, deterministic 3×, plus a standalone `repro/` program).
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `fix(sema): reject an undefined member of a nested module` (stage only intended files).

---

### Task 6C (I): Investigate the nested-module non-function-member call

**Files:**
- Read-only: `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/type_registry.zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the reproduced defect (`std.io.INVALID_FD()` → rc=0, no diagnostic, emitted `(void)zG_…_INVALID_FD();` fails gcc; and the 6B-fixed undefined-member case).
- Produces: the exact scope of member-call shapes that produce no diagnostic, the root cause, the minimal fix recommendation, the blast radius, and the Task 6D verification plan.

- [ ] **Step 1: Reproduce** — with the current seed compiler, reproduce each shape: undefined member (`std.io.printt` — should now reject), defined non-function member (`std.io.INVALID_FD()`), defined non-function member with args, a deeper chain, and a defined **function** member (valid control). Capture rc + emitted C for each.
- [ ] **Step 2: Locate the root cause** — where the callee's resolved type is (or is not) checked for callability on the nested-member path; why a non-function value is lowered as a call. Exact file:line.
- [ ] **Step 3: Establish correct semantics** — official Zig rejects a call whose callee is not a function; Z98 should emit a diagnostic and 0 `.c`. Decide the code (reuse an existing one if it fits).
- [ ] **Step 4: Determine the minimal fix and its blast radius** — which files; whether the emitted C / self-emission fixed point moves; whether any existing program depends on the current behavior.
- [ ] **Step 5: Recommend the Task 6D verification plan** — fixture/repro, gate battery, seed rotation, tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 6D (F): Diagnose a call whose callee is not a function

**Files (per 6C):** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 6C root cause + recommendation.
- Produces: a compiler that cleanly diagnoses a call whose callee is not a function.

- [ ] **Step 1: Implement** per 6C.
- [ ] **Step 2: Rebuild + verify** — the invalid construct clean-rejects (diagnostic + 0 `.c`); valid function calls are unchanged; leave reproductions (a permanent `repro/mi_matrix/<name>/` fixture with goldens from the FIXED compiler, deterministic 3×, plus a standalone `repro/` program).
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `fix(lower): diagnose a call whose callee is not a function` (stage only intended files).

---

### Task 6E (I): Investigate the undefined free-function call

**Files:**
- Read-only: `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/symbol_table.zig`, `sf/src/type_registry.zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the reproduced defect (`nope()` → rc=0, no diagnostic, emitted undeclared `nope` fails gcc) and the 6B/6D fixes.
- Produces: the full set of unresolved-callee shapes that produce no diagnostic, the root cause, the minimal fix recommendation, the blast radius, and the Task 6F verification plan.

- [ ] **Step 1: Reproduce** — with the current seed compiler, reproduce each shape: undefined free function (`nope()`), undefined free function with args, undefined free function whose name shadows nothing, a valid free-function call (control), and any related unresolved-callee shape. Capture rc + emitted C.
- [ ] **Step 2: Locate the root cause** — why an unresolved free-function callee is lowered/emitted as an undeclared C call instead of diagnosed; contrast with the paths that do diagnose (6B's `error[3042]`, 6D's `error[3056]`).
- [ ] **Step 3: Establish correct semantics** — official Zig rejects a call to an unknown function; decide the correct Z98 diagnostic (reuse an existing code if it fits).
- [ ] **Step 4: Determine the minimal fix and its blast radius** — which files; whether the emitted C / self-emission fixed point moves; whether any existing program depends on the current behavior.
- [ ] **Step 5: Recommend the Task 6F verification plan** — fixture/repro, gate battery, seed rotation, tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 6G (I): Investigate the S variant (sema undeclared-identifier fix)

**Files:**
- Read-only: `sf/src/semantic_analyzer.zig`, `sf/src/type_registry.zig`, `sf/src/lower.zig`, `sf/src/diagnostics.zig`, `repro/mi_matrix/`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the 6E report's variant-S sketch and the operator's ruling (AMENDMENT 5) to fix the root cause.
- Produces: the exact sema change, the full blast radius (every affected fixture/corpus dir), the double-diagnosis dedup approach, the `undefined()` residual decision, the diagnostic code, and the Task 6F verification plan.

- [ ] **Step 1: Reproduce** the sema root cause — an undeclared identifier resolves silently to `TYPE_VOID` (`semantic_analyzer.zig:570`); enumerate every use position that is silently accepted (`nope()`, `take(nope)`, `return nope;`, `arr[nope]`, `_ = nope;`, conditions, binary operands, `s.nope()`, `undefined()`).
- [ ] **Step 2: Design the S change** — diagnose the undeclared identifier at resolution (all uses), reusing an existing code if it fits; specify the exact diagnostic, span, and where `TYPE_VOID` is returned today.
- [ ] **Step 3: Map the full blast radius** — the `diag_excerpt_multifile_xmod` re-baseline (it deliberately uses an undeclared `missing`), the `nope.foo` double-diagnosis and its dedup, the `undefined()` residual (S misses it), and any other corpus/fixture movement; run the corpus classifier against a prototype.
- [ ] **Step 4: Verify against official Zig** — the correct semantics for each affected shape.
- [ ] **Step 5: Recommend the Task 6F verification plan** — fixture/repro, gate battery, seed rotation, tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 6F (F): Diagnose an undeclared identifier (variant S)

**Files (per 6G):** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 6G root-cause analysis + recommendation (variant S).
- Produces: a compiler that cleanly diagnoses an undeclared identifier.

- [ ] **Step 1: Implement variant S** per 6G.
- [ ] **Step 2: Rebuild + verify** — an undeclared identifier now clean-rejects across its use positions (diagnostic + 0 `.c`); valid programs are unchanged; leave reproductions (a permanent `repro/mi_matrix/<name>/` fixture with goldens from the FIXED compiler, deterministic 3×, plus a standalone `repro/` program).
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement; the `diag_excerpt_multifile_xmod` re-baseline must be explicitly accounted for).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `fix(sema): diagnose an undeclared identifier` (stage only intended files).

---

### Task 7A (I): Investigate `const` enforcement

**Files:**
- Read-only: `sf/src/semantic_analyzer.zig`, `sf/src/symbol_table.zig`, `sf/src/type_registry.zig`, `sf/src/lower.zig`, `src/bootstrap/type_checker.cpp`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the reproduced defect (local/module `const` reassignment and `*const T` writes compile rc=0, no diagnostic) and zig0's enforcing implementation.
- Produces: the exact zig1 check site(s), the const-form coverage, the diagnostic choice, the blast radius, and the Task 7B verification plan.

- [ ] **Step 1: Reproduce** with the current seed compiler every unenforced shape: local `const x = 1; x = 2;`, compound (`x += 1;`), module-level const reassignment, write through `*const T` (`p.* = 2`), `[]const T` element write, assignment to a function parameter / loop capture. Capture rc + emitted C.
- [ ] **Step 2: Study zig0's rule** — `src/bootstrap/type_checker.cpp:1841`/`:1893` (`isLValueConst`) — and enumerate the const forms it rejects.
- [ ] **Step 3: Locate the zig1 check site** — the assignment / compound-assignment resolution path (`semantic_analyzer.zig:3430-3440` and wherever the l-value is resolved); determine how to compute constness (symbol flag, `*const T`, `[]const T`).
- [ ] **Step 4: Decide the diagnostic** — reuse the reserved `ERR_3002_INVALID_ASSIGNMENT` (design of record) vs zig0's `ERR_TYPE_MISMATCH` + message; specify code, level, and span.
- [ ] **Step 5: Blast radius + 7B plan** — does any existing corpus program/fixture reassign a const (a corpus sweep)? Does the emitted C / self-emission fixed point move? Recommend the fixture/repro, gate battery, seed rotation, and tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 7B (F): Implement `const` enforcement

**Files (per 7A):** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 7A root-cause analysis + recommendation.
- Produces: a compiler that rejects assignment to a `const` l-value.

- [ ] **Step 1: Implement** per 7A (mirror zig0's `isLValueConst` coverage).
- [ ] **Step 2: Rebuild + verify** — every const-assignment shape clean-rejects (diagnostic + 0 `.c`); valid programs are unchanged; leave reproductions (a permanent `repro/mi_matrix/<name>/` fixture with goldens from the FIXED compiler, deterministic 3×, plus a standalone `repro/` program).
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `fix(sema): enforce const assignment` (stage only intended files).

---

### Task 7B-revert: Undo the zig0-tuned scope-aware lookup (operator ruling m1061)

**Context:** Task 7B fix round 1 (`fa553205`) was demanded by a reviewer using **zig0** as the oracle. Official Zig 0.15.2 REJECTS local declaration shadowing in both directions, so the reviewer's "over-rejection" case is invalid Zig and `fa553205` makes zig1 ACCEPT an illegal program. Operator ruling m1061: revert it, and reject the invalid constructs via a new I/F pair (Tasks 7C/7D), matching official Zig.

**Files:** revert of `fa553205` — `sf/src/semantic_analyzer.zig`, `release/seed/zig1-seed.tgz` (v69→v68), `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md`, `repro/const_assign.z98`, `repro/mi_matrix/const_assign_ok_xmod/**`, `repro/mi_matrix/const_assign_reject_xmod/main.zig`, `repro/mi_matrix/EXPECTED_FAIL.md`, `sf/docs/tech_docs/05_semantic_analysis.md`, `sf/docs/tech_docs/09_pipeline_orchestration.md`, `sf/docs/tech_docs/INDEX.md`.

- [ ] **Step 1:** `git revert --no-edit fa553205` (clean — HEAD is `fa553205`).
- [ ] **Step 2: Verify** the const l-value lookup is back to the `6584be65` (function-wide newest-first) state; the seed archive is v68 (`462dde37…`), fixed point `02c10559…`.
- [ ] **Step 3:** tree clean; the revert commit records the ruling.

---

### Task 7C (I): Investigate local declaration shadowing

**Files:**
- Read-only: `sf/src/semantic_analyzer.zig`, `sf/src/symbol_table.zig`, `sf/src/lower.zig`, `sf/src/parser.zig`; oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: operator ruling m1061 (reject what needs rejecting, matching official Zig — NOT zig0) and the reverted `6584be65` const lookup.
- Produces: the exact Zig shadowing rule (both directions, all declaration forms, function-local vs module), zig1's current behavior, the fix site(s), the diagnostic choice, the blast radius, and the Task 7D verification plan.

- [ ] **Step 1: Establish the oracle rule** with `/tmp/zig-x86_64-linux-0.15.2/zig` (`zig build-obj -fno-emit-bin`): confirm Zig rejects a function-local declaration shadowing an earlier function-local declaration in an enclosing block (both directions — `const` shadowing `var` and `var` shadowing `const`); confirm a local shadowing a module/global is LEGAL; enumerate the declaration forms (local `const`/`var`, params, `if`/`while`/`for` captures, `catch`/`else` payloads, switch prong captures, nested functions) and whether Zig rejects each.
- [ ] **Step 2: Reproduce zig1's current behavior** with the seed compiler for the same shapes; capture rc + emitted C.
- [ ] **Step 3: Locate the fix site(s)** — where function-local declarations are registered (the local-decl stack, `registerLocalDecl`, the capture registrations) and where a redeclaration in a strictly-enclosing block can be detected.
- [ ] **Step 4: Decide the diagnostic** — reuse an existing code vs a new dedicated code; specify code, level, and span (mirror Zig's `local ... shadows ...` intent).
- [ ] **Step 5: Blast radius + 7D plan** — does any `sf/src`/corpus program shadow a local? Does the emitted C / self-emission fixed point move? Recommend the fixture/repro, gate battery, seed rotation, and tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 7M (M): Migrate (de-shadow) the compiler-source local-shadow sites

**Context:** Task 7C found 10 real local-shadowing sites in the compiler's own `sf/src` (all function-local: an inner binding shadowing an enclosing one). When the shadow-rejection lands (Task 7D), these would break the self-compile. Operator ruling m1079: de-shadow them FIRST, so the migration is verified independently of the rejection; then use "scope 1" (full Zig fidelity) for the I/F.

**Files:**
- Modify: `sf/src/parser.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig` (the sites below — mechanical renames only, semantics-preserving).
- Modify: `release/seed/` (rotation — the compiler's own emitted C changes), `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md`, `repro/mi_matrix/EXPECTED_FAIL.md`.
- No behavior change to the compiler's output on user programs.

**Sites (from 7C §5.1; verify each against current source before editing):**
| File | Shadowing site | Shadows |
|---|---|---|
| `sf/src/parser.zig` | `:730` `var tok` | `:713` `var tok` |
| `sf/src/lower.zig` | `:3338`, `:4077`, `:4164`, `:4345`, `:4849`, `:4975`, `:5111` `var rt` | `:2539` `var rt` |
| `sf/src/lower.zig` | `:4023` `var field_name_id` | `:3981` `var field_name_id` |
| `sf/src/c89_emit.zig` | `:3973` `var pi` | `:3140` `var pi` |

**Interfaces:**
- Consumes: the 7C report §5.1 site list.
- Produces: an `sf/src` free of local shadowing (so 7D's rejection does not break the self-compile), plus a rotated seed.

- [ ] **Step 1: Locate + verify** each site against current source (re-read the enclosing scope before editing; `edit`/`fastedit` only, per `docs/sf/AGENTS.md` §X.7). Rename ONLY the inner shadowing binding; do NOT touch the outer binding.
- [ ] **Step 2: Rename** each inner binding to a distinct name (semantics-preserving; update every reference within its scope).
- [ ] **Step 3: Rebuild** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t7m/build`; confirm the self-compile succeeds (two-hop closure) and record the new fixed point.
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (4-MD5 unchanged, corpus zero movement, example matrix, std-lib gate, `check_emit_support.sh`, `verify_upgraded.sh`). STOP on unexpected movement.
- [ ] **Step 5: Rotate the seed** (the fixed point moves); update `release/seed/CHANGELOG.md`, `docs/sf/QUICK_REF.md`, `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `refactor(sf): de-shadow locals in the compiler source`.

---

### Task 7D (F): Reject local declaration shadowing

**Files (per 7C):** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 7C root-cause analysis + recommendation.
- Produces: a compiler that rejects function-local declaration shadowing (Zig-matching), so the reverted `fa553205` scope-aware lookup is unnecessary.

- [ ] **Step 1: Implement** per 7C (mirror official Zig's shadowing rule).
- [ ] **Step 2: Rebuild + verify** — every shadowing shape clean-rejects (diagnostic + 0 `.c`); non-shadowing programs unchanged; leave reproductions (a permanent `repro/mi_matrix/<name>/` fixture with goldens from the FIXED compiler, deterministic 3×, plus a standalone `repro/` program).
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `fix(sema): reject local declaration shadowing`.

---

### Task 7E (I): Investigate the `print` type-dispatch gap (f32)

**Context:** `getPrintFnName` (`sf/src/c89_emit.zig:5474-5502`) maps a `print` argument's TypeId to a runtime helper but has no `f32_type` arm, so an `f32` argument falls through to the `std_print_i32` default (`1.5` prints `1`). AMENDMENT 8.

**Files:**
- Read-only: `sf/src/c89_emit.zig`, `sf/src/lower.zig` (`lowerPrintFmt`), `sf/src/include/zig_runtime.c`/`.h`, `sf/src/std_io.zig`, `docs/reference/Language_Spec_Z98.md`; oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: AMENDMENT 8 (approach (a): reuse `std_print_f64` with a `(double)` widening).
- Produces: the full set of type kinds that reach the `std_print_i32` default (f32 and any others), official Zig's behavior for each, the fix site, the `{}`/`{d}`/`{x}`/`{c}`/`{s}` semantics for floats, the blast radius, and the Task 7F verification plan.

- [ ] **Step 1: Enumerate** every `TypeKind` reachable through `getPrintFnName` and which kinds hit the `std_print_i32` default (f32 certainly; check arbitrary-width ints, `i8`/`i16`, `usize`/`isize`, enums, and `f64` with `{x}`/`{c}`).
- [ ] **Step 2: Confirm** against official Zig 0.15.2 what printing each type must do.
- [ ] **Step 3: Locate the fix site** + specify the exact edit (approach (a): an `f32_type` arm emitting `std_print_f64` with a `(double)` widening, or equivalent).
- [ ] **Step 4: Blast radius + 7F plan** — does the emitted C / fixed point move? Recommend the fixture/repro, gate battery, seed rotation, and tech-doc updates.
- [ ] **Step 5: Report.** No `sf/src` edits, no commit.

---

### Task 7F (F): Fix the `print` dispatch (f32) + close chapter 6

**Files (per 7E):** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`; `docs/sf/manuals/en/vol1-06-variables-types.html`; `docs/sf/manuals/en/vol1-05-first-program.html`.

**Interfaces:**
- Consumes: the 7E root-cause analysis + recommendation.
- Produces: a compiler that prints an `f32` correctly (Zig-matching), and a chapter-6 page with the stale f32 workaround note removed plus the two open Task-7 review findings fixed.

- [ ] **Step 1: Implement** the fix per 7E (approach (a)).
- [ ] **Step 2: Rebuild + verify** — the f32 fixture prints the right value (rc=0, golden); non-f32 prints unchanged; leave reproductions.
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Chapter-6 page** — remove the stale f32 workaround note (print the `f32` directly), fix `en/vol1-05-first-program.html:46` (restore `<b>Your first program</b>`), fix `en/vol1-06-variables-types.html:198` ("Four"→"Five"); re-run `check.sh` + `build.sh`.
- [ ] **Step 7: Commit(s).**

---

### Task 7G (I): Investigate the remaining `print` dispatch/format divergences

**Context:** Task 7F fixed the `f32` mis-route only. 7E found many more `print` divergences. Operator ruling m1146: extend the scope to fix them all (matching official Zig 0.15.2). AMENDMENT 9.

**Files:**
- Read-only: `sf/src/c89_emit.zig` (`getPrintFnName`, the `.print_val` arm), `sf/src/lower.zig` (`lowerPrintFmt`), `sf/src/print_decomposition.zig`, `sf/src/semantic_analyzer.zig` (the print special case), `sf/src/include/zig_runtime.c`/`.h`, `sf/src/std_io.zig`, `docs/reference/Language_Spec_Z98.md`; oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the 7E report's dispatch table + AMENDMENT 9.
- Produces: for every `print` divergence, a decision (FIX the routing/format, or CLEAN-REJECT at sema/lowering), the exact fix sites + diagnostic codes, official-Zig behavior per case, the blast radius, and the 7H verification plan.

- [ ] **Step 1: Enumerate** every remaining divergence (routing mis-routes + `{x}`/`{c}`/`{s}` format behavior + float formatting) from 7E, verified against the seed compiler.
- [ ] **Step 2: Decide per case** (FIX vs CLEAN-REJECT) against official Zig 0.15.2, with the diagnostic code for each reject (existing vs new).
- [ ] **Step 3: Locate the fix sites** and specify the exact edits (routing arms, format handling, runtime helpers if any, sema rejects).
- [ ] **Step 4: Blast radius + 7H plan** — emitted C / fixed point / corpus movement; the fixtures (positive + reject controls), the gate battery, and the seed rotation.
- [ ] **Step 5: Report.** No `sf/src` edits, no commit.

---

### Task 7H (F): Fix the remaining `print` divergences

**Files (per 7G):** `sf/src/**`; `repro/mi_matrix/` fixtures + standalone `repro/` programs; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 7G analysis + per-case decisions.
- Produces: a compiler whose `print` routing and format behavior match official Zig for every enumerated case (or clean-rejects the invalid ones), with fixtures and a rotated seed.

- [ ] **Step 1: Implement** per 7G.
- [ ] **Step 2: Rebuild + verify** — each fixed case prints correctly (rc=0, goldens); each reject case clean-rejects (diagnostic + 0 `.c`); non-`print` programs unchanged; leave reproductions.
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit.**

---

### Task 7: Chapter 6 — Variables and types

**Files:**
- Create: `docs/sf/manuals/src/vol1/types.z98`
- Create: `docs/sf/manuals/en/vol1-06-variables-types.html`

**Interfaces:**
- Consumes: the template + chapter 5.
- Produces: chapter 6; `types.z98`.

- [ ] **Step 1: Author `types.z98`** — declare `var`/`const` of `i32`, `u8`, `bool`, `f32`; print values and `@sizeOf` for each. Compile+run; capture the transcript.
- [ ] **Step 2: Write the page** — `var` vs `const`, the primitive types, why width matters on a 32 MB machine, `@sizeOf`; embed the transcript; "Common mistakes" (e.g. implicit `i32`↔`usize` coercion is rejected — use `@intCast`); "Check yourself".
- [ ] **Step 3: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 4: Cross-check** — the type list, `@sizeOf`, and the coercion rule match the spec §1/§4 and source; the `@sizeOf` values match the compiled output.
- [ ] **Step 5: Wire + verify** — flip the chapter 6 entry to a link across shipped pages; `check.sh` passes; `build.sh` succeeds.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 6 — variables and types`.

---

### Task 8A (I): Investigate the `@as(signed, negative)` binary-operand miscompile

**Context:** Verifying chapter 7 (Task 8) found a silent miscompile: `@as(i32, -2)` used as a **binary operand** is lowered as the `u64` constant `18446744073709551614ULL`, losing the signed target — `v / @as(i32, -2)` prints `0` (Zig: `-3`) and `v * @as(i32, -2)` traps under `-fsafe` (rc 133). Operator ruling m1202: open a scoped I/F pair. AMENDMENT 10.

**Files:**
- Read-only: `sf/src/lower.zig` (the `@as`/`int_cast` operand lowering), `sf/src/comptime_eval.zig` (the `@as` fold), `sf/src/c89_emit.zig`, `sf/src/type_registry.zig`; oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the reproduced defect (seed v73, `3c55361a…`).
- Produces: the root cause (which path loses the target width/signedness), the exact fix site(s) + minimal edit, the blast radius, and the Task 8B verification plan.

- [ ] **Step 1: Reproduce + narrow** every shape (`@as(i32,-2)` as `/`/`*`/`+`/`-`/`%`/comparison operand; `@as(i64,-2)`, `@as(i8,-2)`, `@as(u32,2)`, `-@as(i32,2)`; direct print; `const`; literal) with the seed compiler; capture rc + emitted C.
- [ ] **Step 2: Locate the root cause** — why the `@as(signed, negative)` operand is lowered as `u64` (the comptime fold vs the operand lowering).
- [ ] **Step 3: Confirm the fix** against official Zig 0.15.2 semantics (the value must keep the `@as` target's width/signedness).
- [ ] **Step 4: Blast radius + 8B plan** — emitted C / fixed point / corpus movement; the fixture (positive + control), the gate battery, and the seed rotation.
- [ ] **Step 5: Report.** No `sf/src` edits, no commit.

---

### Task 8B (F): Fix the `@as(signed, negative)` binary-operand miscompile

**Files (per 8A):** `sf/src/**`; `repro/mi_matrix/` fixture + standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 8A root-cause analysis + fix.
- Produces: a compiler that lowers `@as(signed, negative)` operands with the correct width/signedness (matching Zig), with a fixture and a rotated seed.

- [ ] **Step 1: Implement** per 8A — the fix must cover **every signed width** (`i8`/`i16`/`i32`/`i64`/`isize` and arbitrary-width signed), not only `i32` (the 8A investigation found `i64`/`i8` operands are also wrong).
- [ ] **Step 2: Rebuild + verify** — every narrowed shape is correct (rc=0, goldens), including the `i8`/`i16`/`i64`/`isize` operands; non-`@as` programs unchanged; leave reproductions.
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `fix(lower): lower @as(signed, negative) operands with the target type`.

---

### Task 8: Chapter 7 — Doing arithmetic

**Files:**
- Create: `docs/sf/manuals/src/vol1/math.z98`
- Create: `docs/sf/manuals/en/vol1-07-arithmetic.html`

**Interfaces:**
- Consumes: the template + chapter 6; `types.z98`.
- Produces: chapter 7; `math.z98`.

- [ ] **Step 1: Author `math.z98`** — `+ - * / %`, operator precedence, and integer overflow; demonstrate the `-fsafe` overflow trap and the `-ffast` wrap. Compile+run **both** modes; capture both transcripts (or a single one that the page explains).
- [ ] **Step 2: Write the page** — the operators, precedence, and what `-fsafe` does about overflow (the default); embed the transcript(s); "Common mistakes" (integer division truncation; overflow); "Check yourself".
- [ ] **Step 3: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 4: Cross-check** — the overflow behavior matches `docs/sf/QUICK_REF.md` and the compiler's `-fsafe`/`-ffast` semantics; the precedence table matches the spec §3.
- [ ] **Step 5: Wire + verify** — flip chapter 7 to a link; `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 7 — doing arithmetic`.

---

### Task 9A (I): Investigate the condition/`if` acceptance gaps

**Context:** Verifying chapter 8 (Task 9) found three shapes where zig1 silently ACCEPTS invalid Zig (all rejected by official Zig 0.15.2): (a) `if (a = 3) { … }` — assignment in a condition; (b) `var x = if (cond) 1;` — an `if` expression without `else`; (c) `if (a) { … }` — a non-`bool` condition. Operator ruling m1231: open a scoped I/F pair. AMENDMENT 11.

**Files:**
- Read-only: `sf/src/semantic_analyzer.zig` (`resolveIf`, condition typing), `sf/src/parser.zig` (the `if` forms), `sf/src/lower.zig`; oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the three reproduced shapes (seed v74, `bea0a1c4…`).
- Produces: the root cause per shape, the exact fix site(s) + minimal edit, the diagnostic code(s) matching Zig, the blast radius, and the Task 9B verification plan.

- [ ] **Step 1: Reproduce + narrow** each shape (`=` in a condition; `if` expression without `else` in value position; non-`bool` condition — including `i32`, pointer, enum, optional) with the seed compiler; capture rc + emitted C.
- [ ] **Step 2: Locate the root cause(s)** — where the condition is typed and where an `if` expression's value/`else` requirement is decided; whether each gap shares one site or needs separate checks.
- [ ] **Step 3: Confirm the rejects** against official Zig 0.15.2 (assignment-in-condition, missing-`else` value `if`, non-`bool` condition) — with the diagnostic code/level/span to use.
- [ ] **Step 4: Blast radius + 9B plan** — emitted C / fixed point / corpus movement; the fixtures (reject + control), the gate battery, and the seed rotation; plus the stale spec example fix (`docs/reference/Language_Spec_Z98.md` §3.1).
- [ ] **Step 5: Report.** No `sf/src` edits, no commit.

---

### Task 9B (F): Reject the invalid condition/`if` forms

**Files (per 9A):** `sf/src/**`; `repro/mi_matrix/` fixtures + standalone `repro/` programs; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`; the stale spec example `docs/reference/Language_Spec_Z98.md` §3.1; and the chapter-8 page `docs/sf/manuals/en/vol1-08-decisions.html` (+ regenerate `dist/`).

**Interfaces:**
- Consumes: the 9A root-cause analysis + rejects.
- Produces: a compiler that rejects assignment-in-condition, a value `if` without `else`, and a non-`bool` condition (matching Zig), with fixtures and a rotated seed; plus the corrected spec §3.1 example.

- [ ] **Step 1: Implement** per 9A (all three shapes) with the m1240 rulings: (a) parser-level; (b) match Zig (allow a comptime-true no-`else` value `if`; reject only non-void/noreturn then-branch with a non-comptime-true condition); (c) reject non-`bool` conditions; plus the related gaps (non-optional `if (a) |v|`; assignment-as-expression).
- [ ] **Step 2: Rebuild + verify** — each shape clean-rejects (diagnostic + 0 `.c`); valid `if`/`else` programs unchanged; leave reproductions.
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`; fix the stale `Language_Spec_Z98.md` §3.1 example (brace-less `if` is rejected).
- [ ] **Step 6: Commit** — `fix(sema): reject invalid condition and if forms`.

---

### Task 9C (I): Investigate the comptime-fold narrowing + the void-then value-`if` lowering defect

**Context:** Two residuals from Task 9B. (i) The comptime-true no-`else` allowance uses Z98's comptime fold, which does **not** fold comparisons, so `const a: i32 = 1; var x: i32 = if (a == 1) 1;` is rejected although Zig accepts — too narrow a downgrade vs Zig. (ii) A pre-existing backend defect: `_ = if (c) foo();` (a void-then value `if`) is front-end-accepted but lowers to an undeclared temp → gcc failure. Operator ruling m1251: keep Zig parity and fold both into a new scoped I/F pair. AMENDMENT 12.

**Files:**
- Read-only: `sf/src/comptime_eval.zig` (the fold: which node kinds it folds), `sf/src/semantic_analyzer.zig` (`semanticAnalyzerResolveIfExpr`, the `error[3059]` gate), `sf/src/lower.zig` (the value-`if` lowering / void-then temp); oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the two residuals (seed v76, `efa91f8d…`).
- Produces: for each, the root cause, the exact fix site(s) + minimal edit, the blast radius, and the Task 9D verification plan.

- [ ] **Step 1: (i) Reproduce + narrow** which comptime-known conditions are (mis)rejected: comparison (`==`,`!=`,`<`,`<=`,`>`,`>=`), `and`/`or`/`not`, arithmetic-derived bools, const-of-const — with the seed compiler; identify exactly which fold node kinds are missing.
- [ ] **Step 2: (i) Locate the fix** — where the `if`-without-`else` comptime-true decision is made and why the fold does not cover the comparison node kind; specify the minimal fold extension (mirroring Zig's comptime-known-true rule).
- [ ] **Step 3: (ii) Reproduce + locate** the void-then value-`if` lowering defect (`_ = if (c) foo();` → undeclared temp): which lowering path emits the temp and why the else arm is bogus; the exact fix site.
- [ ] **Step 4: Confirm both fixes** against official Zig 0.15.2.
- [ ] **Step 5: Blast radius + 9D plan** — emitted C / fixed point / corpus movement; fixtures (positive + reject/control), the gate battery, and the seed rotation.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 9D (F): Fix the comptime-fold narrowing + the void-then value-`if` lowering

**Files (per 9C):** `sf/src/**`; `repro/mi_matrix/` fixtures + standalone `repro/` programs; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 9C root-cause analysis + fixes.
- Produces: a compiler where a comptime-known-true comparison condition permits a no-`else` value `if` (matching Zig), and a void-then value `if` lowers correctly; with fixtures and a rotated seed.

- [ ] **Step 1: Implement** per 9C (both fixes).
- [ ] **Step 2: Rebuild + verify** — the comptime-true comparison case now compiles+runs; the void-then value `if` compiles+runs; invalid forms still reject; leave reproductions.
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md`.
- [ ] **Step 6: Commit** — `fix(sema): match Zig for comptime-true no-else if and fix void-then value if`.

---

### Task 9: Chapter 8 — Making decisions

**Files:**
- Create: `docs/sf/manuals/src/vol1/classify.z98`
- Create: `docs/sf/manuals/en/vol1-08-decisions.html`

**Interfaces:**
- Consumes: the template + chapter 7.
- Produces: chapter 8; `classify.z98`.

- [ ] **Step 1: Author `classify.z98`** — `if`/`else`, an `if` expression, comparison operators, `bool`; classify a value (e.g. positive/negative/zero). Compile+run; capture the transcript.
- [ ] **Step 2: Write the page** — conditionals and `if` expressions; embed the transcript; "Common mistakes" (brace-less `if`/`else` is rejected; `=` vs `==`); "Check yourself".
- [ ] **Step 3: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 4: Cross-check** — the `if`-expression and brace rules match the spec §3.2 and the parser behavior.
- [ ] **Step 5: Wire + verify** — flip chapter 8 to a link; `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 8 — making decisions`.

---

### Task 10A (I): Investigate the `for`-loop `continue` defect

**Context:** Verifying chapter 9 (Task 10) found a silent miscompile: `continue` inside a `for` loop (range or array) jumps to the loop's condition instead of its implicit increment, so the loop never advances and the program hangs (no diagnostic; rc=0 emit/build; runtime `timeout` rc=124). Spec §3.2 (`docs/reference/Language_Spec_Z98.md:249`) says `continue` jumps to the next iteration of the innermost `while` **or** `for` loop. `continue` in a `while` and `break` in a `for` are correct. Operator ruling m1318: open a scoped I/F pair. AMENDMENT 13.

**Files:**
- Read-only: `sf/src/lower.zig` (the loop lowering / `continue` target selection), `sf/src/ast.zig`, `sf/src/parser.zig` as needed; oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: AMENDMENT 13; the defect reproduction in `task-10-report.md`.
- Produces: the root cause, the exact fix site + minimal edit, the characterization matrix (range/array/nested/labeled/`while`/`for`-with-step), official Zig's loop shape, the blast radius, and the Task 10B verification plan.

- [ ] **Step 1: Reproduce + characterize** — every `continue`-in-`for` shape (range `0..n`, array/slice iterable, nested loops, `while (c) : (step)`, a `continue` inside a nested `if` in the body) on the current seed; record rc, emitted C, and runtime (every run under `timeout 120`).
- [ ] **Step 2: Locate the fix site** — how `for` lowers its condition/body/step blocks and which block `continue` targets; identify where the `continue` edge must be re-pointed to the implicit-step block (and confirm `break`/`while` are unaffected).
- [ ] **Step 3: Confirm the fix** — ensure the shape matches Zig 0.15.2 semantics (the step runs before the next condition test); check side-effect ordering (`continue` taken after a side effect).
- [ ] **Step 4: Blast radius** — does any `sf/src`/corpus/example/manual program use `continue` in a `for`? Does the emitted C of the gate programs change? Is the fixed point expected to move (seed rotation)? 4-MD5/matrix predictions.
- [ ] **Step 5: 10B plan** — fixture + standalone repro + gate battery + seed rotation + the tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 10B (F): Fix the `for`-loop `continue` target AND the nested-loop label leak

**Files:** `sf/src/**`; `repro/mi_matrix/` fixtures + standalone `repro/` programs; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 10A root-cause analysis + recommendation; operator ruling m1336 (fold BOTH defects into 10B; the 4-MD5 re-baseline is authorized with runtime-identity evidence; report ANY anomaly as Important even if pre-existing).
- Produces: a compiler whose `continue` in a `for` loop runs the loop's implicit step AND whose labeled `break`/`continue` target the labeled loop (Zig-matching), so chapter 9 can teach `continue` honestly.

- [ ] **Step 1: Implement fix A** per 10A (the 2-hunk `step_bb` edit: the `continue` edge must reach the implicit-step block; always emit `step_bb`, even for always-continue bodies).
- [ ] **Step 2: Implement fix B** per the 10A report's label-leak findings — clear/restore `current_label` correctly when entering a nested unlabeled loop, so labeled `break`/`continue` target the labeled loop, not the inner one; cover both `while` and `for`, and both `break` and `continue`.
- [ ] **Step 3: Rebuild + verify** — RED→GREEN for both defects with standalone repros and permanent `repro/mi_matrix/<name>/` fixtures (goldens from the FIXED compiler, deterministic 3×, `@panic` guards, `expected.rc`); Zig-0.15.2 oracle cross-check; controls unchanged (`continue` in `while`, `break` in `for`, nested unlabeled loops, labeled transfers targeting the correct loop).
- [ ] **Step 4: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement). **The 4-MD5 lisp/json gates are AUTHORIZED to move** (measured +58 B/+62 B step-block/goto restructuring): re-baseline them in `docs/sf/QUICK_REF.md` **with runtime-identity evidence** (PRE vs POST stdout + rc identical for each gate program) — report ANY anomaly as **Important** even if pre-existing. gol/mud must stay unchanged.
- [ ] **Step 5: Rotate the seed** (the fixed point moves: the pre-rotation rebuild is a moving point — expect `hop1≠hop2`, then `hop2==hop3`; the post-rotation closure must be `hop1==hop2`).
- [ ] **Step 6: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md` (v200→v201) and the stdlib pin (215→216).
- [ ] **Step 7: Commit** — `fix(lower): run the for-loop step when continue is taken and fix nested-loop labels`.

---

### Task 10C (I): Investigate the `var`-after-same-named-`for`-capture aliasing defect

**Context:** Task 10B's work found a pre-existing silent miscompile (present in v80 and v81): a plain local `var` declared after a same-named `for` capture in a **sibling** scope loses its declaration and initializer in the emitted C and aliases the stale capture temp, so reads/writes hit the old loop variable (Zig `c7=12` vs Z98 `c7=0` on v80 / `c7=3` on v81). Operator ruling m1347: open a scoped I/F pair. AMENDMENT 14.

**Files:**
- Read-only: `sf/src/lower.zig` (local-declaration/temp allocation and the `for` capture scoping), `sf/src/semantic_analyzer.zig`, `sf/src/ast.zig` as needed; oracle `/tmp/zig-x86_64-linux-0.15.2/zig`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: AMENDMENT 14; the defect reproduction in `task-10B-report.md` (§3/§7).
- Produces: the root cause, the exact fix site + minimal edit, the characterization matrix (same-name/different-name, sibling/nested blocks, `|x|` vs `|x, i|` captures, a `while` capture analogue), the blast radius, and the 10D verification plan.

- [ ] **Step 1: Reproduce + characterize** — every `var`-after-`for`-capture shape (same name vs different name; sibling block vs same block; `|x|` vs `|x, i|` captures; the `while` capture analogue; a nested block) on the current seed (v81); record rc, emitted C, and runtime (every run under `timeout 120`).
- [ ] **Step 2: Locate the fix site** — how the capture temp is named/scoped and how a later local `var` with the same name gets (or fails to get) its own declaration/initializer; identify the minimal fix that gives it a distinct local decl/temp.
- [ ] **Step 3: Confirm the fix** — the shape must match Zig 0.15.2 (the later `var` is a distinct variable; the capture is out of scope after the loop); check the 7D shadow-rejection rule is not weakened (this shape is legal Zig — sibling scopes may reuse a name).
- [ ] **Step 4: Blast radius** — grep the tree for the shape; does any gate program's emitted C change? Is the fixed point expected to move (seed rotation)? 4-MD5/matrix predictions.
- [ ] **Step 5: 10D plan** — fixture + standalone repro + gate battery + seed rotation + the tech-doc updates.
- [ ] **Step 6: Report.** No `sf/src` edits, no commit.

---

### Task 10D (F): Fix the `var`-after-same-named-`for`-capture aliasing

**Files:** `sf/src/**`; a `repro/mi_matrix/` fixture + a standalone `repro/` program; tech docs (`sf/docs/tech_docs/`); `release/seed/` (rotation); `docs/sf/QUICK_REF.md`; `repro/mi_matrix/EXPECTED_FAIL.md`.

**Interfaces:**
- Consumes: the 10C root-cause analysis + recommendation.
- Produces: a compiler in which a local declaration after a same-named capture introduces a distinct variable (Zig-matching), so chapter 9 (and later chapters) can reuse names across sibling scopes honestly.

- [ ] **Step 1: Implement** per 10C.
- [ ] **Step 2: Rebuild + verify** — RED→GREEN with a permanent `repro/mi_matrix/<name>/` fixture (goldens from the FIXED compiler, deterministic 3×, `@panic` guards, `expected.rc`) + a standalone `repro/` program; Zig-0.15.2 oracle cross-check; controls unchanged (captures, nested loops, sibling-scope name reuse).
- [ ] **Step 3: Run the QUICK_REF gate battery verbatim** (STOP on unexpected movement; report ANY anomaly as Important even if pre-existing).
- [ ] **Step 4: Rotate the seed** iff the fixed point moves.
- [ ] **Step 5: Update the tech docs** per AGENTS §1.1.1; update `docs/sf/QUICK_REF.md`; bump `repro/mi_matrix/EXPECTED_FAIL.md` and the stdlib pin if a new fixture is added.
- [ ] **Step 6: Commit** — `fix(lower): keep a same-named local distinct from a sibling for capture`.

---

### Task 10: Chapter 9 — Doing things repeatedly

**Files:**
- Create: `docs/sf/manuals/src/vol1/count.z98`
- Create: `docs/sf/manuals/en/vol1-09-repetition.html`

**Interfaces:**
- Consumes: the template + chapter 8.
- Produces: chapter 9; `count.z98`.

- [ ] **Step 1: Author `count.z98`** — `while`, `for` over a range (`0..10`), `break`, `continue`; count/sum something. Compile+run; capture the transcript.
- [ ] **Step 2: Write the page** — loops and ranges; embed the transcript; "Common mistakes" (off-by-one; `0..N` excludes `N`; a range end that must resolve); "Check yourself".
- [ ] **Step 3: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 4: Cross-check** — range semantics and `break`/`continue` match the spec §3.2; the `.len`/range-end behavior matches the current compiler.
- [ ] **Step 5: Wire + verify** — flip chapter 9 to a link; `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 9 — doing things repeatedly`.

---

### Task 11: Chapter 10 — Functions

**Files:**
- Create: `docs/sf/manuals/src/vol1/functions.z98`
- Create: `docs/sf/manuals/en/vol1-10-functions.html`

**Interfaces:**
- Consumes: the template + chapter 9.
- Produces: chapter 10; `functions.z98`.

- [ ] **Step 1: Author `functions.z98`** — a `fn` with parameters and a return value, called from `main`; a `pub fn`. Compile+run; capture the transcript.
- [ ] **Step 2: Write the page** — function declarations, parameters, returns, `pub fn`, and why parameters are immutable; embed the transcript; "Common mistakes" (no method syntax; parameters cannot be reassigned); "Check yourself".
- [ ] **Step 3: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 4: Cross-check** — the function grammar and immutability match the spec §1/§3.
- [ ] **Step 5: Wire + verify** — flip chapter 10 to a link; `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 10 — functions`.

---

### Task 12: Chapter 11 — Grouping data (structs)

**Files:**
- Create: `docs/sf/manuals/src/vol1/point.z98`
- Create: `docs/sf/manuals/en/vol1-11-structs.html`

**Interfaces:**
- Consumes: the template + chapter 10.
- Produces: chapter 11; `point.z98`.

- [ ] **Step 1: Author `point.z98`** — a `const Point = struct { x: i32, y: i32 };`, field access, construction. Compile+run; capture the transcript.
- [ ] **Step 2: Write the page** — `struct`, field access, the `const S = struct { ... };` idiom; embed the transcript; "Common mistakes" (field order/layout; no methods); "Check yourself".
- [ ] **Step 3: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 4: Cross-check** — the struct syntax and `const S = struct { ... };` form match the spec §1.3 and the current compiler.
- [ ] **Step 5: Wire + verify** — flip chapter 11 to a link; `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 11 — grouping data`.

---

### Task 13: Chapter 12 — Lists of things (arrays)

**Files:**
- Create: `docs/sf/manuals/src/vol1/scores.z98`
- Create: `docs/sf/manuals/en/vol1-12-arrays.html`

**Interfaces:**
- Consumes: the template + chapter 11.
- Produces: chapter 12; `scores.z98`.

- [ ] **Step 1: Author `scores.z98`** — a `[N]T` array, indexing, iteration; show why `[0..N]` is not the same as `[0..N-1]`. Compile+run; capture the transcript.
- [ ] **Step 2: Write the page** — arrays and indexing; the half-open range rule; embed the transcript; "Common mistakes" (out-of-bounds; `.len` is the count, not the last index); "Check yourself".
- [ ] **Step 3: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 4: Cross-check** — array syntax, indexing, and `.len` match the spec §1.4 and the compiler.
- [ ] **Step 5: Wire + verify** — flip chapter 12 to a link; `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 12 — lists of things`.

---

### Task 14: Chapter 13 — Reading the errors

**Files:**
- Create: `docs/sf/manuals/src/vol1/errors/err1.z98` … `errors/err5.z98`
- Create: `docs/sf/manuals/en/vol1-13-reading-errors.html`

**Interfaces:**
- Consumes: the template + chapter 12.
- Produces: chapter 13; five deliberately-erroneous programs and their captured diagnostics.

- [ ] **Step 1: Author the five error programs** — each triggers a distinct real diagnostic (e.g. an unknown type name, an unknown builtin, a type mismatch, a missing `else` prong, a void-typed variable). Compile each with the seed compiler; capture the exact `file:line:col` diagnostic, caret, note, and related-span output. If a chosen error does not reproduce as expected, pick a different real error (do not invent a diagnostic).
- [ ] **Step 2: Write the page** — how to read `error[30xx]`, the `file:line:col` format, the caret underline, and the note/related-span callouts; walk through all five captured errors. End with "Check yourself" (read one error and state the fix). No "Common mistakes" beyond the walk-through.
- [ ] **Step 3: Figure** — one Win9x placeholder (e.g. "Figure N — an error in the Win9x console") + matching row.
- [ ] **Step 4: Cross-check** — every quoted diagnostic matches the captured compiler output verbatim; the error-code count claim (if any) matches `sf/src/diagnostics.zig`.
- [ ] **Step 5: Wire + verify** — flip chapter 13 to a link; `check.sh`; `build.sh`.
- [ ] **Step 6: Commit** — `docs(manual): add Volume I chapter 13 — reading the errors`.

---

### Task 15: Chapter 14 — Your first useful program

**Files:**
- Create: `docs/sf/manuals/src/vol1/wc.z98`
- Create: `docs/sf/manuals/en/vol1-14-line-counter.html`

**Interfaces:**
- Consumes: the template + chapter 13; chapters 6–12.
- Produces: chapter 14; `wc.z98`.

- [ ] **Step 1: Verify feasibility first (STOP if it fails).** Determine whether a beginner-level line-counting tool — read a file, count lines, print the count — is expressible with the current `std` surface at the level chapters 6–12 have taught (no error-union chapter yet). Inspect `sf/src/std_io.zig` / `sf/src/std_file.zig` and the spec. If the tool cannot be written without error-union machinery (Volume II content), STOP and present options (move the chapter later, or re-scope the example) — do not invent an API.
- [ ] **Step 2: Author `wc.z98`** — the line-counting tool using only taught constructs; compile+run against a real input file; capture the transcript (including the input used).
- [ ] **Step 3: Write the page** — the tool built up piece by piece; embed the transcript; "Common mistakes"; "Check yourself" (extend the tool).
- [ ] **Step 4: Figure** — one Win9x placeholder + matching row.
- [ ] **Step 5: Cross-check** — every API used exists in `sf/src`; no error-union construct taught before Volume II.
- [ ] **Step 6: Wire + verify** — flip chapter 14 to a link; `check.sh`; `build.sh`.
- [ ] **Step 7: Commit** — `docs(manual): add Volume I chapter 14 — your first useful program`.

---

### Task 16: Chapter 15 — What you have learned, what is next

**Files:**
- Create: `docs/sf/manuals/en/vol1-15-whats-next.html`

**Interfaces:**
- Consumes: the template + chapters 0–14.
- Produces: chapter 15; the Volume II handoff.

- [ ] **Step 1: Read the sources** — blueprint Part 3 chapter 15 ("if you came here to learn programming in general, Z98 is a fine teacher, but you should know that modern languages exist…; this manual is about a specific discipline, not about programming as such") and the Volume II title page.
- [ ] **Step 2: Write the page** — the honest summary of what the reader can now do; the mandatory honesty callout; the handoff to Volume II. End with "Check yourself". No example program.
- [ ] **Step 3: Cross-check** — the summary claims match what the volume actually taught; no overselling.
- [ ] **Step 4: Verify** — `check.sh` passes; `build.sh` succeeds.
- [ ] **Step 5: Commit** — `docs(manual): add Volume I chapter 15 — what you have learned`.

---

### Task 17: Volume I closeout — whole-set review and verification sweep

**Files:**
- Review: all `docs/sf/manuals/**`; modify as needed.

**Interfaces:**
- Consumes: all sixteen chapters.

- [ ] **Step 1: Whole-set mechanical gate** — `bash docs/sf/manuals/check.sh` passes (links, `rel`, lang bar, charset, forbidden list, figure 1:1, no-CSS baseline); `bash docs/sf/manuals/build.sh` succeeds and is idempotent; `bash docs/sf/manuals/serve.sh` serves and the pages fetch.
- [ ] **Step 2: Re-run every example** — rebuild the seed compiler; compile+run all of `src/vol1/*.z98` (and the five error programs) and confirm each page's embedded transcript still matches byte-for-byte.
- [ ] **Step 3: No-CSS baseline** — every Volume I page is legible, navigable, and correctly ordered with the stylesheet links stripped.
- [ ] **Step 4: Navigation completeness** — every shipped chapter is linked in every Volume I page's sidebar, in `en/toc.html`, and in `en/vol1-00-title.html`; the `rel` prev/next chain is continuous `vol1-00 → … → vol1-15 → vol2-00-title`; no `(planned)` marker remains for a shipped chapter.
- [ ] **Step 5: Figure workflow** — the placeholder↔`todo-figures-list.html` mapping is 1:1 and each row names a concrete capture.
- [ ] **Step 6: Fix** any failure found (website only).
- [ ] **Step 7: Commit** — `git add docs/sf/manuals && git commit -m "docs(manual): Volume I closeout — whole-set review and verification sweep"`.

---

## Self-Review

- **Spec coverage:** spec §6 (HTML/CSS/JS/assets/forbidden) → Global Constraints + `check.sh`; §7 (figures) → each chapter's figure step + closeout step 5; §8 (content verification) → each chapter's compile+run + cross-check steps + closeout step 2; §11 (conventions) → Global Constraints; blueprint Part 3 (the sixteen chapters) → the sixteen chapter tasks; blueprint Part 9 Phase 1 ("all 16 chapters, all examples in `src/vol1/`, all screenshots") → the chapter table and Task 17.
- **Placeholder scan:** every chapter names its file, its sample program, and its observable result; the only in-task values are the captured transcripts, which the plan mandates be produced by real runs. No `TBD`/`TODO`.
- **Type/name consistency:** page filenames match the spec §4 tree and are unique; sample filenames match the blueprint Part 3 samples; the `rel` targets are the adjacent chapter files; the figure rows use the same `Page | Figure | Caption | Claim | What to capture` columns as Phase 0.
- **Open risks the tasks must verify (STOP if they fail):** ch 4 `zig1 --version` is a real flag; ch 14 `wc.z98` is feasible with beginner-level `std` file I/O; ch 13's five diagnostics reproduce verbatim; ch 7's `-fsafe`/`-ffast` overflow behavior is as documented.
- **Scope discipline:** the plan is website-only; the seed is not rotated; any compiler defect found while verifying a claim is a STOP, not a fix.
