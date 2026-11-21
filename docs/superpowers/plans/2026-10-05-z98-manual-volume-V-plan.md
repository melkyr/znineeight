# Z98 Manual — Volume V (HOWTO) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Author the 24 task-oriented HOWTO guides of Volume V under `docs/sf/manuals/en/vol5-*.html`, each a step-by-step procedure with exact commands and measured output, **reusing** the existing `repro/mi_matrix/`, `examples/z98/`, shipped `src/vol*` samples, and repo scripts rather than creating new material — every guide gated by `check.sh` and the search-index byte-match.

**Architecture:** One plan: a read-only coverage inventory (Task 0), 24 guide tasks in a **foundational-first** order, and a whole-set closeout (Task 25). Each guide task maps its steps to existing verified artifacts, writes the page from the shipped skeleton, wires navigation, gates, and commits. Website-only **except** operator-ruled scoped compiler I/F amendments.

**Tech Stack:** Hand-authored HTML 4.0 Transitional, CSS1, 1998-era vanilla JavaScript (`doc.js`), GIF assets, Python 3 (`check.py`), the seed-built `zig1` + `gcc -m32`, and the committed `scripts/win32_cross/` harness (`i686-w64-mingw32-gcc` + 32-bit `wine`) for Win9x guides, git.

**Spec:** `docs/superpowers/specs/2026-10-05-z98-manual-volume-V-design.md` (binding for this plan). Program-level spec: `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md`. Blueprint: `docs/sf/manuals/manuals_blueprint.txt` Part 6 (lines 237–266). Prior-volume mechanics/register: `docs/superpowers/specs/2026-10-03-z98-manual-volume-IV-design.md`.

**Sequence:** PREVIOUS = `docs/superpowers/plans/2026-10-03-z98-manual-volume-IV-plan.md` (Volume IV, COMPLETE; seed rotated v90 → v91). NEXT = the Volume VI (Internals) plan.

**Compiler amendments:** appended to this plan only by **operator ruling**, as an I/F pair — Task Na (I) read-only investigation; Task Nb (F) fix with a `repro/mi_matrix/` fixture + a standalone `repro/` program + the QUICK_REF gate battery verbatim (STOP on unexpected movement) + tech-doc updates + a two-hop closure with the moved fixed point recorded + a commit. Amendment tasks are the ONLY tasks permitted to touch `sf/src`, `scripts/`, `repro/`, or `release/seed/`. **Seed rotation is closeout-only:** rotated once at Task 25 iff an amendment moved the fixed point.

## Global Constraints

