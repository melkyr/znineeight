# Z98 Manual — Volume III (Working in the Era) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author all 19 chapters of Volume III (Working in the Era), English, into the Phase 0 website under `docs/sf/manuals/`, each carrying the era's honesty as tradeoffs (not apology), a runnable example where the blueprint gives one, a "Common mistakes" list wherever there is code, and cross-references to Volume II and the Reference — every example compiled+run (or `-osw`/`wine`-verified) against the seed-built compiler.

**Architecture:** One plan, 19 chapter tasks plus a read-only capability inventory (Task 0) and a whole-set closeout (Task 20). The register-setter (chapter 2) and the mental shift (chapters 9–10) ship first, then the honesty spine (3–7), then the numeric fill (0, 1, 8, 11–18). Each chapter task: read its contract from the spec, verify feasibility (STOP if it fails), author the example under `src/vol3/`, capture the real transcript, write the page from the shipped template, cross-check every claim against `docs/reference/Language_Spec_Z98.md`, the compiler source, and the actual toolchain, add the figure placeholder and matching `todo-figures-list.html` row, wire the chapter's navigation, gate with `check.sh` + the index workaround, and commit. The site is correct after every commit; Task 20 is the whole-set review and verification sweep. The plan is website-only **except** operator-ruled scoped compiler I/F amendments.

**Tech Stack:** Hand-authored HTML 4.0 Transitional, CSS1, 1998-era vanilla JavaScript (`doc.js`), GIF assets, Python 3 standard library (`check.py`), the seed-built `zig1` + `gcc -m32`, the committed `scripts/win32_cross/` harness (`i686-w64-mingw32-gcc` + 32-bit `wine`) for Win9x claims, git.

