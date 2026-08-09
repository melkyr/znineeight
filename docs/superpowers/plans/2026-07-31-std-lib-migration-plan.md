# Bootstrap → Z98 Std Lib Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Research and implement a proper Z98 standard library (`std.zig`, `std_io.zig`, `std_net.zig`, `std_os.zig`, `std_arena.zig`) and migrate all examples away from `extern fn __bootstrap_*` declarations. **Also solve the two std-lib-deferred gaps from the multi-module fixes plan** (AMENDMENT 2026-08-08): the `arena_alloc_default` runtime gap (json_parser + json_parser_workaround) and the 5 `plat_console_*`/`plat_is_windows` stubs (rogue_mud).

**Architecture:** One I-task (research + report, incorporating the existing I2/I4 deferred-item reports) followed by F-tasks. I-task inventories every bootstrap call site, designs the Z98 std API, maps PAL boundary, and orders the migration. F-tasks create the std lib packages, migrate examples, and implement the arena + plat stubs.

**Tech Stack:** Z98-compatible Zig, zig1 binary at `sf/build/out_release/zig1`, PAL C layer stays in `sf/src/include/zig_pal.c`.

## Global Constraints

- **PAL C layer stays** — `sf/src/include/zig_pal.c` keeps Win32/POSIX `#ifdef` for platform portability
- **Pure Z98 where possible** — format/itoa/mem helpers written in Z98, emitted as C89 by zig1
- **Extern C only at PAL boundary** — `std_pal.zig` is the single file declaring `extern "c" fn pal_*`
- **Corpus gate (AMENDMENT 2026-08-08):** manifest 230 repros, **OK=223 / FAIL=3 / green-guards=4** (sweep 237 dirs: OK=229 / FAIL=8 / ICE=0 / CRASH=0 — the sweep lumps the 4 green-guards into FAIL and counts the 7 plan-added dirs separately). FAIL must not increase. **json_parser, json_parser_workaround, rogue_mud MUST clear** (currently OK-by-gate/latent or link-deferred) — these are the std-lib deferred items this plan solves.
- **4 MD5 gates byte-identical** (AMENDMENT 2026-08-08): mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `a12f2fcebc30f2d8c2a148facb9d1174` (post-F1 re-baseline), json `c403f0799dbc5c56d548eee07bb9eebd`. UNLESS operator-approved re-baseline with runtime proof (AMENDMENT B). **json MD5 likely re-baselines** when json_parser starts linking its arena (emitted C unchanged — json_parser currently doesn't emit; verify).
- **Runtime gate:** all 21 Z98 examples build + link + run correctly (was 18 — 3 new: json_parser_workaround, rogue_mud, mud_server already existed; the count is 21 today)
- **fastedit/edit only for source edits** — per AGENTS.md §X.7. NO sed/python bulk transforms.
- **Commit per task**
- **Follow QUICK_REF.md for build/run commands**
- **Plan says A, you do A** — STOP on ambiguity, present to operator
- **zig1 self-compile note (AMENDMENT 2026-08-08):** arena resize landed (perm 4M / mod 8M / scr 2M + 16M budget, commit 462ddee4). Scratch-arena OOM on the largest file remains a FUTURE investigation (per-module scratch reset / scratch 4M / token array to module arena) — NOT in this plan's scope unless the operator rules otherwise.

---

### Task I-B: Research bootstrap migration strategy + deferred-item design

**Files:**
- Read: all 21 example `.zig` files, `sf/src/include/zig_runtime.c`, `sf/src/include/zig_pal.c`, `sf/src/pal.zig`
- Read (existing reports — AMENDMENT 2026-08-08): `.superpowers/sdd/I-orphan-module-report.md` (I2 — arena_alloc_default), `.superpowers/sdd/I-platstub-gap-report.md` (I4 — plat_ stubs)
- Create: `.superpowers/sdd/IB-report.md` (research report)

**Research questions:**

1. **Bootstrap call site inventory.** Per example, per file, per `extern fn __bootstrap_*` declaration + call site counts. Map bootstrap functions to their PAL backing (e.g. `__bootstrap_print` → `pal_print_stdout`). Count the cast-helper family (`__bootstrap_usize_from_i64`, `__bootstrap_i32_from_u32`, `__bootstrap_u32_from_u64`, `__bootstrap_u32_from_i32`, `__bootstrap_usize_from_i32`, `__bootstrap_i32_from_usize`, `__bootstrap_u8_from_usize`, etc.) — these are the compiler's `@intCast` runtime helpers and are NOT examples-only; their std-lib home must be decided (keep in zig_runtime.c OR move into std). **Report which are example-only vs compiler-needed.**

2. **Compiler's own I/O.** How does zig1 currently write diagnostics, markers, panic? (`pal.zig`, `extern_c.zig`). What must change for zig1 to use `const std = @import("std")` instead?

3. **PAL function inventory.** List every `pal_*` function in `zig_pal.c` and its Win32/POSIX branches. Which must be exposed to Z98 via `std_pal.zig`?

4. **Z98 std API design.** Exact function signatures for `std.io.print()`, `std.io.write()`, `std.net.listen()`, `std.os.sleep()`, `std.arena.create()/alloc()/reset()`. Pure Z98 bodies for format/itoa/mem; extern C for PAL I/O.

5. **Bootstrap compatibility.** Can zig0 compile zig1 when zig1 `@import("std")` brings in `std_io.zig` which has `extern "c" fn pal_print_stdout`? Does zig0 handle multi-module compilation with `extern "c"` in imported modules?

6. **Migration order.** Which examples migrate first (simplest: hello, fibonacci, prime). Which need `std.net` (mud_server). per-example change count (file:line of each `extern fn` to replace).

7. **Arena design (AMENDMENT 2026-08-08 — solves json_parser + json_parser_workaround).** From I2: `arena_alloc_default` is an extern (json.zig:253, file.zig:25) declared in `zig_runtime.h:21-22`, defined ONLY in legacy `src/runtime/zig_runtime.c:154-156` (with `arena_create/alloc/reset/destroy/free` at :71-158), absent from `sf/src/include/zig_runtime.c`. Decide the std-lib home: **Option A** — `std_arena.zig` with `pub fn create/alloc/reset/free` in pure Z98 (bump allocator on a fixed buffer, matching the legacy arena semantics) — no new PAL C needed; **Option B** — port the legacy arena functions verbatim into `sf/src/include/zig_runtime.c` (C, not std-lib); **Option C** — `std_arena.zig` declaring `extern "c" fn arena_alloc_default` and leaving the C definition to a future runtime file. Recommend one (operator previously leaned: "I2 probably will be part of the std zig1 library rather than those zig_runtime.c stubs" — so Option A/C preferred over B). json_parser + json_parser_workaround must then clear (gcc link rc=0, run rc=0).

8. **Plat console design (AMENDMENT 2026-08-08 — solves rogue_mud).** From I4: 5 missing symbols (`plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`, `plat_console_putchar`, `plat_console_clear`) — all rogue_mud-only, declared in `examples/z98/rogue_mud/ui.zig:11-14`. Design the std-lib home: a new PAL C file `sf/src/include/zig_pal_console.c` (or extend `zig_pal.c`) with POSIX implementations (putchar → putchar, clear → ANSI escape, gotoxy → ANSI escape, setcolor → ANSI escape, is_windows → 0/false) + `std_pal.zig` extern declarations. rogue_mud must then link rc=0. Win32 `#ifdef` variants can be stubbed (rogue_mud runs POSIX in this project).

**Steps:**
- [ ] **Step 1:** Grep all 21 examples for `__bootstrap_*` / `extern fn` — produce counts table per example. Split cast-helper vs I/O functions.
- [ ] **Step 2:** Read `sf/src/include/zig_pal.c` fully — inventory every PAL function + `#ifdef` branch.
- [ ] **Step 3:** Read `sf/src/pal.zig` — compiler's own I/O, what must change.
- [ ] **Step 4:** Test zig0 bootstrap: add `@import("std")` to a test zig1 module, verify zig0 compiles it.
- [ ] **Step 5:** Read the I2 + I4 reports. Design the arena std-lib home (Option A/B/C) + the plat console std-lib home. Include exact file:line edit targets for json_parser, json_parser_workaround, rogue_mud.
- [ ] **Step 6:** Write IB-report with bootstrap → Z98 mapping table, API signatures (file:line), migration order, Option A/B/C for PAL boundary placement + arena + plat, blast-radius analysis.
- [ ] **Step 7:** Commit checkpoint `bugfix: IB research report for bootstrap migration + deferred-item design`

**Interfaces:**
- Produces: `IB-report.md` with bootstrap call site inventory, Z98 std API design, migration order per example, deferred-item solutions (arena + plat), exact edit targets.

---

### Task F-B1: Create Z98 std lib packages + verify zig1 bootstrap

**Files:**
- Create: `sf/src/std.zig`, `sf/src/std_io.zig`, `sf/src/std_pal.zig`, `sf/src/std_net.zig`, `sf/src/std_os.zig`
- Verify: `bash sf/scripts/build_release.sh` (zig1 bootstraps with std lib importable)

**Per IB-report recommendations (API signatures from the report — exact values there):**

- [ ] **Step 1:** Create Z98 std lib packages — `std.zig` (root: `pub const io = @import("std_io.zig"); pub const os = @import("std_os.zig"); pub const net = @import("std_net.zig"); pub const arena = @import("std_arena.zig");`), `std_io.zig` (print/write/read_line + itoa/format in pure Z98), `std_pal.zig` (extern C wrappers to zig_pal.c)
- [ ] **Step 2:** Verify zig1 compiles using std (bootstrap gate: `bash sf/scripts/build_release.sh`, gate `=== [release] Done: sf/build/out_release/zig1 ===`)
- [ ] **Step 3:** Commit

**Gate:** std packages exist; zig1 bootstraps clean.

---

### Task F-B2: Migrate compiler's own I/O

**Files:**
- Modify: `sf/src/pal.zig` (migrate to `std.io` for compiler diagnostics/markers/panic)
- Test: `bash sf/scripts/build_release.sh` + run a compile that emits an error (verify stderr still works)

**Per IB-report recommendations.**

- [ ] **Step 1:** Replace `pal.zig`'s raw write/extern calls with `std.io.err.write(...)` per IB-report mapping
- [ ] **Step 2:** Build + verify: `bash sf/scripts/build_release.sh` gate; compile a bad file → error prints to stderr correctly
- [ ] **Step 3:** 4 MD5 gates byte-identical (compiler output must not change — emitted C identical)
- [ ] **Step 4:** Commit

**Gate:** zig1 boots + diagnostics unchanged; 4 MD5s byte-identical.

---

### Task F-B3: Migrate examples to std lib

**Files:**
- Modify: example `.zig` files (replace `extern fn __bootstrap_*` with `@import("std")`) — in IB-report order, one category per commit
- Modify: `sf/src/include/zig_runtime.c` (remove now-dead `__bootstrap_*` wrappers at :67-72 — ONLY the example-only I/O ones; keep the cast-helper family if the compiler still needs it)
- Update: all 21 `examples/z98/*/NOTES.md`

**Per IB-report migration order (single-file first, then multi-module, then net/lisp).**

- [ ] **Step 1:** Migrate single-file examples (hello, fibonacci, prime, mandelbrot, days_in_month, tco_*, func_ptr_return, heapsort, quicksort, sort_strings) — one commit per category
- [ ] **Step 2:** Migrate multi-module examples (game_of_life, lzw, lisp_interpreter_*, json_parser, json_parser_workaround)
- [ ] **Step 3:** Migrate networking (mud_server, rogue_mud — needs std.net + plat console)
- [ ] **Step 4:** Remove example-only `__bootstrap_*` wrappers from `zig_runtime.c`
- [ ] **Step 5:** Build + run all 21 examples (runtime gate — each prints expected output, rc=0)
- [ ] **Step 6:** 4 MD5 gates (re-baseline json only if its emitted C changes — likely byte-identical since it currently doesn't emit)
- [ ] **Step 7:** Corpus gate: 230/OK=223/FAIL=3/gg=4 — FAIL must not increase
- [ ] **Step 8:** Update all 21 NOTES.md
- [ ] **Step 9:** Tech doc update: `00_shared_infra.md` (PAL section)
- [ ] **Step 10:** Commit per category

**Gate:** all 21 examples build + link + run; corpus FAIL not increased; 4 MD5s verified; NOTES.md updated.

---

### Task F-B4: Implement arena_alloc_default in std lib (AMENDMENT 2026-08-08 — solves json_parser + json_parser_workaround)

**Files:**
- Create: `sf/src/std_arena.zig` (per IB-report Option A/C recommendation — pure Z98 bump allocator, or extern-wrapping `arena_alloc_default`)
- Modify: `examples/z98/json_parser/*.zig`, `examples/z98/json_parser_workaround/*.zig` (import std.arena instead of bare extern)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md` (arena extern note) + example NOTES.md
- Test: `repro/mi_matrix/extern_runtime_symbol_xmod/`, `examples/z98/json_parser/`, `examples/z98/json_parser_workaround/`

**Context (I2):** `arena_alloc_default` extern (json.zig:253, file.zig:25) declared `zig_runtime.h:21-22`, defined ONLY in legacy `src/runtime/zig_runtime.c`, absent from `sf/src/include/zig_runtime.c`. Standard link fails `undefined reference` ×5. Legacy link works (run rc=0). This task closes the gap per the IB-report design.

- [ ] **Step 1:** Implement `std_arena.zig` per IB-report Option A/C (pure Z98 bump allocator with create/alloc/reset/free — or the extern-wrapping option if chosen)
- [ ] **Step 2:** Migrate json_parser + json_parser_workaround to `@import("std").arena` (replace bare extern)
- [ ] **Step 3:** Build + verify: `extern_runtime_symbol_xmod` repro links rc=0 (standard runtime recipe, no legacy file); json_parser links rc=0 + runs rc=0 printing expected JSON output; json_parser_workaround links rc=0
- [ ] **Step 4:** Update tech docs + NOTES.md (deferred → fixed)
- [ ] **Step 5:** 4 MD5 gates (json likely unchanged — verify)
- [ ] **Step 6:** Commit

**Gate:** `extern_runtime_symbol_xmod` + json_parser + json_parser_workaround all link rc=0 with the STANDARD runtime; run rc=0; 4 MD5s verified.

---

### Task F-B5: Implement plat_ console stubs in std lib (AMENDMENT 2026-08-08 — solves rogue_mud)

**Files:**
- Create: `sf/src/include/zig_pal_console.c` (POSIX implementations: putchar → putchar, clear → ANSI `\x1b[2J`, gotoxy → ANSI `\x1b[<y>;<x>H`, setcolor → ANSI `\x1b[<fg>;<bg>m`, is_windows → returns 0) + `sf/src/include/zig_pal_console.h` + Win32 `#ifdef` variants (may stub)
- Modify: `sf/src/std_pal.zig` (add extern declarations for the 5 console functions)
- Modify: `examples/z98/rogue_mud/ui.zig` (import std_pal instead of bare externs) — or keep ui.zig externs if they match std_pal signatures (verify)
- Modify: `sf/src/include/zig_pal.h` (declare the 5 new functions)
- Test: `repro/mi_matrix/plat_stubs_missing_xmod/`, `examples/z98/rogue_mud/`

**Context (I4):** 5 missing stubs (`plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`, `plat_console_putchar`, `plat_console_clear`), rogue_mud-only (ui.zig:11-14). 12 socket plat_ symbols already exist in net_runtime.c. zig0 fails identically (runtime gap, not compiler). This task closes the gap per the IB-report design.

- [ ] **Step 1:** Create `zig_pal_console.c` + `.h` (POSIX implementations + Win32 stubs) with the 5 functions
- [ ] **Step 2:** Add the 5 extern declarations to `std_pal.zig` (+ `zig_pal.h`)
- [ ] **Step 3:** Build + verify: `plat_stubs_missing_xmod` repro links rc=0 (with zig_pal_console.c linked); rogue_mud dump rc=0, gcc compile rc=0, **link rc=0** (previously failed on 5 undefined refs)
- [ ] **Step 4:** Update QUICK_REF.md gcc-link recipe if it must add `zig_pal_console.c` to the link line (or confirm zig_pal.c can host them instead — prefer NO recipe change: put the 5 functions INTO `zig_pal.c` if that keeps the existing link command unchanged)
- [ ] **Step 5:** Update tech docs + NOTES.md (deferred → fixed)
- [ ] **Step 6:** 4 MD5 gates (mud_server/rogue_mud not MD5-gated — verify all 4 unchanged)
- [ ] **Step 7:** Commit

**Gate:** `plat_stubs_missing_xmod` + rogue_mud link rc=0 (standard recipe, no recipe change if possible); 4 MD5s verified.

---

### Task F-B6: Gate sweep + docs reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v29 — std-lib plan closeout: json_parser + json_parser_workaround + rogue_mud + extern_runtime_symbol_xmod + plat_stubs_missing_xmod all clear)
- Modify: `docs/sf/QUICK_REF.md` (corpus baseline + MD5 table)
- Modify: `sf/docs/tech_docs/00_shared_infra.md`, `08_c89_emission.md` (final line-ref verification)

**Interfaces:**
- Consumes: F-B1..F-B5, all 21 examples, all repros.
- Produces: final manifest reflecting post-std-lib corpus state.

- [ ] **Step 1:** Run full 21-example matrix
- [ ] **Step 2:** Verify 4 MD5 gates
- [ ] **Step 3:** Verify test_analyzer_bin PASS
- [ ] **Step 4:** Update EXPECTED_FAIL.md v29 (deferred items cleared)
- [ ] **Step 5:** Update QUICK_REF.md baseline
- [ ] **Step 6:** Final tech doc line-ref verification
- [ ] **Step 7:** Commit

**Gate:** 21-example matrix recorded (json_parser, json_parser_workaround, rogue_mud now OK); 4 MD5 gates verified; test_analyzer_bin PASS; manifest + QUICK_REF + tech docs consistent.
