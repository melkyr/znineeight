# Stdlib Growth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow the Z98 stdlib from 4 files / 389 lines to a usable core (`std_str`, `std_mem`, `std_math`, `std_debug`, `std_io` file I/O, `std_arena` per-arena rewrite, `std.zig` full re-export) — every module written in Z98, cstdio-free, pinned by corpus fixtures.

**Architecture:** New/changed modules live at `sf/src/` (installed to `<exe>/lib`). They are **user-program modules** (not in the compiler's `sf/src/main.zig` import graph) so they do not move the self-emission fixed point; correctness is pinned by corpus fixtures that `@import("std")` and assert byte-exact stdout. All I/O routes through the existing PAL/Win32 surface.

**Tech Stack:** Z98, `sf/src/std*.zig`, PAL externs (`pal.zig`, `zig_pal.c`), corpus fixtures in `repro/mi_matrix/`.

**Spec:** `docs/superpowers/specs/2026-09-09-stdlib-growth-design.md`

## Global Constraints

- **Win9x API set — no cstdio / no C-runtime dependence (hard, grep-audited).** All I/O/alloc via `@`-builtins + PAL/Win32 externs only. Grep every new module for `printf|fwrite|fopen|fread|malloc|strlen|strcpy|puts` → must be 0.
- **Reference per the seed model** (`release/seed/`); measurement compiler = the N-hop-converged binary, stated per report. Dump CWD = repo root, relative `sf/src/main.zig`.
- **Flag-set rule:** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; `-Wall -Wextra -O3 -fsyntax-only` separate gate.
- **Corpus primary oracle:** 420 dirs = 404 OK / 9 GREEN / 7 FAIL at HEAD (post-EMITCOMPACT). Each increment zero-asymmetric except its own new fixture dirs. Golden 9/9 + matrix 21/21 run byte-identity.
- **4-MD5 dump gates unchanged by stdlib work** unless a gate program imports a changed std module → if so, recorded-not-rebaselined; operator-ruled re-baseline only at closeout.
- **Working conventions:** SDD mandatory; compression forbidden during build sessions; memories via `mnemoria --path .opencode/memory add` under agent `stdlib-session`; edits via `edit`/`fastedit` only; no commit until review clean; pre-existing dirty set never staged.
- Report `.superpowers/sdd/task-STDLIB-report.md`; ledger `.superpowers/sdd/progress.md`; memory agent `stdlib-session`.

---

### Task 1: Baseline + PAL file-surface census + consumer audit (I, record-only)

**Files:**
- Read: `sf/src/std*.zig`, `sf/src/pal.zig`, `sf/src/include/zig_pal.c`, `sf/src/std_net.zig`, all current `std` consumers (corpus fixtures + examples that `@import("std")` / `@import("std_arena.zig")`)
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 1`)
- No source edits, no commit, nothing staged.

- [ ] **Step 1: Baseline.** Reconfirm HEAD, fixed point `ea149e05` (seed v6), 4-MD5 (gol `bbafa30f…`, lisp `c1767529…`, json `3ada7d8b…`, mud `ee42f9b7…`), EXPECTED_FAIL v76, corpus 420 dirs = 404/9/7. Record.
- [ ] **Step 2: PAL file-surface census.** Read `pal.zig` (fileOpen/fileWrite/fileClose/streamOpen/streamClose/streamWrite/streamRead/streamSeek at :88-153) and `zig_pal.c` (`pal_file_write`/`pal_file_close` at :193-208, `CreateFileA` at :184). Determine: which file primitives are live + correct at HEAD, their exact Z98-visible signatures, return conventions (handle type, `?*void` vs `usize`), and whether a read path returns a byte count. Record the exact extern/wrapper surface the `std_io` file API will wrap. Verify a minimal file write→close→read-back round trip works on POSIX today (scratch probe, not committed).
- [ ] **Step 3: `std.zig` re-export census (A2).** Test whether `pub const net = @import("std_net.zig")` in `std.zig` breaks programs that never use net (std_net carries `@cInclude("<net_prelude.h>")` + wsock32 externs). Also test unconditional re-export of the planned `str`/`mem`/`math`/`debug` modules (they are pure — expected safe). Record the decision: unconditional, platform-gated, or direct-import-only for `net`.
- [ ] **Step 4: `std_arena` consumer audit.** Enumerate every program/fixture that imports `std_arena` or uses `std.arena` (the shared-global stub). Record the exact migration each needs for the per-arena `init(data)` form. List the affected fixtures that will need source migration + runtime re-verification.
- [ ] **Step 5: RED probes for each planned module.** Author scratch probes (NOT committed) confirming each module's functions compile or fail as expected today, and that a fixture importing a not-yet-existing `std_str` fails cleanly (absent module → `error[3048]`-class). Record.
- [ ] **Step 6: Report + ledger.** Append full census; one ledger line. No commit.

---

### Task 2: `std_str` + `std_mem` + `std_math` (pure modules) + fixtures (F)

**Files:**
- Create: `sf/src/std_str.zig`, `sf/src/std_mem.zig`, `sf/src/std_math.zig`
- Modify: `sf/src/std.zig` (re-export the three, per Task-1 A2 verdict)
- Create (fixtures): `repro/mi_matrix/stdlib_str_xmod/main.zig`, `repro/mi_matrix/stdlib_mem_xmod/main.zig`, `repro/mi_matrix/stdlib_math_xmod/main.zig`
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 2`)
- Commit: `feat: stdlib — std_str/std_mem/std_math modules + corpus fixtures (STDLIB)`