- **Website only, with scoped exceptions (spec §6).** Do NOT edit `sf/src/**`, `scripts/**`, `repro/**`, or `release/seed/**` — EXCEPT tasks inserted by an operator-ruled amendment. Every other task leaves the compiler fixed point and the seed untouched.
- **STOP on a real compiler defect** found while verifying a step — report the minimal reproduction; do not fix `sf/src`, do not document around it, do not re-scope the guide (phase0 §9/§11). Compiler correctness takes priority.
- **Reuse-first (spec §4, binding operator ruling).** The how-to corpus already exists. Map every guide step to an existing `repro/mi_matrix/**` fixture, `examples/z98/**`, shipped `docs/sf/manuals/src/vol1-3/**` sample, or repo script; cite it and its measured output. **Create new code only when Task 0 finds nothing reuseable** (new samples go under `docs/sf/manuals/src/vol5/`). Do NOT re-create or re-test an artifact that already exists in a script or document unless it is suspicious or contradictory. No arbitrary "slop" examples.
- **Guide shape (spec §3).** h1 + one-line goal; prerequisites; numbered steps with exact commands; a **Verify it worked** step showing the real captured output (reused measured transcript); "Common mistakes" wherever a step ships code; "Where to go next" (adjacent guide + Volume IV Reference). Neutral, task-focused; no Volume II/III honesty framing.
- **Blueprint-vs-reality (spec §5).** `vol5-13-debugger` is **gdb on the generated C only** (`.z98dbg` does not exist). `vol5-21-static-site` documents `check.sh` + `/tmp/z98_build_tmp.sh` (never `build.sh`/`serve.sh`). `vol5-20-build-multilingual` describes one-language builds from the template (translations `(planned)`). `vol5-19-pack-for-diskette` is a documented tar/zip recipe (`dist/` gitignored). Never ship an unreproducible claim.
- **All content files under `docs/sf/manuals/`** except this plan and its spec.
- **HTML restrictions (phase0 §6.1).** HTML 4.0 Transitional in the HTML 3.2/4.0 intersection. No HTML5 structural tags; no `<div>` (layout via `<table>`); ISO-8859-1 meta; every page carries `<link rel="home|up|prev|next">`, a 25-row sidebar TOC (index + 23 guides), a language bar, and a prev/contents/next footer.
- **CSS/JS/asset/forbidden (phase0 §6.2–§6.5).** CSS1 external only (`z98.css`/`z98-print.css`); no inline `<style>`; one `doc.js` ≤ 2048 bytes, four functions; GIF only; the checker's forbidden list.
- **Figures (spec §5).** No figures except deferred Win9x screenshot placeholders for `vol5-04`/`vol5-10`/`vol5-19`, numbered from **39** (Task 0 confirms the baseline; Volume IV used 1–38). Other Win9x steps are verified through the `scripts/win32_cross/` harness.
- **Navigation (spec §12).** Sidebar lists all 25 Volume V entries (shipped = link, unshipped = `<i>(planned)</i>`); `rel`/footer point at the nearest shipped entry; the final page's `next` is `toc.html` until Volume VI exists; Task 25 restores the continuous chain.
- **Cross-references.** Only existing files may be `<a>`-linked (Volume I–IV pages, `docs/reference/*.md`, existing `vol5-*`); planned volumes/translations are prose `(planned)`.
- **English only.** The language bar carries English plus the "not yet available" plain-text entries, as existing pages do.
- **Environment deviation (binding).** `docs/sf/manuals/build.sh` HANGS at `rm -rf docs/sf/manuals/dist`. **Never run `build.sh` or `serve.sh`; never touch `dist`.** Gate with `bash docs/sf/manuals/check.sh`; regenerate the search index with `/tmp/z98_build_tmp.sh` (writes only `/tmp/z98_search-data.regen.js` + `/tmp/z98_dist_tmp`) and require a byte-match to `en/search-data.js` (copy over only if it differs, and report).
- **Edits via `edit`/`fastedit` only**; no bulk transforms. Never stage `mnemoria/`, `.opencode/`, or `.zig1_*.tmp`.
- **Seed model (binding).** Reference compiler rebuilt per `release/seed/`, seed **v91** (archive md5 `39669954c928df59263e5d03cbaacd1d`; archived binary = fixed point `0b8c3e4ac0b1fc49c0bdf8caf9d39945`). Rotated only by Task 25, only if an amendment moved the fixed point.

## Compiler under test

```bash
FIXED_POINT_MD5=0b8c3e4ac0b1fc49c0bdf8caf9d39945 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/manual_seed
# gate: === [seed] Done: /tmp/manual_seed ===
# result: /tmp/manual_seed/zig1_5_clean  +  /tmp/manual_seed/lib/
```

Every binary runs under `timeout 120`. Compile/run a step's program:

```bash
/tmp/manual_seed/zig1_5_clean -o /tmp/manual_out <file>.z98
cd /tmp/manual_out && timeout 120 sh build_target.sh linux <prog>
```

For a Win9x step, use the committed `scripts/win32_cross/` harness (mingw cross-compile + 32-bit `wine` run + LF-normalized parity); the emitted OpenWatcom `build_owc.bat`/`wcc386` path is emitted-only on this host.

### How each guide task works (shared steps)

Each guide task repeats this shape; its own block lists Files / Consumes / Must cover:

