# Z98 Manual — Volume III (Working in the Era) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author all 19 chapters of Volume III (Working in the Era), English, into the Phase 0 website under `docs/sf/manuals/`, each carrying the era's honesty as tradeoffs (not apology), a runnable example where the blueprint gives one, a "Common mistakes" list wherever there is code, and cross-references to Volume II and the Reference — every example compiled+run (or `-osw`/`wine`-verified) against the seed-built compiler.

**Architecture:** One plan, 19 chapter tasks plus a read-only capability inventory (Task 0) and a whole-set closeout (Task 20). The register-setter (chapter 2) and the mental shift (chapters 9–10) ship first, then the honesty spine (3–7), then the numeric fill (0, 1, 8, 11–18). Each chapter task: read its contract from the spec, verify feasibility (STOP if it fails), author the example under `src/vol3/`, capture the real transcript, write the page from the shipped template, cross-check every claim against `docs/reference/Language_Spec_Z98.md`, the compiler source, and the actual toolchain, add the figure placeholder and matching `todo-figures-list.html` row, wire the chapter's navigation, gate with `check.sh` + the index workaround, and commit. The site is correct after every commit; Task 20 is the whole-set review and verification sweep. The plan is website-only **except** operator-ruled scoped compiler I/F amendments.

**Tech Stack:** Hand-authored HTML 4.0 Transitional, CSS1, 1998-era vanilla JavaScript (`doc.js`), GIF assets, Python 3 standard library (`check.py`), the seed-built `zig1` + `gcc -m32`, `-osw`/OpenWatcom + `wine` for Win9x claims, git.

