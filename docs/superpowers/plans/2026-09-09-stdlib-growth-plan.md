# Stdlib Growth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow the Z98 stdlib from 4 files / 389 lines to a usable core (`std_str`, `std_mem`, `std_math`, `std_debug`, `std_io` file I/O, `std_arena` per-arena rewrite, `std.zig` full re-export) — every module written in Z98, cstdio-free, pinned by corpus fixtures.

**Architecture:** New/changed modules live at `sf/src/` (installed to `<exe>/lib`). They are **user-program modules** (not in the compiler's `sf/src/main.zig` import graph) so they do not move the self-emission fixed point; correctness is pinned by corpus fixtures that `@import("std")` and assert byte-exact stdout. All I/O routes through the existing PAL/Win32 surface. **EXCEPTION (AMENDMENT 1):** Task 3 extends `pal.zig` + `zig_pal.c` (compiler-graph files) to add a Win9x-clean file-READ primitive → the self-emission fixed point MOVES there; Task-6 seed rotation becomes mandatory.

**Tech Stack:** Z98, `sf/src/std*.zig`, PAL externs (`pal.zig`, `zig_pal.c`), corpus fixtures in `repro/mi_matrix/`.

**Spec:** `docs/superpowers/specs/2026-09-09-stdlib-growth-design.md`

## Global Constraints

- **Win9x API set — no cstdio / no C-runtime dependence (hard, grep-audited).** All I/O/alloc via `@`-builtins + PAL/Win32 externs only. Grep every new module for `printf|fwrite|fopen|fread|malloc|strlen|strcpy|puts` → must be 0.
- **Reference per the seed model** (`release/seed/`); measurement compiler = the N-hop-converged binary, stated per report. Dump CWD = repo root, relative `sf/src/main.zig`.
- **Flag-set rule:** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; `-Wall -Wextra -O3 -fsyntax-only` separate gate.
- **Corpus primary oracle:** 420 dirs = 404 OK / 9 GREEN / 7 FAIL at HEAD (post-EMITCOMPACT). Each increment zero-asymmetric except its own new fixture dirs. Golden 9/9 + matrix 21/21 run byte-identity.
- **4-MD5 dump gates:** re-baselined at Task 2 (pure re-export, runtime-identical); from Task 3 onward the compiler source itself changes (`pal.zig`) so every increment re-dumps + runtime-identical-verifies + re-baselines the rows in QUICK_REF (AMENDMENT 1).
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

## AMENDMENT 1 — Task 3 scope + fixed-point consequence (OPERATOR RULING 2026-09-10)

**Ruling (operator, STOP-present):** std_io's `fileRead` has NO Win9x-clean PAL surface to wrap — Task-1 census proved `pal_file_open/write/close` are structurally WRITE-ONLY (POSIX `O_WRONLY|O_CREAT|O_TRUNC`, Win32 `GENERIC_WRITE|CREATE_ALWAYS`); `pal_file_read` does not exist; the only read path (`stream*`, `pal.readFile`) is libc `FILE*` (cstdio). The operator chose **option (a): Extend PAL now (read+write)**.

**Consequences (binding):**
1. Task 3 file scope EXPANDS to compiler-graph files:
   - Modify `sf/src/include/zig_pal.c` — add read-mode open (POSIX `O_RDONLY` / Win32 `GENERIC_READ` branch) + new `pal_file_read` returning a byte count.
   - Modify `sf/src/pal.zig` — add the `pal_file_read` extern + a `fileRead` wrapper (and any mode-flag plumbing) alongside the existing `fileOpen`/`fileWrite`/`fileClose`.
   - `pal.zig` IS in the compiler's `sf/src/main.zig` import graph (imported by c89_emit.zig/front_resolution.zig/allocator.zig/ast.zig/etc.) → **the self-emission fixed point WILL MOVE**.
2. **Task 6 seed rotation + N-hop + full 4-MD5 re-baseline + full battery become MANDATORY** (not conditional) once Task 3 lands the PAL change. The fixed point `ea149e05` (seed v6) will be superseded; a new fixed point must be N-hop-closed from the committed seed and the seed rotated v6→v7.
3. `std_io` file API (`fileOpen`/`fileWrite`/`fileRead`/`fileClose`) wraps the PAL surface — with the read leg now real and Win9x-clean.
4. `std_debug` (`log`/`logInt`/`assert`/`panic`): Task-1 RED probe proved `@panic`/`unreachable` LOWER TO NO-OPS in user programs. Binding: assert/panic must use a PRINTED abort (message via `@stdoutWrite`/`@putChar`) followed by a non-returning trap (`while(true){}` in a `noreturn` fn) or `c_exit` (pal-provided). Do NOT rely on `@panic`/`unreachable`.
5. Every stdlib increment from Task 3 on re-baselines the four 4-MD5 rows (compiler changed) — follow the Task-2 precedent: re-dump gates, verify runtime-identical, re-baseline rows in QUICK_REF in the task's own docs commit.

### Task 3: `std_debug` + `std_io` file I/O over extended PAL (F) — scope amended by AMENDMENT 1

**Files:**
- Create: `sf/src/std_debug.zig`
- Modify: `sf/src/std_io.zig` (add file API: `fileOpen`/`fileWrite`/`fileRead`/`fileClose` over the PAL surface)
- Modify: `sf/src/include/zig_pal.c` (read-mode open + `pal_file_read` byte-count read) — AMENDMENT 1
- Modify: `sf/src/pal.zig` (read-mode plumbing + `pal_file_read` extern + `fileRead` wrapper) — AMENDMENT 1
- Modify: `sf/src/std.zig` (re-export `debug`)
- Create (fixtures): `repro/mi_matrix/stdlib_debug_xmod/main.zig`, `repro/mi_matrix/stdlib_fileio_xmod/main.zig`
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 3`)
- Commit: `feat: stdlib — std_debug + std_io file I/O over PAL (STDLIB)` (AMENDMENT 1: scope incl. zig_pal.c + pal.zig)

- [ ] **Step 1: Author `std_debug`** per spec §3.4 (`log`/`logInt`/`assert`/`panic`, all via `@stdoutWrite`/`@putChar`). Panic mechanism PINNED by AMENDMENT 1: printed abort + non-returning trap or `c_exit` — `@panic`/`unreachable` are no-ops and MUST NOT be used.
- [ ] **Step 2: Extend the PAL (AMENDMENT 1)** — add read-mode open to `pal_file_open` in `zig_pal.c` (POSIX `O_RDONLY`; Win32 `GENERIC_READ`, no CREATE_ALWAYS on read) + new `pal_file_read(fd, buf, len)` returning bytes-read (POSIX `read` loop / Win32 `ReadFile`); mirror the `pal.zig` extern decls + a `fileRead` wrapper. Preserve the existing write/close symbols byte-identical.
- [ ] **Step 3: Add the file API to `std_io`** wrapping the now-complete PAL surface (`fileOpen`/`fileWrite`/`fileRead`/`fileClose`). No cstdio — wrappers call the PAL externs only.
- [ ] **Step 4: Author fixtures.** `stdlib_debug_xmod`: log/assert/pass output byte-exact. `stdlib_fileio_xmod`: write a temp file → close → read back → assert byte-exact content (POSIX run).
- [ ] **Step 5: Run gate** (as Task 2 Step 3): fixtures GREEN 3×, golden/matrix byte-identity, corpus zero-asymmetric except the 2 new dirs, cstdio grep 0. **4-MD5: re-dump + runtime-identical verify + re-baseline rows in QUICK_REF (AMENDMENT-1 consequence — compiler changed).** Fixed point now EXPECTED to move: run the N-hop chain from the committed seed and RECORD the new fixed point (do not rotate the seed in this task; rotation is Task 6).
- [ ] **Step 6: Commit** (message above).
- [ ] **Step 7: Report + ledger.**

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

### Task 6: Full battery + docs GATE + seed rotation (I then F, after operator approval) — AMENDMENT 1: rotation MANDATORY

**Files:**
- Report: `.superpowers/sdd/task-STDLIB-report.md` (appended `## Task 6`)
- Modify: `docs/sf/QUICK_REF.md` (stdlib bullet), `release/seed/CHANGELOG.md` + `release/seed/zig1-seed.tgz` (MANDATORY — AMENDMENT 1: the Task-3 `pal.zig` change moved the fixed point), `repro/mi_matrix/EXPECTED_FAIL.md` (only if fixture movement occurred)
- Commit (F): `docs: GATE — stdlib growth (STDLIB)`

- [ ] **Step 0 (F, prerequisite from Task-3 review):** fix `scripts/seed/build_from_seed.sh:125` — it still copies only 4 std files (`std.zig std_io std_arena std_net`) into `<out>/lib`, so a fresh seed rebuild is missing `str/mem/math/debug`. Update it to the full install set (8 files per the QUICK_REF:85 recipe) BEFORE any seed rotation, so the rotated seed's lib is self-consistent.
- [ ] **Step 1 (I): Full battery** — golden 9/9 + matrix 21/21 run byte-identity; corpus `-s0` zero-asymmetric vs Task-5; all stdlib fixtures GREEN deterministic; cstdio grep across `sf/src/std*.zig` = 0. N-hop from the committed seed (gate A) — **fixed point EXPECTED to have moved (AMENDMENT 1); close the chain to the new fixed point and record it**.
- [ ] **Step 2 (I): STOP-present** the re-baseline + seed-rotation + docs-GATE plan to the operator; await approval.
- [ ] **Step 3 (F): Docs GATE** — QUICK_REF newest-first stdlib bullet; 4-MD5 rows re-baselined; seed rotation v6→v7 (AMENDMENT 1 — fixed point moved); EXPECTED_FAIL bump only if fixture movement occurred.
- [ ] **Step 4: Report + ledger close**, STOP-present the plan close.

---

## Next-up items (NOT tasks of this plan — spec §5, kept so they aren't forgotten)

- **C89-ahead features plan** (`volatile` feasibility, `static`, `do…while`, type-alias) — runs after this plan.
- EMITCOMPACT executes before this plan in the forward queue.
- String formatting beyond the existing decompose; containers (ArrayList/hash-map std forms); parsing libraries.