1. **Read** the guide's Task-0 reuse inventory entry (which existing artifacts satisfy its steps) and the relevant Volume IV Reference page(s).
2. **Confirm** each step against the seed compiler **or** reuse the recorded measured output of the cited artifact; only if a step is uncovered, write the minimal new sample under `docs/sf/manuals/src/vol5/` and measure it.
3. **Write** `docs/sf/manuals/en/<file>.html` — the guide shape (§3): goal, prerequisites, numbered steps, Verify-it-worked transcript, Common mistakes (if code), Where to go next.
4. **Cross-check** links (existing targets only) and the sidebar/`rel`/language-bar/footer.
5. **Wire** the page: make its sidebar row a link (unbolded on siblings), add it to `en/toc.html` Volume V section and `en/vol5-00-index.html`, and re-point the nearest shipped neighbours' `rel`/footer.
6. **Gate**: `bash docs/sf/manuals/check.sh` green; regenerate the index with `/tmp/z98_build_tmp.sh` and confirm byte-match.
7. **Commit**: `docs(manual): add Volume V guide NN — <title>`.

---

### Task 0: Coverage inventory (read-only)

**Files:**
- Read-only: `repro/mi_matrix/**`, `examples/z98/**`, `docs/sf/manuals/src/vol1/**`+`vol2/**`+`vol3/**`, `scripts/**`, `docs/sf/QUICK_REF.md`, `docs/reference/*.md`, the shipped `en/vol1-4*` pages, `en/toc.html`.
- Create (untracked): `.superpowers/sdd/2026-10-05-z98-manual-volume-V-plan/task-0-report.md`.
- No `sf/src` edits, no commit.

**Consumes:** the spec's guide index (§2), guide shape (§3), reuse-first rule (§4), blueprint corrections (§5), open items (§9).
**Produces:** for each of the 24 guides, a **coverage table**: every step → the existing artifact that satisfies it (with its path and measured output) or `net-new`; plus the figure-numbering baseline, the predicted compiler I/F pairs, and any remaining blueprint-vs-reality gap.

- [ ] **Step 1: Build the compiler** per "Compiler under test" and record its md5 (`md5sum /tmp/manual_seed/zig1_5_clean`).
- [ ] **Step 2: Inventory the corpus.** List `repro/mi_matrix/` dirs with goldens, `examples/z98/` programs, `src/vol1-3` samples, and the repo scripts; index them by topic (build, targets, arena, errors, coroutines, files, sockets, interop, debug, markers, diagnostics, packaging, site).
- [ ] **Step 3: Map each guide's steps.** For guides 01–23, map every step to a corpus artifact or mark it `net-new`; note the exact commands and reused transcripts. For the meta guides (13, 19, 20, 21, 22, 23) record the repo reality each step must describe.
- [ ] **Step 4: Confirm the blueprint-vs-reality corrections** (spec §5) and record the replacement wording (esp. `.z98dbg` dropped in guide 13; the `dist`-hang workaround in guide 21).
- [ ] **Step 5: Figure baseline + I/F prediction.** Confirm the next free figure number (expected 39) for `vol5-04`/`vol5-10`/`vol5-19`; list the highest-risk compiler I/F pairs.
- [ ] **Step 6: Write the report** and return a summary. No commit.

---

### Task 1: Guide 00 — Index

**Files:** Create `docs/sf/manuals/en/vol5-00-index.html`; modify `en/toc.html`.
**Consumes:** Task 0 report; the spec §2 index.
**Must cover:** every guide A–Z and grouped by theme (build & run, language practices, interop & porting, targets, tooling, distribution & meta), each linking its page (unshipped = `(planned)`), plus a one-line description.
- [ ] Steps 1–7 (shared). **Commit:** `docs(manual): add Volume V guide 00 — index`.

---

### Task 2: Guide 01 — Rebuild `zig1` from seed