**Spec:** `docs/superpowers/specs/2026-09-30-z98-manual-volume-III-design.md` (binding for this plan). Program-level spec: `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (binding for every volume). Blueprint: `docs/sf/manuals/manuals_blueprint.txt` Part 5.

**Sequence:** PREVIOUS plan: `docs/superpowers/plans/2026-09-25-z98-manual-volume-II-plan.md` (Volume II, COMPLETE; all 21 chapters, seed rotated v88 → v89). NEXT plan: the Volume IV (Reference) plan.

**Compiler amendments (operator-ruled, inserted when a defect is found):** an amendment appends an I/F pair to this plan — **Task Na (I)** read-only investigation, **Task Nb (F)** fix with a `repro/mi_matrix/` fixture, a standalone `repro/` program, the QUICK_REF gate battery verbatim (STOP on unexpected movement), tech-doc updates, a two-hop closure verification with the moved fixed point recorded, and a commit. Amendment tasks are the **only** tasks permitted to touch `sf/src`, `scripts/`, `repro/`, or `release/seed/`, or to run the compiler gate battery. **Seed rotation is closeout-only:** F tasks verify the closure and record the moved fixed point; Task 20 rotates the seed once (iff the fixed point moved) via `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`.

## Global Constraints

- **Website only, with scoped exceptions (spec §5).** Do NOT edit `sf/src/**`, `scripts/**`, `repro/**`, or `release/seed/**` — EXCEPT tasks inserted by an operator-ruled compiler amendment. Only those tasks may edit the compiler, add fixtures/repros, run the compiler gate battery, or verify a moved fixed point. Every other task leaves the compiler fixed point and the seed untouched.
- **STOP on a real compiler defect** found while verifying a claim — report it with a minimal reproduction; do not fix `sf/src`, do not document around it, do not re-scope the chapter (spec §5; phase0 §9/§11). Compiler correctness takes priority over the manual; a defect becomes its own amendment.
- **All content files under `docs/sf/manuals/`** except this plan and its spec.
- **Blueprint-vs-reality rule (spec §2.1, phase0 §3).** The manual documents the current compiler and the actual era toolchain only. The ruled corrections: `.z98dbg` does not exist (chapter 15 is gdb-only); emitter-level socket builtins are gone (chapter 12 is the `std.net` extern surface); chapter 8 is the current `-osw` target (not `platform_win98.h`/`WINVER`/`_MBCS`); the `ddraw-mini.z98` example is dropped (chapter 14 is verifiable prose only). Never ship an unreproducible claim.
- **Tone and honesty (spec §3, binding).** The register is the *tradeoff* kind: no apology, no self-deprecation, no meta-defense; **no modern-language scoreboard** (a modern toolchain cannot run on the target); every stated limit is paired with its way over or is dropped; opinions are marked; chapters 3–5 say plainly when the other tool wins. Chapters 2–7 use the four-part honesty pattern (what you expect → what you get → the trade → the way over it).
- **HTML restrictions (phase0 §6.1).** HTML 4.0 Transitional, authored in the HTML 3.2/4.0 intersection. No HTML5 structural tags. No `<div>` for structure — layout uses `<table>`. ISO-8859-1 declared in the meta. Baseline appearance by presentational attributes and `<font>`/`<b>`/`<i>`/`<center>`. Every page carries `<link rel="home|up|prev|next">`, a sidebar TOC of the current volume, a language bar, and a prev/contents/next footer.
- **CSS restrictions (phase0 §6.2).** CSS1 only; `z98.css`/`z98-print.css` external linked stylesheets; **no inline `<style>`**; CSS carries no meaning or layout (the no-CSS baseline must stay legible).
- **JS restrictions (phase0 §6.3).** One file `doc.js`, ≤ 2048 bytes, four functions, no `document.write`, no browser sniffing.
- **Asset restrictions (phase0 §6.4).** GIF only; XBM alternates under `gfx/xbm/`.
- **Forbidden list (phase0 §6.5, checker-enforced).** HTML5 structural tags; `<div>` structure; PNG/SVG/web fonts; external resources (any `http://`/`https://` in `href`/`src`); inline `<style>`; `<script src>` other than `doc.js`; > 2048 bytes of JS; CSS2/CSS3.
- **Figures (phase0 §7).** Terminal transcripts are real runs in `<pre>`, not figures. Win9x screenshots are placeholder boxes plus a `todo-figures-list.html` row, 1:1 by figure number. The next free global figure number is **33** (32 is the last used by `vol2-18-print.html`); Task 0 confirms. Chapter-shipping figures in this plan: chapter 9 → 33, chapter 10 → 34, chapter 8 → 35, chapter 11 → 36, chapter 12 → 37 (only if it ships a sample), chapter 13 → 38 (only if it ships a sample).
- **Content verification (phase0 §8; spec §7).** Every example is compiled with the seed-built `zig1` and `gcc -m32`, actually run, and its transcript matched to the prose byte-for-byte; `-osw`/Win9x claims are run under `wine`; every syntax/builtin claim is cross-checked against `docs/reference/Language_Spec_Z98.md` and source.
- **Chapter shape (spec §4.2).** h1 title; **10–18 pages** of prose; a runnable example with its transcript where the page index gives a sample; a "Common mistakes" subsection wherever the chapter has code; a "Where to go next" cross-reference subsection; the §3 honesty pattern in chapters 2–7; one honesty callout wherever a limit/friction/era alternative is touched. No "Check yourself" (as Volume II).
- **Cross-references (spec §4.3).** Only files that exist may be `<a>`-linked. All Volume II chapters (`vol2-00` … `vol2-20`) and the shipped Reference pages (`vol4-00-title.html`, `vol4-15-builtins.html`, `vol4-24-html-style.html`) are linkable. Planned targets (most of Volume IV, all of Volume V/VI) are named in prose with `(planned)` and no link.
- **Navigation, non-contiguous shipping (spec §4.4).** The sidebar lists all 19 chapters on every shipped Volume III page (shipped = link, unshipped = `<i>(planned)</i>`). `rel` prev/next and the footer point at the **nearest shipped page** in that direction (or `toc.html` at the start). Task 20 restores the continuous chain; the last chapter's `next` is `vol4-00-title.html`.
- **English only.** The language bar carries English plus the "not yet available" plain-text entries, exactly as the existing pages do.
- **Edits via `edit`/`fastedit` only**; no bulk transforms. Never stage `mnemoria/`, `.opencode/`, or `.zig1_*.tmp`.
- **Reference compiler rebuilt per the seed model** (`release/seed/`), seed **v89** (archive md5 `a1549c5b5d9ad23da4d41d214d9ad3c5`; archived binary = fixed point `8216fedc8dd69db084d453be80f3c010`). The seed is rotated **only** by Task 20, and only if a compiler amendment moved the fixed point.
- **Environment deviation (binding for this volume).** `docs/sf/manuals/build.sh` hangs at `rm -rf docs/sf/manuals/dist` (filesystem-level; `dist` is gitignored). **Never run `build.sh` or `serve.sh`; never touch `dist`.** The mechanical gate is the read-only `bash docs/sf/manuals/check.sh`. Regenerate the search index with the `/tmp`-only workaround `/tmp/z98_build_tmp.sh` (writes only `/tmp/z98_search-data.regen.js` and `/tmp/z98_dist_tmp`); the regenerated `en/search-data.js` must byte-match the committed file — copy it over only if it differs, and report if it does.

## Compiler under test (for example verification)

Build the seed compiler once per session (repo root, relative path required):

```bash
FIXED_POINT_MD5=8216fedc8dd69db084d453be80f3c010 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
```

Compile and run an example (recipe in `docs/sf/QUICK_REF.md`):

```bash
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out docs/sf/manuals/src/vol3/<prog>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

Capture stdout, stderr, and `rc` as the transcript. For a `-osw`/Win9x claim, emit with `-osw` and run the `.exe` under `wine`. If the emitted script's argument order or default name differs, use the recipe in `docs/sf/QUICK_REF.md` verbatim. Every binary runs under `timeout 120`.

---

## File Structure

**Create (pages, flat in `docs/sf/manuals/en/`):**
- `vol3-02-honesty-inventory.html`, `vol3-03-when-c89.html`, `vol3-04-when-cpp98.html`, `vol3-05-when-assembly.html`, `vol3-06-era-limits.html`, `vol3-07-friction.html` (honesty spine)
- `vol3-09-coroutines.html`, `vol3-10-coroutine-program.html` (mental shift)
- `vol3-00-title.html`, `vol3-01-the-1998-machine.html`, `vol3-08-win9x.html`, `vol3-11-talking-to-c.html`, `vol3-12-winsock.html`, `vol3-13-debug-api.html`, `vol3-14-directx.html`, `vol3-15-debugger-workflow.html`, `vol3-16-memory-budgets.html`, `vol3-17-packaging.html`, `vol3-18-whats-next.html`

**Create (examples, `docs/sf/manuals/src/vol3/`):**
- `tasks.z98` (ch9), `echo.z98` (ch10), `hello.z98` (ch8), `getenv.z98` (ch11)
- `http-mini.z98` (ch12) and `dbg-mini.z98` (ch13) **only if Task 0 rules them feasible**; otherwise those chapters are prose + compile-only excerpts
- helper modules only where an example needs one (named in the task that creates it)

**Modify (existing):**
- `docs/sf/manuals/en/toc.html` — link Volume III and each shipped chapter (the `<h2>` anchor exists; add the volume title link and chapter links).
- `docs/sf/manuals/en/index.html`, `readme.html`, `search.html` — flip "III. Working in the Era (planned)" to a link where they list volumes.
- `docs/sf/manuals/en/search-data.js` — regenerated by the `/tmp` workaround (never hand-edited).
- `docs/sf/manuals/todo-figures-list.html` — one row per new placeholder.
- Every shipped `docs/sf/manuals/en/vol3-*.html` — flip this chapter's sidebar entry from `(planned)` to a link; keep rel/footer nearest-shipped links correct. Also update shipped `vol2-20-whats-next.html` (and any other page that names Volume III as `(planned)`) to link the Volume III title page once it ships.
- `docs/superpowers/specs/2026-09-30-z98-manual-volume-III-design.md` — status line at closeout (Task 20).

**Reference (read-only):** `docs/sf/manuals/manuals_blueprint.txt` (Part 5), `docs/reference/Language_Spec_Z98.md`, `docs/reference/builtins.md`, `docs/sf/QUICK_REF.md`, `docs/sf/manuals/en/vol4-24-html-style.html` (template/contract), the shipped `en/vol2-20-whats-next.html` and the honesty page `en/vol2-01-honest-comparison.html` (register reference), the tech docs for coroutines (`sf/docs/tech_docs/12_async_coroutines.md` if present), and the closed parity-plan residuals in `repro/mi_matrix/EXPECTED_FAIL.md`.

---

## How each chapter task works

Every chapter task follows this shape. Steps are written out per task below; the shared rules are:

1. **Read the sources** — the chapter's contract in spec §2.2, the blueprint Part 5 row, and the spec §3 tone rules; list the exact claims to verify.
2. **Verify feasibility first (STOP if it fails)** where the chapter depends on an API/behavior/toolchain that may not exist (coroutines, `std.net`, Win32 APIs, `-osw`); report to the operator instead of inventing it.
3. **Author the example(s)** under `src/vol3/`, compile+run with the seed compiler, and capture the exact transcript (or `-osw` emit + `wine` run for Win-only).
4. **Write the page** from the `vol4-24-html-style.html` skeleton — sidebar (all 19 Volume III chapters, shipped ones linked, unshipped `(planned)`), language bar, `rel` home/up/prev/next (nearest shipped), 10–18 pages of prose per the chapter's "Must cover" list, the runnable example(s) with transcripts in `<pre>`, the §3 honesty pattern for chapters 2–7, "Common mistakes" wherever there is code, "Where to go next" (existing pages only), one honesty callout where warranted, and the Win9x note where the chapter ships a program.
5. **Cross-check every claim** against `docs/reference/Language_Spec_Z98.md`, the compiler source, and the actual toolchain.
6. **Figures:** add the placeholder box and the matching `todo-figures-list.html` row (1:1) using the chapter's figure number (task table above).
7. **Wire the chapter:** flip this chapter's sidebar entry from `(planned)` to a link on every shipped `en/vol3-*.html` page, in `en/toc.html`, and in `en/vol3-00-title.html` if it exists; set the new page's `rel`/footer prev/next to its nearest shipped neighbors and update those neighbors' `rel`/footer; link the chapter from `en/index.html`/`readme.html` where the volume index lists chapters.
8. **Verify:** `bash docs/sf/manuals/check.sh` passes; regenerate the search index with `/tmp/z98_build_tmp.sh` and confirm it byte-matches the committed `en/search-data.js` (copy + report if it differs). Do NOT run `build.sh`.
9. **Commit:** `git add docs/sf/manuals && git commit -m "docs(manual): add Volume III chapter NN — <title>"`.

---

### Task 0: Capability inventory (read-only)

**Files:**
- Read-only: `sf/src/**` (as needed), `docs/reference/Language_Spec_Z98.md`, `docs/reference/builtins.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `docs/sf/manuals/**`.
- Create (untracked): `.superpowers/sdd/2026-09-30-z98-manual-volume-III-plan/task-0-report.md`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the spec's chapter contracts (§2.2), the ruled phase0 §3 corrections (§2.1), and the open items (§9).
- Produces: the capability matrix the chapter tasks rely on — for each chapter 0–18, every "Must cover" claim marked **verified on seed v89** / **needs a corrected claim** / **defect → amendment**; the coroutine API + frame ABI; the Win9x build path; the `std.net` socket surface; which of chapters 12/13 can ship a real sample; the Z98 spellings the blueprint gets wrong; the closed Volume II residuals touching Volume III topics; the next free figure number; and the predicted compiler I/F pairs.

- [ ] **Step 1: Build the compiler** per "Compiler under test" and record its md5 (`md5sum /tmp/manual_seed/zig1_5_clean`).
- [ ] **Step 2: Build the capability matrix** — for each chapter 0–18, reproduce each "Must cover" item (spec §2.2) against the compiler and the Language Spec with small `.z98` probes (compile+run). Cover at minimum: the coroutine builtins and frame ABI (ch9/10), the current `-osw` build path and its scripts (ch8), `extern fn`/`@cInclude`/mangling (ch11), the `std.net` surface (ch12), the Win32 extern surface for the debug API (ch13), the gdb/`--markers` workflow (ch15), `--track-memory`/`-mm0`/arena tiers (ch16), and the build-script shape (ch17). Record verdicts with the probe command and output.
- [ ] **Step 3: Apply and verify the phase0 §3 corrections** — confirm `.z98dbg` absence, the socket-builtin removal, the current Win9x target (vs `platform_win98.h`/`WINVER`/`_MBCS`), and DirectX-header absence; record the exact replacement wording each chapter uses.
- [ ] **Step 4: Inventory the residuals** — read `repro/mi_matrix/EXPECTED_FAIL.md` and the Volume II closeout record (its spec §10) for residuals touching Volume III topics; for each, note whether a chapter's "Must cover" item depends on it.
- [ ] **Step 5: Confirm the figure numbering** — the highest used figure number in `todo-figures-list.html` (expected 32; next free 33) and the per-chapter assignment in Global Constraints.
- [ ] **Step 6: Predict the compiler I/F pairs** — the claims most likely to fail (highest risk first: coroutines, `std.net`, the Win32 debug API, `-osw`), with the probe evidence.
- [ ] **Step 7: Write the report** to the workspace path above and return a summary. No commit.

---

### Task 1: Chapter 2 — Honesty: what Z98 does and doesn't give you (register-setter)

**Files:**
- Create: `docs/sf/manuals/en/vol3-02-honesty-inventory.html`
- Modify: `docs/sf/manuals/en/toc.html`; `en/index.html`, `readme.html` where they list volumes; `en/vol2-20-whats-next.html` (link Volume III) if it names it `(planned)`.
- Read: `en/vol2-01-honest-comparison.html`, `en/vol2-16-no-methods.html`, `docs/reference/Language_Spec_Z98.md` §4.

**Interfaces:**
- Consumes: spec §2.2 chapter 2, §3 tone rules; blueprint line 179; Volume II chapters 1 and 16 (register + no-methods list).
- Produces: the volume's register-setter page; the gives/doesn't-give inventory every later honesty chapter cites.

- [ ] **Step 1: Verify the inventory first (STOP if a claim fails)** — for every "gives you" item, confirm it on seed v89 (error unions, optionals, coroutines, the arena, comptime-introspection builtins, deterministic C89 emission, self-hosting); for every "doesn't give you" item, confirm the reject/absence (generics, templates, classes, exceptions, RTTI, threads, preemption, dynamic dispatch beyond manual vtables, `anyerror`, `comptime` beyond the builtins, package manager, IDE integration, dynamic linking to modern libraries). STOP and report any item that behaves differently.
- [ ] **Step 2: Pair every "doesn't give you" item with its era alternative** — manual vtable, `std.async`, arena tiers, `@ptrCast`/manual dispatch, C89/C++98/asm, etc. (spec §3 rule 3). No bare absences.
- [ ] **Step 3: Write the page** — the four-part honesty pattern; the gives/doesn't-give tables; consistent with Volume II chapter 1 and chapter 16; 10–18 pages; one honesty callout; "Common mistakes"; "Where to go next" (link chapter 9, Volume II ch1/ch16, and `vol4-15-builtins.html`). No sample.
- [ ] **Step 4: Wire** — create `en/toc.html` and index links; set `rel` home/up to `toc.html`, prev/next to the nearest shipped (none yet → `toc.html`/itself-guarded per the template; Task 2 will re-point).
- [ ] **Step 5: Verify** — `check.sh`; index-regeneration byte-match.
- [ ] **Step 6: Commit** — `docs(manual): add Volume III chapter 2 — what Z98 does and does not give you`.

---

### Task 2: Chapter 3 — Honesty: when C89 is the better choice

**Files:**
- Create: `docs/sf/manuals/en/vol3-03-when-c89.html`
- Modify: `en/toc.html`; every shipped `en/vol3-*.html` sidebar; `vol3-02` `rel`/footer.

**Interfaces:**
- Consumes: spec §2.2 chapter 3; blueprint line 180; §3 tone rules.
- Produces: the "mix freely" chapter; the C89-interop proof later chapters (11) build on.

- [ ] **Step 1: Verify the load-bearing claim** — "Z98 emits C89, so you can mix the two freely": compile a Z98 program that calls an `extern fn` defined in a hand-written C89 file, and compile a Z98-emitted TU with `gcc -std=c89 -pedantic -Wall`; run it. Capture the transcript.
- [ ] **Step 2: Write the page** — the six "C89 is better" cases (library only in C89; maintaining C89; maximum toolchain compatibility; widest compiler support; no need for error unions/coroutines; smallest dependency surface); the four-part pattern; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** per the shared shape. Commit `docs(manual): add Volume III chapter 3 — when C89 is the better choice`.

---

### Task 3: Chapter 4 — Honesty: when C++98 is the better choice

**Files:**
- Create: `docs/sf/manuals/en/vol3-04-when-cpp98.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-03` `rel`/footer.

**Interfaces:**
- Consumes: spec §2.2 chapter 4; blueprint line 181.
- Produces: the C++98 trade chapter.

- [ ] **Step 1: Verify the illustrative fragment** — compile a small C++98 template fragment with `g++ -m32 -std=c++98` (as the Volume II chapter 1 rework does) to show what the reader would write; keep it illustrative, not a `src/vol3` sample.
- [ ] **Step 2: Write the page** — templates with the era's incomplete implementations; classes/virtual dispatch and the runtime cost; MSVC 6 / Borland 5.02 idioms; the honest "possible but fragile on 32 MB" trade and when the manual-vtable idiom wins; four-part pattern; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 4 — when C++98 is the better choice`.

---

### Task 4: Chapter 5 — Honesty: when assembly is the better choice

**Files:**
- Create: `docs/sf/manuals/en/vol3-05-when-assembly.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-04` `rel`/footer.

**Interfaces:**
- Consumes: spec §2.2 chapter 5; blueprint line 182.
- Produces: the drop-to-asm chapter.

- [ ] **Step 1: Verify the path** — produce the emitted C for a small Z98 function (`-o` tree), compile it with `gcc -m32 -S` to show the assembly hand-off, and link a hand-written `.s`/`.asm` symbol called from Z98 via `extern fn`; run. Capture.
- [ ] **Step 2: Write the page** — inner loops, ISRs, "when the C89 emission isn't tight enough"; the `.c`/`.asm` drop and link-back; four-part pattern; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 5 — when assembly is the better choice`.

---

### Task 5: Chapter 6 — Honesty: what you can't do on a Pentium II

**Files:**
- Create: `docs/sf/manuals/en/vol3-06-era-limits.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-05` `rel`/footer.

**Interfaces:**
- Consumes: spec §2.2 chapter 6; blueprint line 183.
- Produces: the era-limits chapter.

- [ ] **Step 1: Verify what is verifiable** — where a Z98 angle exists (e.g. no multithreading → `std.async` cooperatives; memory limits → arena), confirm it; otherwise state the era fact with a citation. Mark every opinion.
- [ ] **Step 2: Write the page** — no hardware 3D at modern resolutions; no large textures; no real-time MP3 on a PII-233; no multithreading worth the cost; no networking beyond WinSock 2; "the era had limits, and respecting them is the point"; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 6 — what you cannot do on a Pentium II`.

---

### Task 6: Chapter 7 — Honesty: the friction you will hit

**Files:**
- Create: `docs/sf/manuals/en/vol3-07-friction.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-06` `rel`/footer.

**Interfaces:**
- Consumes: spec §2.2 chapter 7; blueprint line 184.
- Produces: the friction chapter.

- [ ] **Step 1: Verify the claims** — OpenWatcom C89-dialect differences (from Task 0's `-osw` measurements); the two-hop seed rebuild (run `build_from_seed.sh` and record the gate); numbered/sparse errors (a real `error[NNNN]` example); no debugger UI (gdb on generated C, ch15). Each item gets its "what to do".
- [ ] **Step 2: Write the page** — not pessimistic, accurate; each friction with what to do about it; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 7 — the friction you will hit`.

---

### Task 7: Chapter 9 — Coroutines, the third big shift (mental shift)

**Files:**
- Create: `docs/sf/manuals/en/vol3-09-coroutines.html`
- Create: `docs/sf/manuals/src/vol3/tasks.z98`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-07` `rel`/footer; `todo-figures-list.html` (figure 33).

**Interfaces:**
- Consumes: spec §2.2 chapter 9; blueprint line 186; Task 0's coroutine API/frame-ABI verdict; the tech doc for coroutines.
- Produces: the mental-shift chapter and `tasks.z98`; the coroutine chapter 10 builds on.

- [ ] **Step 1: Verify the API first (STOP if it fails)** — compile probes for `@asyncInit`, `@asyncSuspend`, `@asyncResume`, `@asyncFrameSize`, the state-word width rule, `std.async`'s scheduler; confirm every name and behavior against `docs/reference/Language_Spec_Z98.md`, the tech doc, and the compiler source. If the blueprint's API does not exist, STOP and report.
- [ ] **Step 2: Author `tasks.z98`** — N tasks suspending in a known order under the scheduler; compile+run; capture the transcript.
- [ ] **Step 3: Write the page** — the suspending-function analysis; the frame layout; the state-word width rule; the child-frame pool; why this replaces hand-rolled state machines; the "you will reach for a `switch` on a state variable; here is the Z98 way" paragraph; 10–18 pages.
- [ ] **Step 4: Cross-check** — every frame/layout number against the emitted C and the spec.
- [ ] **Step 5: Figure 33** — placeholder + todo row (build-and-run claim).
- [ ] **Step 6: Wire** — sidebar, `toc.html`, `rel` prev/next; `vol3-07` updated.
- [ ] **Step 7: Verify** — `check.sh`; index-regeneration byte-match.
- [ ] **Step 8: Commit** `docs(manual): add Volume III chapter 9 — coroutines`.

---

### Task 8: Chapter 10 — A coroutine program

**Files:**
- Create: `docs/sf/manuals/en/vol3-10-coroutine-program.html`
- Create: `docs/sf/manuals/src/vol3/echo.z98`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-09` `rel`/footer; `todo-figures-list.html` (figure 34).

**Interfaces:**
- Consumes: spec §2.2 chapter 10; blueprint line 187; Task 7's verified API.
- Produces: the worked coroutine program.

- [ ] **Step 1: Verify feasibility (STOP if it fails)** — the blueprint's "one coroutine per connection / line echo server" needs a working transport; determine from Task 0 whether `std.net` runs on the Linux host. If not, use the alternative the blueprint explicitly permits: **a cooperative task demo with N tasks suspending in a known order**. Report which shape was chosen.
- [ ] **Step 2: Author `echo.z98`** — the chosen shape; compile+run; capture the transcript (a network shape is `wine`/Win-only and compile+`wine`-verified).
- [ ] **Step 3: Write the page** — the program walked line by line; the scheduler; 10–18 pages.
- [ ] **Step 4: Figure 34 + wire + verify** per the shared shape.
- [ ] **Step 5: Commit** `docs(manual): add Volume III chapter 10 — a coroutine program`.

---

### Task 9: Chapter 0 — Title and how to read this

**Files:**
- Create: `docs/sf/manuals/en/vol3-00-title.html`
- Modify: `en/toc.html`; `en/index.html`, `readme.html`; every shipped `en/vol3-*.html` sidebar; `vol3-02`/`vol3-03` `rel` chains.

**Interfaces:**
- Consumes: spec §2.2 chapter 0; blueprint line 177.
- Produces: the Volume III title page; the sidebar's chapter-0 row.

- [ ] **Step 1: Write the page** — Volume III is about the discipline, not the syntax; assumes Volume II fluency; entry/exit states; how the volume is built (chapter shape, callouts, `src/vol3/`, the seed recipe); reading paths; "some of it is opinion, and where it is, it's marked". No sample.
- [ ] **Step 2: Wire** — sidebar row 0 becomes a link on every shipped page; `rel` chain from chapter 0 to its nearest shipped successor; `toc.html` title link; index/readme flip Volume III to a link.
- [ ] **Step 3: Verify + commit** `docs(manual): add Volume III chapter 0 — how to read this`.

---

### Task 10: Chapter 1 — The 1998 machine

**Files:**
- Create: `docs/sf/manuals/en/vol3-01-the-1998-machine.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-00`/`vol3-02` `rel` chains.

**Interfaces:**
- Consumes: spec §2.2 chapter 1; blueprint line 178.
- Produces: the machine chapter.

- [ ] **Step 1: Verify what can be verified** — the compiler's target model (32-bit, align-8 — Volume II FX14), the 16 MB peak budget, `-osw`, and the era hardware facts as stated. Mark opinions.
- [ ] **Step 2: Write the page** — Pentium II, 32 MB, Windows 95/98, IDE drives, 640×480; what you can/cannot assume; why memory is the binding constraint, not CPU; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 1 — the 1998 machine`.

---

### Task 11: Chapter 8 — Building for Win9x

**Files:**
- Create: `docs/sf/manuals/en/vol3-08-win9x.html`
- Create: `docs/sf/manuals/src/vol3/hello.z98`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-07`/`vol3-09` `rel` chains; `todo-figures-list.html` (figure 35).

**Interfaces:**
- Consumes: spec §2.2 chapter 8; blueprint line 185; Task 0's `-osw` verdict.
- Produces: the Win9x build chapter and its `hello.z98`.

- [ ] **Step 1: Verify the build path first (STOP if it fails)** — emit `hello.z98` with `-osw`, inspect the emitted `build_owc.bat`/`build_target.bat`, build with mingw and run under `wine`; record the exact commands. Confirm which of the blueprint's `platform_win98.h`/`WINVER`/`_MBCS` claims survive the Phase 0 §3 rewrite (they do not; use the current target).
- [ ] **Step 2: Author `hello.z98`** — the Win9x walkthrough program (from Volume I's hello, adapted); compile+`-osw` emit+`wine` run; capture.
- [ ] **Step 3: Write the page** — OpenWatcom, the build scripts, `_WIN32`, running under 86Box/the era OS; 10–18 pages.
- [ ] **Step 4: Figure 35 + wire + verify** per the shared shape.
- [ ] **Step 5: Commit** `docs(manual): add Volume III chapter 8 — building for Win9x`.

---

### Task 12: Chapter 11 — Talking to C

**Files:**
- Create: `docs/sf/manuals/en/vol3-11-talking-to-c.html`
- Create: `docs/sf/manuals/src/vol3/getenv.z98`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-10`/`vol3-12` `rel` chains; `todo-figures-list.html` (figure 36).

**Interfaces:**
- Consumes: spec §2.2 chapter 11; blueprint line 188; Task 0's extern/mangling verdict.
- Produces: the C-interop chapter and `getenv.z98`.

- [ ] **Step 1: Verify the surface first (STOP if it fails)** — `extern fn`, `@cInclude` **module-level only** (measure the statement-position reject), struct-by-value ABI, calling conventions, the reserved-name rules, and identifier mangling; capture the exact diagnostics.
- [ ] **Step 2: Author `getenv.z98`** — call `getenv` via `extern` and print a value; compile+run; capture.
- [ ] **Step 3: Write the page** — the whole interop surface; 10–18 pages.
- [ ] **Step 4: Figure 36 + wire + verify** per the shared shape.
- [ ] **Step 5: Commit** `docs(manual): add Volume III chapter 11 — talking to C`.

---

### Task 13: Chapter 12 — WinSock under Z98

**Files:**
- Create: `docs/sf/manuals/en/vol3-12-winsock.html`
- Create (only if Task 0 rules feasible): `docs/sf/manuals/src/vol3/http-mini.z98`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-11`/`vol3-13` `rel` chains; `todo-figures-list.html` (figure 37, only if a sample ships).

**Interfaces:**
- Consumes: spec §2.2 chapter 12; blueprint line 189; Task 0's `std.net` surface verdict.
- Produces: the WinSock chapter; the `std.net`-based sample if feasible.

- [ ] **Step 1: Verify the `std.net` surface first (STOP/report if the blueprint's API does not exist)** — enumerate the actual `sf/src/std_net.zig` extern surface; confirm the `WSAStartup`/`socket`/`bind`/`listen`/`accept`/`recv`/`send`/`select`/`closesocket` shapes and the `SOCKET` unsigned-comparison rule; confirm `fd_set` is an opaque blob.
- [ ] **Step 2: Rule the sample** — if a Win-only `http-mini.z98` compiles and is `wine`-verifiable, author it; otherwise the chapter ships compile-only excerpts and no figure, and the task says so.
- [ ] **Step 3: Write the page** — the socket surface, the comparison rule, `fd_set`; 10–18 pages.
- [ ] **Step 4: Figure 37 (iff a sample shipped) + wire + verify** per the shared shape.
- [ ] **Step 5: Commit** `docs(manual): add Volume III chapter 12 — WinSock under Z98`.

---

### Task 14: Chapter 13 — The Win32 Debug API

**Files:**
- Create: `docs/sf/manuals/en/vol3-13-debug-api.html`
- Create (only if Task 0 rules feasible): `docs/sf/manuals/src/vol3/dbg-mini.z98`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-12`/`vol3-14` `rel` chains; `todo-figures-list.html` (figure 38, only if a sample ships).

**Interfaces:**
- Consumes: spec §2.2 chapter 13; blueprint line 190; Task 0's Win32-extern feasibility verdict.
- Produces: the debug-API chapter; the sample if feasible.

- [ ] **Step 1: Verify expressibility first (STOP/report if it fails)** — can the compiler express the required `extern` surface (`CreateProcess`, `WaitForDebugEvent`, `ContinueDebugEvent`, `GetThreadContext`, `ReadProcessMemory`, `WriteProcessMemory`, `INT3` patching, `_MEMORY_BASIC_INFORMATION`)? At minimum compile a probe; run under `wine` only if the sample is feasible.
- [ ] **Step 2: Rule the sample** — runnable/`wine`-verifiable `dbg-mini.z98`, or prose + compile-only excerpts with no figure. Say which.
- [ ] **Step 3: Write the page** — the API walkthrough and the `_MEMORY_BASIC_INFORMATION` workaround; 10–18 pages.
- [ ] **Step 4: Figure 38 (iff a sample shipped) + wire + verify** per the shared shape.
- [ ] **Step 5: Commit** `docs(manual): add Volume III chapter 13 — the Win32 Debug API`.

---

### Task 15: Chapter 14 — DirectX 7/8 under CINTERFACE

**Files:**
- Create: `docs/sf/manuals/en/vol3-14-directx.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-13`/`vol3-15` `rel` chains.

**Interfaces:**
- Consumes: spec §2.2 chapter 14; blueprint line 191; the phase0 §3 ruling (example dropped).
- Produces: the DirectX era-context chapter, no sample.

- [ ] **Step 1: Verify what prose is defensible** — confirm no DirectX headers/example exist in the repo (phase0 §3); keep era-context statements only where verifiable (to the extent the declared target/COM-in-C89 facts are checkable), and mark opinion.
- [ ] **Step 2: Write the page** — COM in C89, `lpVtbl` calls, the `IUnknown` base, `DirectDrawCreate`/`DirectInput8Create`/`DirectSoundCreate`, header pain under OpenWatcom; explicitly no sample (ruled). 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 14 — DirectX under CINTERFACE`.

---

### Task 16: Chapter 15 — The debugger workflow

**Files:**
- Create: `docs/sf/manuals/en/vol3-15-debugger-workflow.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-14`/`vol3-16` `rel` chains.

**Interfaces:**
- Consumes: spec §2.2 chapter 15; blueprint line 192; Task 0's gdb/`--markers` verdict; the phase0 §3 ruling (`.z98dbg` dropped).
- Produces: the debugger-workflow chapter, no sample.

- [ ] **Step 1: Verify the workflow** — run gdb on a generated C file; confirm the `cd DIR` gotcha and absolute `-I` paths; capture `--markers` output on a real program. Do not reference `.z98dbg`.
- [ ] **Step 2: Write the page** — the gdb-on-generated-C workflow, the gotchas, reading `--markers`; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 15 — the debugger workflow`.

---

### Task 17: Chapter 16 — Memory budgets

**Files:**
- Create: `docs/sf/manuals/en/vol3-16-memory-budgets.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-15`/`vol3-17` `rel` chains.

**Interfaces:**
- Consumes: spec §2.2 chapter 16; blueprint line 193; Task 0's `--track-memory`/`-mm0` verdict.
- Produces: the memory-budgets chapter, no sample.

- [ ] **Step 1: Verify the measurements** — run `--track-memory` on a real program and record the peaks; confirm the arena tiers and the `-mm0` switch behavior; state the 16 MB budget claim against the measured evidence.
- [ ] **Step 2: Write the page** — staying under 16 MB, arena tiers, dual arenas at scale, profiling, `-mm0`; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 16 — memory budgets`.

---

### Task 18: Chapter 17 — Packaging and shipping

**Files:**
- Create: `docs/sf/manuals/en/vol3-17-packaging.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-16`/`vol3-18` `rel` chains.

**Interfaces:**
- Consumes: spec §2.2 chapter 17; blueprint line 194.
- Produces: the packaging chapter, no sample (no `dist/` generation).

- [ ] **Step 1: Verify what reproduces** — the release shape (`build_owc.bat` convention, what goes on the diskette, self-extracting archives) only to the extent the repo's scripts and Task 0 support it; mark opinion; never generate `dist/`.
- [ ] **Step 2: Write the page** — the release shape and the era distribution constraints; 10–18 pages.
- [ ] **Step 3: Wire + verify + commit** `docs(manual): add Volume III chapter 17 — packaging and shipping`.

---

### Task 19: Chapter 18 — What you've learned, what's next

**Files:**
- Create: `docs/sf/manuals/en/vol3-18-whats-next.html`
- Modify: `en/toc.html`; shipped `en/vol3-*.html` sidebars; `vol3-17` `rel`/footer; `vol3-18` `rel` next → `vol4-00-title.html`.

**Interfaces:**
- Consumes: spec §2.2 chapter 18; blueprint line 195.
- Produces: the volume finale; the handoff to the Reference/HOWTO/Internals.

- [ ] **Step 1: Write the page** — you can ship for 1998; Reference and HOWTO are for lookup; the examples tree has full case studies; honesty callout; handoff to Volume IV (Reference) / Volume V (HOWTO) / Volume VI (Internals) as `(planned)` prose (link `vol4-00-title.html`, which exists). No sample.
- [ ] **Step 2: Wire** — `rel` prev/next chain complete to `vol4-00-title.html`.
- [ ] **Step 3: Verify + commit** `docs(manual): add Volume III chapter 18 — what you have learned`.

---

### Task 20: Whole-set closeout

**Files:**
- Modify: every shipped `docs/sf/manuals/en/vol3-*.html` if the navigation sweep needs it; `en/toc.html`; `todo-figures-list.html`; `docs/superpowers/specs/2026-09-30-z98-manual-volume-III-design.md` (status); `release/seed/**` (iff rotation); `docs/sf/QUICK_REF.md` (iff rotation).
- Create (untracked): `.superpowers/sdd/2026-09-30-z98-manual-volume-III-plan/task-20-report.md`.

**Interfaces:**
- Consumes: every chapter task; the amendment tasks if any.
- Produces: the verified, continuously-navigable Volume III; the spec status; the rotated seed iff the fixed point moved.

- [ ] **Step 1: Re-run every example** — all `docs/sf/manuals/src/vol3/*.z98` compile+run on the current seed; each page transcript matches byte-for-byte (`-osw`+`wine` for Win-only).
- [ ] **Step 2: Navigation continuity** — no shipped Volume III chapter carries `(planned)` in its own row; the `rel` chain is continuous `toc.html → vol3-00 → … → vol3-18 → vol4-00-title.html`; every sidebar lists 19 chapters; `vol2-20-whats-next.html` and any other page naming Volume III as `(planned)` links the title page.
- [ ] **Step 3: Figure audit** — `todo-figures-list.html` is 1:1 with on-page placeholders, numbers unique, no gaps.
- [ ] **Step 4: Gates** — `bash docs/sf/manuals/check.sh` passes; the `/tmp` index regeneration byte-matches the committed `en/search-data.js` idempotently. Do NOT run `build.sh`.
- [ ] **Step 5: Spec status** — set the Volume III spec's status to **Implemented** and record the closeout (rulings, seed rotation, residuals, environment deviation).
- [ ] **Step 6: Seed rotation (iff an amendment moved the fixed point)** — `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`; verify the post-rotation two-hop closure; update the QUICK_REF "Current seed" block.
- [ ] **Step 7: Whole-set review** — dispatch the final whole-branch review over the Volume III range; fix or park per the loop.
- [ ] **Step 8: Commit** `docs(manual): Volume III closeout — whole-set review and verification sweep`.

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: §2.2's 19 chapters → Tasks 1–19 (order in §2.3: ch2, ch3–7, ch9–10, then 0/1/8/11–18); §3 tone rules are Global Constraints and are re-read by every honesty task; §4 page shape/figures/nav are the shared 9-step shape; §5/§6 the defect policy and amendment protocol; §7 verification is step 8 plus Task 20; §8 is Task 0; §9 open items are Task 0's steps 2–6.

**Placeholder scan.** No `TBD`/`TODO`; the two genuinely Task-0-dependent samples (ch12, ch13) are written as explicit conditional branches with the ruling recorded in the task, not left vague. The ch10 sample has the blueprint's own permitted alternative (cooperative task demo) written in as the fallback.

**Consistency.** Chapter numbers, page filenames, sample names, task numbers, and figure numbers are consistent between the spec's §2.1 table and this plan's task headers (Task 1 = ch2 … Task 19 = ch18; Task 20 closeout; figures 33–38). The harness/evidence vocabulary (seed v89 fixed point `8216fedc…`, `check.sh`, the `/tmp` index workaround, `-osw`+`wine`) is identical throughout.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-30-z98-manual-volume-III-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
