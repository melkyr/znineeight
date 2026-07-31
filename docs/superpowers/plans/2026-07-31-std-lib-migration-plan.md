# Bootstrap → Z98 Std Lib Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Research and implement a proper Z98 standard library (`std.zig`, `std_io.zig`, `std_net.zig`, `std_os.zig`) and migrate all examples away from `extern fn __bootstrap_*` declarations.

**Architecture:** One I-task (research + report) followed by one F-task (implementation). I-task inventories every bootstrap call site, designs the Z98 std API, maps PAL boundary, and orders the migration. F-task creates the std lib packages and migrates examples.

**Tech Stack:** Z98-compatible Z98, zig1 binary at `sf/build/out_release/zig1`, PAL C layer stays in `sf/src/include/zig_pal.c`.

## Global Constraints

- **PAL C layer stays** — `sf/src/include/zig_pal.c` keeps Win32/POSIX `#ifdef` for platform portability
- **Pure Z98 where possible** — format/itoa/mem helpers written in Z98, emitted as C89 by zig1
- **Extern C only at PAL boundary** — `std_pal.zig` is the single file declaring `extern "c" fn pal_*`
- **Corpus gate:** 184 repros, OK=176 FAIL=8 ICE=0 CRASH=0
- **Runtime gate:** all 18 Z98 examples build + link + run correctly
- **fastedit/edit only for source edits** — per AGENTS.md §X.7
- **Commit per task**
- **Follow QUICK_REF.md for build/run commands**
- **Plan says A, you do A** — STOP on ambiguity, present to operator

---

### Task I-B: Research bootstrap migration strategy

**Files:**
- Read: all 18 example `.zig` files, `sf/src/include/zig_runtime.c`, `sf/src/include/zig_pal.c`, `sf/src/pal.zig`
- Create: `.superpowers/sdd/IB-report.md` (research report)

**Research questions:**

1. **Bootstrap call site inventory.** Per example, per file, per `extern fn __bootstrap_*` declaration + call site counts. Map bootstrap functions to their PAL backing (e.g. `__bootstrap_print` → `pal_print_stdout`).

2. **Compiler's own I/O.** How does zig1 currently write diagnostics, markers, panic? (`pal.zig`, `extern_c.zig`). What must change for zig1 to use `const std = @import("std")` instead?

3. **PAL function inventory.** List every `pal_*` function in `zig_pal.c` and its Win32/POSIX branches. Which must be exposed to Z98 via `std_pal.zig`?

4. **Z98 std API design.** Exact function signatures for `std.io.print()`, `std.io.write()`, `std.net.listen()`, `std.os.sleep()`. Pure Z98 bodies for format/itoa/mem; extern C for PAL I/O.

5. **Bootstrap compatibility.** Can zig0 compile zig1 when zig1 `@import("std")` brings in `std_io.zig` which has `extern "c" fn pal_print_stdout`? Does zig0 handle multi-module compilation with `extern "c"` in imported modules?

6. **Migration order.** Which examples migrate first (simplest: hello, fibonacci, prime). Which need `std.net` (mud_server). per-example change count (file:line of each `extern fn` to replace).

**Steps:**
- [ ] **Step 1:** Grep all 18 examples for `__bootstrap_*` / `extern fn` — produce counts table per example
- [ ] **Step 2:** Read `sf/src/include/zig_pal.c` fully — inventory every PAL function + `#ifdef` branch
- [ ] **Step 3:** Read `sf/src/pal.zig` — compiler's own I/O, what must change
- [ ] **Step 4:** Test zig0 bootstrap: add `@import("std")` to a test zig1 module, verify zig0 compiles it
- [ ] **Step 5:** Write IB-report with bootstrap → Z98 mapping table, API signatures (file:line), migration order, Option A/B/C for PAL boundary placement
- [ ] **Step 6:** Commit empty checkpoint `bugfix: IB research report for bootstrap migration`

**Interfaces:**
- Produces: `IB-report.md` with bootstrap call site inventory, Z98 std API design, migration order per example, exact edit targets

---

### Task F-B: Implement Z98 std lib + migrate examples

**Files:**
- Create: `sf/src/std.zig`, `sf/src/std_io.zig`, `sf/src/std_pal.zig`, `sf/src/std_net.zig`, `sf/src/std_os.zig`
- Modify: all 18 example `.zig` files (replace `extern fn __bootstrap_*` with `@import("std")`)
- Modify: `sf/src/pal.zig` (migrate to `std.io` for compiler's own I/O)
- Modify: `sf/src/include/zig_runtime.c` (remove `__bootstrap_*` wrappers at lines 67-72)
- Update: all 18 `examples/z98/*/NOTES.md`

**Implementation per IB-report recommendations:**

- [ ] **Step 1:** Create Z98 std lib packages — `std.zig`, `std_io.zig`, `std_pal.zig`
- [ ] **Step 2:** Verify zig1 compiles using std (bootstrap gate: `bash sf/scripts/build_release.sh`)
- [ ] **Step 3:** Migrate compiler's own I/O — `pal.zig` → `std.io`
- [ ] **Step 4:** Migrate examples in IB-report order — one commit per category
- [ ] **Step 5:** Remove `__bootstrap_*` wrappers from runtime
- [ ] **Step 6:** Build + run all 18 examples
- [ ] **Step 7:** Corpus gate: 184 repros, 176/8/0/0
- [ ] **Step 8:** Update all 18 NOTES.md
- [ ] **Step 9:** Tech doc update: `00_shared_infra.md` (PAL section)
- [ ] **Step 10:** Report + commit `feat: FB Z98 std lib + bootstrap migration`