**Interfaces:**
- Consumes: Task-1 A2 re-export verdict.
- Produces: three pure modules + their re-exports + GREEN fixtures.

- [ ] **Step 1: Author the three modules per spec §3.1-3.3** (concrete-type `std_mem` variants, no generics). Z98-only, no externs. Follow existing stdlib style (`std_io.zig`/`std_arena.zig` conventions).
- [ ] **Step 2: Author the three fixtures.** Each imports the module via `std.<mod>` (or direct `@import`) and asserts byte-exact GREEN stdout, exercising the module AND ≥1 shipped compiler feature (optional return `?usize`, `for` over slice, `u32` width).
- [ ] **Step 3: Run gate.** Fixtures classify OK + run GREEN byte-exact deterministic 3× (RUNRC=0). Golden 9/9 + matrix 21/21 run byte-identity vs PRE. Corpus `-s0` zero-asymmetric except the 3 new dirs. Grep audit: 0 cstdio in the new modules. 4-MD5 unchanged. Record.
- [ ] **Step 4: Commit** (message above; scope = the 3 modules + `std.zig` + 3 fixture dirs).
- [ ] **Step 5: Report + ledger.**

---

### Task 3: `std_debug` + `std_io` file I/O (F)

**Files:**
- Create: `sf/src/std_debug.zig`
- Modify: `sf/src/std_io.zig` (add file API per Task-1 surface census)
- Modify: `sf/src/std.zig` (re-export `debug`)
- Create (fixtures): `repro/mi_matrix/stdlib_debug_xmod/main.zig`, `repro/mi_matrix/stdlib_fileio_xmod/main.zig`
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 3`)
- Commit: `feat: stdlib — std_debug + std_io file I/O over PAL (STDLIB)`

- [ ] **Step 1: Author `std_debug`** per spec §3.4 (`log`/`logInt`/`assert`/`panic`, all via `@stdoutWrite`/`@putChar`; pin the exact panic mechanism available in Z98).
- [ ] **Step 2: Add the file API to `std_io`** wrapping the Task-1-verified PAL surface (`fileOpen`/`fileWrite`/`fileRead`/`fileClose`). No cstdio — verify the wrappers call the PAL externs only.
- [ ] **Step 3: Author fixtures.** `stdlib_debug_xmod`: log/assert/pass output byte-exact. `stdlib_fileio_xmod`: write a temp file → close → read back → assert byte-exact content (POSIX run).
- [ ] **Step 4: Run gate** (as Task 2 Step 3): fixtures GREEN 3×, golden/matrix byte-identity, corpus zero-asymmetric except the 2 new dirs, cstdio grep 0, 4-MD5 unchanged.
- [ ] **Step 5: Commit** (message above).
- [ ] **Step 6: Report + ledger.**

---

### Task 4: `std_arena` per-arena rewrite + consumer migration (F)

**Files:**
- Rewrite: `sf/src/std_arena.zig` (per spec §3.6: `init(data)`/`alloc`/`reset`, drop shared globals)
- Migrate: every consumer the Task-1 audit enumerated (fixtures/examples using the old `create()`/shared-global form)
- Create (fixture): `repro/mi_matrix/stdlib_arena_xmod/main.zig` (two independent `Arena`s over distinct buffers)
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 4`)
- Commit: `feat: stdlib — std_arena per-arena allocator + consumer migration (STDLIB)`