**Files:** Create `docs/sf/manuals/en/vol5-01-build-compiler.html`; wire.
**Consumes:** Task 0 (the seed-build script/recipe); `docs/sf/QUICK_REF.md` seed section.
**Must cover:** the two-hop seed build (`scripts/seed/build_from_seed.sh`), the `FIXED_POINT_MD5` gate, where the built binary and `lib/` land, and verifying the closure.
- [ ] Steps 1–7 (shared; reuse the QUICK_REF recipe verbatim). **Commit:** `docs(manual): add Volume V guide 01 — rebuild zig1 from seed`.

---

### Task 3: Guide 02 — One `.z98` to an executable

**Files:** Create `docs/sf/manuals/en/vol5-02-build-single.html`; wire.
**Consumes:** Task 0 (a single-file shipped sample, e.g. `src/vol1/hello.z98`/`src/vol2/*`).
**Must cover:** `zig1 -o <dir> prog.z98`, `build_target.sh linux`, running the executable, and the `-osw` variant pointer.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 02 — build a single-file program`.

---

### Task 4: Guide 03 — Multiple modules

**Files:** Create `docs/sf/manuals/en/vol5-03-build-multi.html`; wire.
**Consumes:** Task 0 (a `*_xmod` multi-module fixture and its goldens).
**Must cover:** `@import`, module resolution, the emitted per-module files and shared header, and building/linking the multi-module program.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 03 — build a multi-module program`.

---

### Task 5: Guide 06 — Correct arena use

**Files:** Create `docs/sf/manuals/en/vol5-06-arena.html`; wire.
**Consumes:** Task 0 (`src/vol2/arena.z98`, `repro/mi_matrix` arena fixtures, `sf/src/std_arena.zig`).
**Must cover:** arena init over a backing buffer, `alloc`, `reset`, the dual-arena pattern, and when a lifetime must outlive a reset.
- [ ] Steps 1–7 (reuse the arena sample/transcript). **Commit:** `docs(manual): add Volume V guide 06 — use the arena`.

---

### Task 6: Guide 07 — Model and propagate errors

**Files:** Create `docs/sf/manuals/en/vol5-07-errors.html`; wire.
**Consumes:** Task 0 (error-union fixtures, `src/vol2/error_unions.z98`).
**Must cover:** error sets, `try`/`catch`, `errdefer`, propagation, and the enclosing-return rule (reference Volume IV page 09).
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 07 — model and propagate errors`.

---

### Task 7: Guide 08 — Write and drive a coroutine

**Files:** Create `docs/sf/manuals/en/vol5-08-coroutines.html`; wire.
**Consumes:** Task 0 (`src/vol2/builtins/async.z98`, `src/vol3` coroutine samples, `repro/mi_matrix` async fixtures, `std.async`).
**Must cover:** `@asyncInit`/`@asyncSuspend`/`@asyncResume`/`@asyncFrameSize`, the `Context`/`Task`/`Scheduler` driver, and the 8-align frame rule.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 08 — write and drive a coroutine`.

---

### Task 8: Guide 09 — Files

**Files:** Create `docs/sf/manuals/en/vol5-09-files.html`; wire.
**Consumes:** Task 0 (`sf/src/std_io.zig`, file fixtures, `src/vol3` file usage if any).
**Must cover:** read, write, and exists via the std IO surface and the PAL, with the returned-error checks.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 09 — read, write, and check files`.

---

### Task 9: Guide 11 — C interop

**Files:** Create `docs/sf/manuals/en/vol5-11-c-interop.html`; wire.
**Consumes:** Task 0 (`examples/z98` extern usage, `repro/mi_matrix` c-interop fixtures, Volume IV page 11).
**Must cover:** `extern fn`, `@cInclude` (module-level only), calling conventions, and struct-by-value ABI.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 11 — call C from Z98`.

---

### Task 10: Guide 12 — C89 interop