**Spec:** `docs/superpowers/specs/2026-09-30-z98-manual-volume-III-design.md` (binding for this plan). Program-level spec: `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (binding for every volume). Blueprint: `docs/sf/manuals/manuals_blueprint.txt` Part 5.

**Sequence:** PREVIOUS plan: `docs/superpowers/plans/2026-09-25-z98-manual-volume-II-plan.md` (Volume II, COMPLETE; all 21 chapters, seed rotated v88 → v89). NEXT plan: the Volume IV (Reference) plan.

**Compiler amendments (operator-ruled, inserted when a defect is found):** an amendment appends an I/F pair to this plan — **Task Na (I)** read-only investigation, **Task Nb (F)** fix with a `repro/mi_matrix/` fixture, a standalone `repro/` program, the QUICK_REF gate battery verbatim (STOP on unexpected movement), tech-doc updates, a two-hop closure verification with the moved fixed point recorded, and a commit. Amendment tasks are the **only** tasks permitted to touch `sf/src`, `scripts/`, `repro/`, or `release/seed/`, or to run the compiler gate battery. **Seed rotation is closeout-only:** F tasks verify the closure and record the moved fixed point; Task 20 rotates the seed once (iff the fixed point moved) via `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`.

## Global Constraints

- **Website only, with scoped exceptions (spec §5).** Do NOT edit `sf/src/**`, `scripts/**`, `repro/**`, or `release/seed/**` — EXCEPT tasks inserted by an operator-ruled compiler amendment. Only those tasks may edit the compiler, add fixtures/repros, run the compiler gate battery, or verify a moved fixed point. Every other task leaves the compiler fixed point and the seed untouched.
- **STOP on a real compiler defect** found while verifying a claim — report it with a minimal reproduction; do not fix `sf/src`, do not document around it, do not re-scope the chapter (spec §5; phase0 §9/§11). Compiler correctness takes priority over the manual; a defect becomes its own amendment.
- **All content files under `docs/sf/manuals/`** except this plan and its spec.
- **Blueprint-vs-reality rule (spec §2.1, phase0 §3).** The manual documents the current compiler and the actual era toolchain only. The ruled corrections: `.z98dbg` does not exist (chapter 15 is gdb-only); emitter-level socket builtins are gone (chapter 12 is the `std.net` extern surface); chapter 8 is the current `-osw` target (the bootstrap `platform_win98.h`/`_MBCS` are gone; the emitted `ZIG_WIN32` target does define `WINVER 0x0410` for `@console*`-using modules — never claim `WINVER` is absent); the `ddraw-mini.z98` example is dropped (chapter 14 is verifiable prose only). Never ship an unreproducible claim.
- **Tone and honesty (spec §3, binding).** The register is the *tradeoff* kind: no apology, no self-deprecation, no meta-defense; **no modern-language scoreboard** (a modern toolchain cannot run on the target); every stated limit is paired with its way over or is dropped; opinions are marked; chapters 3–5 say plainly when the other tool wins. Chapters 2–7 use the four-part honesty pattern (what you expect → what you get → the trade → the way over it).
- **HTML restrictions (phase0 §6.1).** HTML 4.0 Transitional, authored in the HTML 3.2/4.0 intersection. No HTML5 structural tags. No `<div>` for structure — layout uses `<table>`. ISO-8859-1 declared in the meta. Baseline appearance by presentational attributes and `<font>`/`<b>`/`<i>`/`<center>`. Every page carries `<link rel="home|up|prev|next">`, a sidebar TOC of the current volume, a language bar, and a prev/contents/next footer.
- **CSS restrictions (phase0 §6.2).** CSS1 only; `z98.css`/`z98-print.css` external linked stylesheets; **no inline `<style>`**; CSS carries no meaning or layout (the no-CSS baseline must stay legible).
- **JS restrictions (phase0 §6.3).** One file `doc.js`, ≤ 2048 bytes, four functions, no `document.write`, no browser sniffing.
- **Asset restrictions (phase0 §6.4).** GIF only; XBM alternates under `gfx/xbm/`.
- **Forbidden list (phase0 §6.5, checker-enforced).** HTML5 structural tags; `<div>` structure; PNG/SVG/web fonts; external resources (any `http://`/`https://` in `href`/`src`); inline `<style>`; `<script src>` other than `doc.js`; > 2048 bytes of JS; CSS2/CSS3.
- **Figures (phase0 §7).** Terminal transcripts are real runs in `<pre>`, not figures. Win9x screenshots are placeholder boxes plus a `todo-figures-list.html` row, 1:1 by figure number. The next free global figure number is **33** (32 is the last used by `vol2-18-print.html`); Task 0 confirms. Chapter-shipping figures in this plan: chapter 9 → 33, chapter 10 → 34, chapter 8 → 35, chapter 11 → 36, chapter 12 → 37 (only if it ships a sample), chapter 13 → 38 (only if it ships a sample).
- **Content verification (phase0 §8; spec §7).** Every example is compiled with the seed-built `zig1` and `gcc -m32`, actually run, and its transcript matched to the prose byte-for-byte; every syntax/builtin claim is cross-checked against `docs/reference/Language_Spec_Z98.md` and source.
- **Windows verification — the Win9x oracle on this host (binding).** A Win-target claim is verified on the emitted C89 through the committed `scripts/win32_cross/` harness, **not** by emission alone: `i686-w64-mingw32-gcc` cross-compile (prefer the emitted `build_target.sh mingw` branch, which carries `-lwsock32` iff `std_net` was emitted), run under a dedicated 32-bit wine prefix (`WINEPREFIX=/tmp/wine32 WINEARCH=win32`, initialized once with `wineboot -i`; never touch the operator's wine config), `timeout`-guarded, stdout compared with `scripts/win32_cross/cross_parity.sh`. CRT-path stdout is CRLF under wine, so parity is **LF-normalized** (`PARITY_STRIP_CR=1`) with the raw `stdout.txt` kept as evidence; PAL `WriteFile`-path programs keep strict byte parity. **The emitted OpenWatcom `build_owc.bat`/`wcc386` path is emitted-only on this host — no page may claim it was run.** A Win-only sample the harness cannot run is a **STOP → operator ruling** (drop / prose-with-boundary / a blueprint-permitted Linux shape); a silent compile-only fallback is forbidden. **Inherited wine evidence vs new wine verification.** The coroutine frame/`Context` Win32 layout was verified by the coroutine feasibility plan's ABI oracle (`i686-w64-mingw32-gcc` + wine; `.superpowers/sdd/task-ASYNCPRELUDE-report.md`), and the coroutine-converted `mud_server` multi-connection path is pinned on **Linux** (`examples/z98/mud_server/demo/session.sh` goldens server `66c8f0ab…` / client `93147d0f…`; the two-client scheduler fixture `repro/mi_matrix/stdlib_async_blocking_tick_two_xmod` added by the E4 multi-client fix); coroutine **execution** under wine has no prior record, so Task 0 verifies it. **Measured result (Task 0, 2026-09-30):** the post-`WSAStartup` build **binds under wine** (mud_server server `66c8f0ab…` / client `93147d0f…`), so chapter 12 can ship a `wine-verified` sample; the harness now dumps with `-osw` (operator-ruled fix, see Amendment A0), superseding `cross_net.sh`'s old `10093` assumptions.
- **Chapter shape (spec §4.2).** h1 title; **10–18 pages** of prose; a runnable example with its transcript where the page index gives a sample; a "Common mistakes" subsection wherever the chapter has code; a "Where to go next" cross-reference subsection; the §3 honesty pattern in chapters 2–7; one honesty callout wherever a limit/friction/era alternative is touched. No "Check yourself" (as Volume II).
- **Cross-references (spec §4.3).** Only files that exist may be `<a>`-linked. All Volume II chapters (`vol2-00` … `vol2-20`) and the shipped Reference pages (`vol4-00-title.html`, `vol4-15-builtins.html`, `vol4-24-html-style.html`) are linkable. Planned targets (most of Volume IV, all of Volume V/VI) are named in prose with `(planned)` and no link.
- **Navigation, non-contiguous shipping (spec §4.4).** The sidebar lists all 19 chapters on every shipped Volume III page (shipped = link, unshipped = `<i>(planned)</i>`). `rel` prev/next and the footer point at the **nearest shipped page** in that direction (or `toc.html` at the start). Task 20 restores the continuous chain; the last chapter's `next` is `vol4-00-title.html`.
- **English only.** The language bar carries English plus the "not yet available" plain-text entries, exactly as the existing pages do.
- **Edits via `edit`/`fastedit` only**; no bulk transforms. Never stage `mnemoria/`, `.opencode/`, or `.zig1_*.tmp`.
- **Reference compiler rebuilt per the seed model** (`release/seed/`), seed **v89** (archive md5 `a1549c5b5d9ad23da4d41d214d9ad3c5`; archived binary = fixed point `8216fedc8dd69db084d453be80f3c010`). The seed is rotated **only** by Task 20, and only if a compiler amendment moved the fixed point.
- **Environment deviation (binding for this volume).** `docs/sf/manuals/build.sh` hangs at `rm -rf docs/sf/manuals/dist` (filesystem-level; `dist` is gitignored). **Never run `build.sh` or `serve.sh`; never touch `dist`.** The mechanical gate is the read-only `bash docs/sf/manuals/check.sh`. Regenerate the search index with the `/tmp`-only workaround `/tmp/z98_build_tmp.sh` (writes only `/tmp/z98_search-data.regen.js` and `/tmp/z98_dist_tmp`); the regenerated `en/search-data.js` must byte-match the committed file — copy it over only if it differs, and report if it does.

## Amendment A0 (operator-ruled, 2026-09-30): win32 harness `-osw` fix

The committed `scripts/win32_cross/` harness dumped C89 **without `-osw`**, so mingw compiled the Linux `std_net` branch against the Winsock `net_prelude.h` include and failed (`'close' undeclared`, `XRUNRC=GCCFAIL`) for every `std`-importing entry — caught by Volume III Task 0. Operator ruling (option 2): add `-osw` to the win32 dumps and correct `cross_net.sh`'s superseded `10093`/F6-stub narrative. Scope: `scripts/win32_cross/cross_build_run.sh` + `cross_net.sh` only; no compiler change (fixed point/seed untouched).

- Fix: both scripts' win32 dump now passes `-osw --dump-c89`; `cross_build_run.sh` links `-lwsock32` unconditionally (every `std`-importing entry emits `std_net`); `cross_net.sh`'s pre-`WSAStartup` expectations are marked superseded (its Phase A/B verdict text needs a re-baseline run before use as a gate).
- Verified (2026-09-30, seed `8216fedc…`): `cross_build_run.sh` `XRUNRC=0` on `vol1/hello.z98` (6 `.c`) and `vol2/builtins/async.z98` (7 `.c`); full `cross_parity.sh` on the coroutine sample → `XRUNRC=0` / `WINE_RC=0` / `PARITY=OK` (Linux `frame=88` / `n=3 steps=4`); Task 0's `mud_server` client session parity OK.

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

Capture stdout, stderr, and `rc` as the transcript. Every binary runs under `timeout 120`.

### Windows verification recipe (for Win9x claims)

First capture the linux baseline, then cross-build + wine-run the same entry through the harness (`entry` is repo-relative because module resolution is CWD-relative):

```bash
# 1. linux baseline (the parity target)
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out docs/sf/manuals/src/vol3/<prog>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog> > /tmp/manual_win/<prog>.linuxstdout

# 2. one-time: dedicated 32-bit wine prefix (never touch the operator's wine config)
export WINEPREFIX=/tmp/wine32 WINEARCH=win32 && wineboot -i

# 3. cross-build + wine run + LF-normalized parity
ZIG1=/tmp/manual_seed/zig1_5_clean CROSS_EXTRA_LIBS="" PARITY_STRIP_CR=1 \
WINEPREFIX=/tmp/wine32 WINEARCH=win32 \
  bash scripts/win32_cross/cross_parity.sh \
  docs/sf/manuals/src/vol3/<prog>.z98 /dev/null \
  /tmp/manual_win/<prog>.linuxstdout /tmp/manual_win/<prog>
# verdict lines: XRUNRC=0, WINE_RC=0, PARITY=OK (raw stdout.txt kept as evidence)

# build-only form (when only the cross-link is at stake):
bash scripts/win32_cross/cross_build_run.sh /tmp/manual_seed/zig1_5_clean \
  docs/sf/manuals/src/vol3/<prog>.z98 /tmp/manual_win/build /tmp/manual_win/<prog>.exe
```

`CROSS_EXTRA_LIBS="-lwsock32"` only when the entry's program emits `std_net` and the emitted `build_target.sh mingw` branch does not already carry it. The harness now dumps with `-osw` and links `-lwsock32` (Amendment A0); `cross_net.sh` still carries pre-`WSAStartup` verdict text and must be re-baselined before use as a gate. If the emitted script's argument order or default name differs, use `docs/sf/QUICK_REF.md` verbatim. Record the wine version, the exact command, and whether the parity compare was LF-normalized (CRT-path programs) in the task report and, where it matters, on the page.

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
2. **Verify feasibility first (STOP if it fails)** where the chapter depends on an API/behavior/toolchain that may not exist (coroutines, `std.net`, Win32 APIs, `-osw`); report to the operator instead of inventing it. A Win-only sample must clear the "Windows verification recipe" (the harness) before it is authored; `wine-cannot` is a STOP and an operator ruling, never a compile-only fallback.
3. **Author the example(s)** under `src/vol3/`, compile+run with the seed compiler, and capture the exact transcript; for a Win-only sample, capture the harness verdict (cross-build + wine run + LF-normalized parity) per the "Windows verification recipe".
4. **Write the page** from the `vol4-24-html-style.html` skeleton — sidebar (all 19 Volume III chapters, shipped ones linked, unshipped `(planned)`), language bar, `rel` home/up/prev/next (nearest shipped), 10–18 pages of prose per the chapter's "Must cover" list, the runnable example(s) with transcripts in `<pre>`, the §3 honesty pattern for chapters 2–7, "Common mistakes" wherever there is code, "Where to go next" (existing pages only), one honesty callout where warranted, and the Win9x note where the chapter ships a program (the note states exactly what was verified here — mingw cross-build + wine run with LF-normalized parity — and that the OpenWatcom `build_owc.bat`/`wcc386` script is emitted, not run on this host; the real-machine screenshot stays the figure placeholder).
5. **Cross-check every claim** against `docs/reference/Language_Spec_Z98.md`, the compiler source, and the actual toolchain.
6. **Figures:** add the placeholder box and the matching `todo-figures-list.html` row (1:1) using the chapter's figure number (task table above).
7. **Wire the chapter:** flip this chapter's sidebar entry from `(planned)` to a link on every shipped `en/vol3-*.html` page, in `en/toc.html`, and in `en/vol3-00-title.html` if it exists; set the new page's `rel`/footer prev/next to its nearest shipped neighbors and update those neighbors' `rel`/footer; link the chapter from `en/index.html`/`readme.html` where the volume index lists chapters.
8. **Verify:** `bash docs/sf/manuals/check.sh` passes; regenerate the search index with `/tmp/z98_build_tmp.sh` and confirm it byte-matches the committed `en/search-data.js` (copy + report if it differs). Do NOT run `build.sh`.
9. **Commit:** `git add docs/sf/manuals && git commit -m "docs(manual): add Volume III chapter NN — <title>"`.

---

### Task 0: Delta inventory + claim-scope ruling (read-only)

**Files:**
- Read-only: `.superpowers/sdd/2026-09-25-z98-manual-volume-II-plan/task-0-report.md` and the Volume II spec §10 (the inherited baseline), `sf/src/**` (as needed), `docs/reference/Language_Spec_Z98.md`, `docs/reference/builtins.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `scripts/win32_cross/**` (the commit-time harness), `docs/sf/manuals/**`.
- Create (untracked): `.superpowers/sdd/2026-09-30-z98-manual-volume-III-plan/task-0-report.md`.
- No `sf/src` edits, no commit.

**Interfaces:**
- Consumes: the spec's chapter contracts (§2.2), the ruled phase0 §3 corrections (§2.1), the open items (§9), and the Volume II baseline (its Task 0 report + closeout §10).
- Produces: the **delta matrix** the chapter tasks rely on — for each chapter 0–18, every "Must cover" claim classified as **inherited-verified** (cite the Volume II report line/commit), **new-verified** (probe here), **new-corrected**, **defect → amendment**, **wine-verified / wine-parity-CRLF / wine-cannot (specific gap)**, **compile-only (specific reason)**, **prose/era-opinion (marked)**, or **cannot-verify-here (why)**; the coroutine API + frame ABI; the Win9x build path proven end-to-end under wine; the `std.net` surface and the wine winsock gap; which of chapters 12/13 can ship a real sample (and in which wine class); the next free figure number; and the predicted compiler I/F pairs.

**Don't-list (do not re-measure).** This is a *delta* inventory, not a re-run of the Volume II capability matrix. Do NOT re-derive the language surface already shipped and verified in Volume II (types, pointers, aggregates, arrays/slices, control flow, `defer`, error unions, optionals, arena, builtins, `print`, the stdlib tour, enums/unions/tuples), the 4-MD5/corpus/stdlib gates, self-emission, or the closed parity residuals. Cite them as inherited-verified.

- [ ] **Step 1: Build the compiler** per "Compiler under test" and record its md5 (`md5sum /tmp/manual_seed/zig1_5_clean`).
- [ ] **Step 2: Prove the Windows path end-to-end (STOP if it fails).** Initialize `/tmp/wine32` (`wineboot -i`); run the harness on a manual example (e.g. `docs/sf/manuals/src/vol1/hello.z98` or `vol2/arena.z98`) per the "Windows verification recipe"; record `wine --version`, the exact command, `XRUNRC`/`WINE_RC`/`PARITY`, and whether the compare was LF-normalized. Also run one **coroutine** sample (`docs/sf/manuals/src/vol2/builtins/async.z98` — `@asyncInit`/`@asyncResume`/`@asyncSuspend`/`@asyncFrameSize`, no sockets) and one **`mud_server` + client** session (`examples/z98/mud_server` with `demo/session.sh`) through the same harness: the coroutine run closes the "no coroutine program recorded under wine" gap; the `mud_server` run measures whether the post-`WSAStartup` build binds under wine or still returns `10093` (see Steps 3–4 and §9). If wine or the mingw toolchain is missing/broken, STOP and report before any Win chapter.
- [ ] **Step 3: Build the delta matrix.** For each of the 7 new surfaces — (a) coroutines as a programming model (ch9/10) — cite the inherited Win32 ABI-oracle wine run for the frame/`Context` layout (`.superpowers/sdd/task-ASYNCPRELUDE-report.md`: `i686-w64-mingw32-gcc` + wine rc=0 struct-layout match) and the inherited **Linux** multi-connection evidence (`examples/z98/mud_server/demo/session.sh` goldens `66c8f0ab…`/`93147d0f…`; the two-client `repro/mi_matrix/stdlib_async_blocking_tick_two_xmod` fixture that pinned the E4 multi-client fix); record that coroutine **execution** under wine is not previously recorded, so any Win coroutine claim is new-verified via the Step-2 sample — (b) the Win9x build workflow and scripts (ch8), (c) the C-interop contract (ch11), (d) the `std.net` socket surface + the wine winsock gap (ch12), (e) the Win32 debug-API expressibility (ch13), (f) the C89/C++98/asm mixing proofs (ch3/4/5), (g) the gdb/`--markers` and `--track-memory`/`-mm0`/tiers user claims (ch15/16) — probe and classify every claim in spec §2.2 using the vocabulary above. Record the probe command and output for each new-verified claim; for each inherited claim cite the Volume II source.
- [ ] **Step 4: Apply and verify the phase0 §3 corrections** — confirm `.z98dbg` absence, the socket-builtin removal, the current Win9x target (bootstrap `platform_win98.h`/`_MBCS` are gone; `WINVER 0x0410` IS emitted for `@console*` modules), and DirectX-header absence; record the exact replacement wording each chapter uses. Probe ch12/13/14 under wine to fix each chapter's class (ch12: **measure** the bind — the post-`WSAStartup` build may bind under wine, so `wine-verified` is possible; otherwise `wine-cannot` with the control probe; ch13/ch14 to be measured).
- [ ] **Step 5: Inventory the residuals** — read `repro/mi_matrix/EXPECTED_FAIL.md` and the Volume II closeout (its spec §10); for each residual touching a Volume III topic, note whether a chapter's "Must cover" item depends on it.
- [ ] **Step 6: Confirm the figure numbering** — the highest used figure number in `todo-figures-list.html` (expected 32; next free 33) and the per-chapter assignment in Global Constraints; adjust the assignment if a Win sample drops to prose-only per Step 4.
- [ ] **Step 7: Predict the compiler I/F pairs** — the claims most likely to fail (highest risk first: coroutines, `std.net`, the Win32 debug API, `-osw`), with the probe evidence.
- [ ] **Step 8: Write the report** to the workspace path above and return a summary. No commit.

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

- [ ] **Step 1: Verify feasibility (STOP if it fails)** — the blueprint's "one coroutine per connection / line echo server" needs a working transport. Task 0 fixes the class: if the harness proves the network path wine-runnable, use it; if it is `wine-cannot` (the known winsock 10093 gap), use the blueprint-permitted **cooperative task demo with N tasks suspending in a known order**. Report which shape and why.
- [ ] **Step 2: Author `echo.z98`** — the chosen shape; compile+run on Linux and capture the transcript; if the network shape is chosen, also capture the harness verdict (cross-build + wine + LF-normalized parity; `CROSS_EXTRA_LIBS="-lwsock32"` iff `std_net` is emitted and the emitted branch does not already carry it).
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

- [ ] **Step 1: Verify the build path first (STOP if it fails)** — run the "Windows verification recipe" harness end-to-end on `hello.z98` (cross-build with `i686-w64-mingw32-gcc`, wine run under `/tmp/wine32`, LF-normalized parity); inspect the emitted `build_target.bat`/`build_owc.bat`; record the exact commands and the `build_target.sh mingw` branch flags. Confirm the Phase 0 §3 rewrite for this chapter: the bootstrap `platform_win98.h` and `_MBCS` are gone and the emitted `ZIG_WIN32` guard is current, but `WINVER 0x0410` **is** emitted (with `_WIN32_WINDOWS`/`_WIN32_WINNT`/`NTDDI_VERSION`/`WIN32_LEAN_AND_MEAN` + `<windows.h>`) for `@console*`-using modules (`sf/src/c89_emit.zig:2816`) — state the measured reality. The OpenWatcom script is emitted-only — the page must not claim it was run here.
- [ ] **Step 2: Author `hello.z98`** — the Win9x walkthrough program (from Volume I's hello, adapted); capture both transcripts: the Linux run and the harness (cross-build + wine + parity).
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

- [ ] **Step 1: Verify the `std.net` surface first (STOP/report if the blueprint's API does not exist)** — enumerate the actual `sf/src/std_net.zig` extern surface; confirm the `WSAStartup`/`socket`/`bind`/`listen`/`accept`/`recv`/`send`/`select`/`closesocket` shapes and the `SOCKET` unsigned-comparison rule; confirm `fd_set` is an opaque blob. Then run the harness on a net entry and record its verdict, including the expected wine limitation (`socket()`/bind fails with `WSANOTINITIALISED`, 10093).
- [ ] **Step 2: Rule the sample (operator)** — if the harness proves the Win-only `http-mini.z98` path wine-runnable, author it and take the parity transcript; if it is `wine-cannot` (the 10093 gap), ship the chapter with the harness's wine-side control-probe evidence (the socket surface it *can* demonstrate) and defer the live bind/serve to the real-Win9x figure, stating the boundary on the page. A compile-only fallback still needs the operator ruling.
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

- [ ] **Step 1: Verify expressibility first (STOP/report if it fails)** — can the compiler express the required `extern` surface (`CreateProcess`, `WaitForDebugEvent`, `ContinueDebugEvent`, `GetThreadContext`, `ReadProcessMemory`, `WriteProcessMemory`, `INT3` patching, `_MEMORY_BASIC_INFORMATION`)? Cross-build a `dbg-mini` probe through the harness and attempt a wine run (and `winedbg` where useful); record the class (`wine-verified` / `wine-parity-CRLF` / `wine-cannot` with the exact failure).
- [ ] **Step 2: Rule the sample** — a `wine`-verified `dbg-mini.z98`, or (if `wine-cannot`) prose + compile-only excerpts with the specific reason and no figure, pending the operator's ruling.
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

- [ ] **Step 1: Verify what prose is defensible** — confirm no DirectX headers/example exist in the repo (phase0 §3) and record that the DirectDraw/DirectSound paths are **wine-untestable here** (the era-OS graphics/sound stack is not a wine capability we rely on); keep era-context statements only where verifiable (to the extent the declared target/COM-in-C89 facts are checkable), mark opinion, and state the boundary on the page.
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

- [ ] **Step 1: Verify what reproduces** — the release shape (`build_owc.bat` convention — **emitted, not run on this host**, what goes on the diskette, self-extracting archives) only to the extent the repo's scripts and Task 0 support it; mark opinion; never generate `dist/`.
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

- [ ] **Step 1: Re-run every example** — all `docs/sf/manuals/src/vol3/*.z98` compile+run on the current seed; each page transcript matches byte-for-byte; every Win-only sample re-runs through the "Windows verification recipe" harness (cross-build + wine + LF-normalized parity).
- [ ] **Step 2: Navigation continuity** — no shipped Volume III chapter carries `(planned)` in its own row; the `rel` chain is continuous `toc.html → vol3-00 → … → vol3-18 → vol4-00-title.html`; every sidebar lists 19 chapters; `vol2-20-whats-next.html` and any other page naming Volume III as `(planned)` links the title page.
- [ ] **Step 3: Figure audit** — `todo-figures-list.html` is 1:1 with on-page placeholders, numbers unique, no gaps.
- [ ] **Step 4: Gates** — `bash docs/sf/manuals/check.sh` passes; the `/tmp` index regeneration byte-matches the committed `en/search-data.js` idempotently. Do NOT run `build.sh`.
- [ ] **Step 5: Spec status** — set the Volume III spec's status to **Implemented** and record the closeout (rulings, seed rotation, residuals, environment deviation).
- [ ] **Step 6: Seed rotation (iff an amendment moved the fixed point)** — `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`; verify the post-rotation two-hop closure; update the QUICK_REF "Current seed" block.
- [ ] **Step 7: Whole-set review + Windows-claim audit** — no shipped Volume III page asserts an OpenWatcom run or a Win9x run the harness did not perform; every Win9x note names what was verified (mingw+wine, LF-normalized) and what is the figure's job. Also qualify any already-shipped Volume I/II sentence that states `wcc386`/`build_owc.bat` ran without evidence (docs-only; touching pages outside Volume III needs an operator ruling). Then dispatch the final whole-branch review over the Volume III range; fix or park per the loop.
- [ ] **Step 8: Commit** `docs(manual): Volume III closeout — whole-set review and verification sweep`.

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: §2.2's 19 chapters → Tasks 1–19 (order in §2.3: ch2, ch3–7, ch9–10, then 0/1/8/11–18); §3 tone rules are Global Constraints and are re-read by every honesty task; §4 page shape/figures/nav are the shared 9-step shape; §5/§6 the defect policy and amendment protocol; §7 verification is step 8 plus Task 20; §8 is Task 0; §9 open items are Task 0's steps 2–6.

**Placeholder scan.** No `TBD`/`TODO`; the two genuinely Task-0-dependent samples (ch12, ch13) are written as explicit conditional branches with the ruling recorded in the task, not left vague. The ch10 sample has the blueprint's own permitted alternative (cooperative task demo) written in as the fallback.

**Consistency.** Chapter numbers, page filenames, sample names, task numbers, and figure numbers are consistent between the spec's §2.1 table and this plan's task headers (Task 1 = ch2 … Task 19 = ch18; Task 20 closeout; figures 33–38). The evidence vocabulary (seed v89 fixed point `8216fedc…`, `check.sh`, the `/tmp` index workaround, the `scripts/win32_cross/` harness + 32-bit wine prefix + LF-normalized parity) is identical throughout.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-30-z98-manual-volume-III-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?

---

## Deferred compiler I/F — `anytype` call-path reject (parked; run after all writing)

The `anytype` call-path segfault observed during Task 1 (seed v89: `fn show(x: anytype) void { _ = x; }` + `show(5)` → rc 139) is **parked**, consistent with the earlier deferral in `docs/superpowers/plans/2026-08-06-compiler-gaps-plan.md` (AMENDMENT 5: "`anytype` (comptime-generic) support remains a separate future feature"). `anytype` is designed-unsupported (`sf/src/analyzer.zig:458` `ERR_2012_ANYTYPE_NOT_SUPPORTED`; `sf/src/parser.zig:1130` makes `parserParseType` return node 0 for `anytype`, so that check and the FX13-F signature walk skip it today).

- **Writing-phase rule:** no Volume III chapter may call an `anytype` function — a call crashes today and is expected to be rejected once the reject path is fixed. Chapters may state that `anytype`/generics are unsupported.
- **The scoped I/F that implements the clean reject is appended and executed AFTER all Volume III writing is complete (after Task 20)**, by operator ruling (2026-09-30): an **I** task to root-cause the parser-returns-0 / analyzer-dead-check path, then an **F** task delivering a clean level-0 reject (`error[16]`/`error[20]`) with a `repro/mi_matrix/` fixture, a standalone repro, and the standard gate battery. Seed rotation stays closeout-only; if this I/F lands after Task 20 it carries its own subsequent closeout rotation.