- [ ] **Step 1: Rewrite `std_arena`** to the self-contained per-arena form. Remove `g_storage`/`g_used`.
- [ ] **Step 2: Migrate every audited consumer** to `std.arena.init(buffer[0..])`; verify each migrated program still compiles and its runtime output is byte-identical to PRE (re-verify the affected fixtures' run gates).
- [ ] **Step 3: Author the arena fixture** (two independent arenas; second alloc fails only when its own buffer is exhausted; reset independence).
- [ ] **Step 4: Run gate** (as Task 2 Step 3), plus re-run every migrated consumer's runtime byte-identity.
- [ ] **Step 5: Commit** (message above).
- [ ] **Step 6: Report + ledger.**

---

### Task 5: `std.zig` full re-export close + net (F)

**Files:**
- Modify: `sf/src/std.zig` (final re-export set incl. `net` per the Task-1 A2 verdict)
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 5`)
- Commit: `feat: stdlib — std.zig full module re-export (STDLIB)`

- [ ] **Step 1: Apply the A2 verdict** — re-export `str`/`mem`/`math`/`debug`/`arena`/`io` and `net` (unconditional, platform-gated, or direct-import-only as the census decided).
- [ ] **Step 2: Verify every stdlib fixture still imports through `std.`** where applicable and runs GREEN.
- [ ] **Step 3: Run gate** (golden/matrix byte-identity, corpus zero-asymmetric, cstdio grep over all stdlib modules = 0).
- [ ] **Step 4: Commit** (message above).
- [ ] **Step 5: Report + ledger.**

---

### Task 6: Full battery + docs GATE + seed rotation (I then F, after operator approval)

**Files:**
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 6`)
- Modify: `docs/sf/QUICK_REF.md` (stdlib bullet), `release/seed/CHANGELOG.md` + `release/seed/zig1-seed.tgz` (only if the fixed point moved), `repro/mi_matrix/EXPECTED_FAIL.md` (only if fixture movement occurred)
- Commit (F): `docs: GATE — stdlib growth (STDLIB)`

- [ ] **Step 1 (I): Full battery** — golden 9/9 + matrix 21/21 run byte-identity; corpus `-s0` zero-asymmetric vs Task-5; all stdlib fixtures GREEN deterministic; cstdio grep across `sf/src/std*.zig` = 0. N-hop from the committed seed (gate A) — the stdlib is user-module-only so the fixed point should be unchanged; record the chain.
- [ ] **Step 2 (I): STOP-present** any gate re-baseline or docs-GATE plan to the operator; await approval.
- [ ] **Step 3 (F): Docs GATE** — QUICK_REF newest-first stdlib bullet; EXPECTED_FAIL bump only if fixture movement occurred; seed rotation only if the fixed point moved.
- [ ] **Step 4: Report + ledger close**, STOP-present the plan close.

---

## Next-up items (NOT tasks of this plan — spec §5, kept so they aren't forgotten)

- **C89-ahead features plan** (`volatile` feasibility, `static`, `do…while`, type-alias) — runs after this plan.
- EMITCOMPACT executes before this plan in the forward queue.
- String formatting beyond the existing decompose; containers (ArrayList/hash-map std forms); parsing libraries.