**Files:** Create `docs/sf/manuals/en/vol5-12-c89-interop.html`; wire.
**Consumes:** Task 0 (the emitted C89 workflow, a hand-C89 link fixture).
**Must cover:** linking a Z98-emitted object with a hand-written C89 object, naming/mangling, and the build-script recipe.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 12 — link against C89`.

---

### Task 11: Guide 16 — Port from C

**Files:** Create `docs/sf/manuals/en/vol5-16-port-from-c.html`; wire.
**Consumes:** Task 0 (a C↔Z98 pairing used in Volume II/III; e.g. the ch1 C89 fragment vs its Z98 twin).
**Must cover:** an idiom-by-idiom translation checklist (types, arrays→slices, errors, cleanup→defer, ownership→arena) and the verification steps.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 16 — port a C file`.

---

### Task 12: Guide 17 — Port from C++98

**Files:** Create `docs/sf/manuals/en/vol5-17-port-from-cpp.html`; wire.
**Consumes:** Task 0 (Volume II ch4 C++98 material and Volume III guides 4).
**Must cover:** what translates (templates→manual/concrete, RAII→defer, exceptions→error unions) and what honestly does not, with the Z98 alternative for each.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 17 — port a C++98 file`.

---

### Task 13: Guide 18 — Port from Python

**Files:** Create `docs/sf/manuals/en/vol5-18-port-from-python.html`; wire.
**Consumes:** Task 0 (a small dynamic-language program mapped onto a Z98 sample).
**Must cover:** dynamic typing→static, dicts/lists→manual structures/slices, exceptions→error unions, GC→arena; what a Python reader will miss.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 18 — port from Python`.

---

### Task 14: Guide 04 — Win9x `.exe`

**Files:** Create `docs/sf/manuals/en/vol5-04-target-win9x.html`; wire; add figure 39 placeholder + `todo-figures-list.html` row.
**Consumes:** Task 0 (the `-osw` recipe, `scripts/win32_cross/`, Volume III ch8).
**Must cover:** emitting with `-osw`, the emitted build scripts (`build_target.bat`, `build_owc.bat` emitted-only), the mingw+wine verification path, and the real-machine note.
- [ ] Steps 1–7 (Win steps via the harness). **Commit:** `docs(manual): add Volume V guide 04 — target Win9x`.

---

### Task 15: Guide 05 — Linux ELF

**Files:** Create `docs/sf/manuals/en/vol5-05-target-linux.html`; wire.
**Consumes:** Task 0 (the default linux `build_target.sh` path).
**Must cover:** the default target, `gcc -m32`, the emitted build script, and how to choose the target.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 05 — target Linux`.

---

### Task 16: Guide 10 — Sockets (WinSock)

**Files:** Create `docs/sf/manuals/en/vol5-10-sockets.html`; wire; add figure 40 placeholder + row.
**Consumes:** Task 0 (`sf/src/std_net.zig`, `examples/z98/mud_server`, `scripts/win32_cross/cross_net.sh`, Volume IV page 12).
**Must cover:** the `std.net` extern surface, `WSAStartup`, socket lifecycle, the `-lwsock32` link, and the measured wine bind class.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 10 — use sockets`.

---

### Task 17: Guide 13 — Debugger

**Files:** Create `docs/sf/manuals/en/vol5-13-debugger.html`; wire.
**Consumes:** Task 0 (the gdb-on-generated-C recipe; Volume IV page 15; Volume III ch15).
**Must cover:** building with debug info, the `cd DIR` + absolute `-I` gotchas, gdb on the emitted `.c`, and reading `--markers`. **`.z98dbg` is dropped** (gdb-only).
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 13 — debug the generated C`.

---

### Task 18: Guide 14 — Markers

**Files:** Create `docs/sf/manuals/en/vol5-14-markers.html`; wire.
**Consumes:** Task 0 (`--markers` on a shipped sample; `sf/src/pal.zig` marker API; Volume IV page 20).
**Must cover:** enabling `--markers`, `pal.markerWrite*`, and reading the marker stream.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 14 — trace with markers`.

---

### Task 19: Guide 15 — Diagnostics

**Files:** Create `docs/sf/manuals/en/vol5-15-diagnostics.html`; wire.
**Consumes:** Task 0 (representative rejects from `repro/mi_matrix`; Volume IV page 21).
**Must cover:** how to read `error[N]`/`warning[N]` (the printed ordinal vs the `ERR_####` name), the source/target notes, and a handful of common codes and fixes.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 15 — read the diagnostics`.

---

### Task 20: Guide 19 — Pack for diskette

**Files:** Create `docs/sf/manuals/en/vol5-19-pack-for-diskette.html`; wire; add figure 41 placeholder + row.
**Consumes:** Task 0 (the self-contained `-osw` output tree, `docs/sf/manuals/src/build_owc.bat`).
**Must cover:** assembling the distributable directory, the tar/zip diskette-image recipe, and what the archive contains. `dist/` stays gitignored; no image committed.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 19 — pack for a diskette`.

---

### Task 21: Guide 20 — Build multilingual

**Files:** Create `docs/sf/manuals/en/vol5-20-build-multilingual.html`; wire.
**Consumes:** Task 0 (the page template, the language bar, `check.py`).
**Must cover:** producing one language's manual from the template, the encoding rules for non-Latin scripts, and how `check.sh`/`index` treat a translation. Translations are `(planned)`.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 20 — build a translated manual`.

---

### Task 22: Guide 21 — Static site

**Files:** Create `docs/sf/manuals/en/vol5-21-static-site.html`; wire.
**Consumes:** Task 0 (`docs/sf/manuals/check.sh`/`check.py`, `/tmp/z98_build_tmp.sh`, the `dist`-hang reality).
**Must cover:** the doc generator pipeline (gate + search-index regeneration), how a page is added, and the host's `build.sh`/`dist` limitation with the workaround.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 21 — build the static site`.

---

### Task 23: Guide 22 — Contribute

**Files:** Create `docs/sf/manuals/en/vol5-22-contribute.html`; wire.
**Consumes:** Task 0 (`docs/sf/AGENTS.md`, repo layout, the seed model).
**Must cover:** the repo layout, the edit/verification conventions, the seed/amendment protocol, and how to prepare a patch.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 22 — contribute`.

---

### Task 24: Guide 23 — Report a bug

**Files:** Create `docs/sf/manuals/en/vol5-23-report-bug.html`; wire.
**Consumes:** Task 0 (`repro/mi_matrix` repro conventions, `run_all.sh`, diagnostics).
**Must cover:** what a bug report must include (compiler version/fixed point, minimal program, exact command, expected vs actual output, diagnostic) and how to minimise a reproduction.
- [ ] Steps 1–7. **Commit:** `docs(manual): add Volume V guide 23 — report a bug`.

---

### Task 25: Whole-set closeout

**Files:** Modify `docs/sf/manuals/**` (nav/index), `docs/superpowers/specs/2026-10-05-z98-manual-volume-V-design.md` (status), `release/seed/**` (only if rotated), `docs/sf/QUICK_REF.md`, `release/seed/CHANGELOG.md`.
**Consumes:** all guide pages; the Task 0 coverage report.
- [ ] **Step 1: Re-verify every guide.** Re-run/reuse each guide's Verify step; confirm every shipped transcript still matches (reuse the recorded measured output where the artifact is unchanged; only re-run a step that is suspicious or contradictory per the reuse-first rule).
- [ ] **Step 2: Navigation sweep.** Sidebar 25 rows on every `vol5-*` page; `rel` chain continuous `toc → vol5-00 → … → vol5-23 → toc.html`; `toc.html` lists every shipped guide; no stale `(planned)` for a shipped guide.
- [ ] **Step 3: Figure audit.** Placeholders/rows 1:1 for any figures shipped (39+).
- [ ] **Step 4: Gates.** `check.sh` green; index byte-match idempotent.
- [ ] **Step 5: Spec status.** Set the Volume V design status to **Implemented** with a closeout section.
- [ ] **Step 6: Seed rotation.** Rotate v91 → v92 iff an amendment moved the fixed point; verify the post-rotation two-hop closure; update QUICK_REF/CHANGELOG/SEED_README.
- [ ] **Step 7: Final commit.** `docs(manual): Volume V closeout — whole-set review and verification sweep`.
