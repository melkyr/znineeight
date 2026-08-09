# Bootstrap → Z98 Std Lib Migration + Compiler Builtins — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 20 compiler builtins (I/O, console, networking), create a pure-Z98 std lib (`std.zig`, `std_io.zig`, `std_arena.zig`) built on them, migrate all 21 examples off `__bootstrap_*` externs, and solve the deferred arena + plat-console gaps. Zero `extern "c"` in the std lib.

**Architecture:** 3 batched I-tasks (investigate zig_runtime.c, net_runtime.c, zig0 C++ PAL — each fills a questionnaire + updates tech docs) → combined STOP for operator ruling on the builtin catalog → Phase 1 F-tasks (core I/O + console builtins, arena, std lib + example migration, rogue_mud) → Phase 2 F-task (networking builtins + `std_net.zig`, porting net_runtime.c into the emitter and migrating mud_server + rogue_mud) → F7 gate sweep.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), zig1 (`sf/build/out_release/zig1`), zig0 oracle (`sf/build/zig0`), gcc -m32 C89, 21 examples, tech docs.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `sf/build/out_release/zig1`. Build: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: sf/build/out_release/zig1 ===`.
- **Bootstrap constraint:** zig1's own source (`sf/src/*.zig`) MUST stay unchanged and compiled by zig0 (which does NOT support the new builtins). Do NOT migrate `pal.zig`/`extern_c.zig` — they stay.
- **Compile recipe:** `mkdir -p DIR && sf/build/out_release/zig1 --dump-c89 --output-dir DIR <main.zig> 2>/tmp/err` (multi-module) or `--dump-c89 <FILE.zig> > /tmp/x.c` (single). gcc: `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c *.c` then link with `zig_runtime.c zig_pal.c` (+ `net_runtime.c` for socket examples).
- **RUNTIME gates mandatory** (AGENTS §2.5.3): every migrated example must run rc=0 AND print expected output. Compile-only gates are FORBIDDEN.
- **Corpus (2026-08-08):** manifest 230 repros OK=223/FAIL=3/gg=4; sweep 237 dirs OK=229/FAIL=8/ICE=0/CRASH=0. FAIL must not increase.
- **4 MD5 gates** byte-identical unless operator-approved re-baseline with runtime proof (AMENDMENT B): mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `a12f2fcebc30f2d8c2a148facb9d1174`, json `c403f0799dbc5c56d548eee07bb9eebd`.
- **Preprocessor-guarded C emission** for platform-dependent builtins: `#ifdef _WIN32` / `#elif defined(__WATCOMC__)` / `#else` (POSIX). `@isWindows` is comptime-folded, never emitted.
- **One LIR instruction per builtin** (backend-agnostic optimization).
- **I-tasks report then STOP for combined operator ruling** (all 3 I-tasks, one combined STOP) on the builtin catalog before F-tasks.
- **Phase 1 (F1-F5) must complete before Phase 2 (F6)** — networking builtins depend on the proven pattern from F1/F2.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present. On any issue, STOP.

---

## Phase 0 — Investigation

### Task I-RT: zig_runtime.c bootstrap inventory

**Files:**
- Investigate: `sf/src/include/zig_runtime.c`
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md`
- Report: `.superpowers/sdd/I-RT-bootstrap-report.md`

**Context:** `zig_runtime.c` holds the `__bootstrap_*` I/O wrappers (lines 67-72: print/print_int/print_char/panic/write/sleep_ms) + the cast-helper family (`__bootstrap_usize_from_i64`, `__bootstrap_i32_from_u32`, `__bootstrap_u32_from_u64`, `__bootstrap_u32_from_i32`, `__bootstrap_usize_from_i32`, `__bootstrap_i32_from_usize`, `__bootstrap_u8_from_usize`, etc.). The I/O wrappers become builtins; the cast helpers are the compiler's `@intCast` runtime and stay.

**Questionnaire:**

| Q | Investigate |
|---|---|
| Q1 | Inventory every `__bootstrap_*` function: name, signature, line. Classify: example-facing → proposed builtin; compiler-internal → stays as C helper. Exact file:line → builtin proposal table. |
| Q2 | Inventory every cast-helper. Which are called by zig1's self-compile (sf/src/) vs only by examples? |
| Q3 | How does `zig_runtime.c`'s approach differ from zig0's C++ PAL? (cross-reference I-PAL output) |
| Q4 | Which functions need `#ifdef` for msvc6/openwatcom/posix? Which are pure ISO C89? |
| Q5 | After builtin migration, what REMAINS in `zig_runtime.c`? List surviving functions. |
| Q6 | Update `07_lir_lowering.md`: bootstrap-to-builtin mapping table, `[updated: 2026-08-08]`. |

**Steps:**
- [ ] **Step 1:** Grep `zig_runtime.c` for `__bootstrap_` — full inventory with file:line + signature.
- [ ] **Step 2:** Classify each as example-facing (→ builtin) or compiler-internal (→ stays). For example-facing, propose the builtin signature.
- [ ] **Step 3:** Grep `sf/src/*.zig` + `examples/z98/` for each cast-helper call site — determine compiler vs example usage.
- [ ] **Step 4:** Assess `#ifdef` needs per function (msvc6/openwatcom/posix).
- [ ] **Step 5:** Update `07_lir_lowering.md` (bootstrap-to-builtin mapping + surviving-function list).
- [ ] **Step 6:** Write `.superpowers/sdd/I-RT-bootstrap-report.md`.
- [ ] **Step 7:** Commit `bugfix: I-RT bootstrap inventory report`.

**Gate:** every `__bootstrap_*` categorized; builtin proposals with signatures; surviving C functions listed; tech doc updated; no compiler source changes.

---

### Task I-NET: net_runtime.c socket inventory

**Files:**
- Investigate: `sf/src/include/net_runtime.c`
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Report: `.superpowers/sdd/I-net-report.md`

**Context:** `net_runtime.c` holds the 12 `plat_socket_*` functions used by mud_server. These become the Phase 2 networking builtins.

**Questionnaire:**

| Q | Investigate |
|---|---|
| Q1 | Inventory every `plat_socket_*` function: name, signature, line. Map each to proposed builtin. |
| Q2 | What `#ifdef`/`#pragma` patterns exist for msvc6 (`#pragma comment(lib, "ws2_32")`), openwatcom, POSIX? Exact per-function branching. |
| Q3 | How does zig0's C++ PAL handle sockets? (cross-reference I-PAL). What to copy? What to improve? |
| Q4 | After builtin migration, does `net_runtime.c` go away or stay (as reference / for zig0)? |
| Q5 | Update `08_c89_emission.md`: networking builtins + `#ifdef` emission pattern, `[updated: 2026-08-08]`. |

**Steps:**
- [ ] **Step 1:** Grep `net_runtime.c` for `plat_` — full inventory with file:line + signature.
- [ ] **Step 2:** Catalog the `#ifdef`/`#pragma` patterns per platform (msvc6, openwatcom, POSIX).
- [ ] **Step 3:** Map each function to a proposed builtin signature.
- [ ] **Step 4:** Assess: does `net_runtime.c` stay (reference/zig0) or go away post-migration?
- [ ] **Step 5:** Update `08_c89_emission.md`.
- [ ] **Step 6:** Write `.superpowers/sdd/I-net-report.md`.
- [ ] **Step 7:** Commit `bugfix: I-NET socket inventory report`.

**Gate:** every socket function mapped to builtin; platform patterns cataloged; tech doc updated; no compiler source changes.

---

### Task I-PAL: zig0 C++ PAL study

**Files:**
- Investigate: zig0 bootstrap compiler's C++ PAL source (locate it — check `sf/build/zig0` dependencies, any C++ source dir for the bootstrap compiler)
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md`
- Report: `.superpowers/sdd/I-pal-report.md`

**Context:** The bootstrap compiler (zig0) was written in C++ and has its own PAL layer that "got the C right" for multiple platforms (Win32, POSIX). We study it to copy proven patterns or do better.

**Questionnaire:**

| Q | Investigate |
|---|---|
| Q1 | Locate the zig0 C++ PAL source. What files? What API surface (putchar, write, sockets, console, sleep)? |
| Q2 | How does zig0 abstract Win32 vs POSIX? Compile-time `#ifdef`? Runtime dispatch? |
| Q3 | What did zig0 get RIGHT that we should copy? (pattern, function signature, `#ifdef` style) |
| Q4 | What can we do BETTER? (simpler abstraction, fewer `#ifdef` levels, comptime folding, Z98 advantage) |
| Q5 | How does zig0's PAL relate to `zig_runtime.c` and `net_runtime.c`? Did we inherit or rewrite from zig0? |
| Q6 | Update `00_shared_infra.md`: PAL architecture + how builtins improve it, `[updated: 2026-08-08]`. |

**Steps:**
- [ ] **Step 1:** Locate zig0 PAL source (search `sf/` and repo for the bootstrap C++ source, e.g. `grep -rl "class.*Pal\|pal_" --include="*.cpp"` or the zig0 build dir).
- [ ] **Step 2:** Catalog the PAL API surface (functions, signatures, file:line).
- [ ] **Step 3:** Analyze the platform abstraction strategy (compile-time vs runtime vs comptime).
- [ ] **Step 4:** Write the copy-vs-improve analysis.
- [ ] **Step 5:** Update `00_shared_infra.md`.
- [ ] **Step 6:** Write `.superpowers/sdd/I-pal-report.md`.
- [ ] **Step 7:** Commit `bugfix: I-PAL bootstrap PAL study report`.

**Gate:** zig0 PAL surface cataloged; copy-vs-improve analysis; tech doc updated; no compiler source changes.

**→ Report back after all 3 I-tasks for the combined STOP. F-tasks do NOT start until the operator rules on the builtin catalog.**

---

## Phase 1 — Core

### Task F1: Core I/O builtins (6)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (intrinsic table: `@putChar`, `@stdoutWrite`, `@stderrWrite`, `@getChar`, `@exit`, `@sleepMs`)
- Modify: `sf/src/lower.zig` (6 LIR instructions: `.builtin_put_char`, `.builtin_stdout_write`, `.builtin_stderr_write`, `.builtin_get_char`, `.builtin_exit`, `.builtin_sleep_ms`)
- Modify: `sf/src/lir.zig` (LirInst union — new builtin variants live here)
- Modify: `sf/src/parser.zig` (zero-arg builtin call parse fix — F1 found `@getChar()` was a pre-existing error[2000] gap)
- Modify: `sf/src/c89_emit.zig` (C emission per builtin; `#ifdef` for `@sleepMs`)
- Create: `repro/mi_matrix/io_builtin_test/main.zig` + `NOTES.md`
- Modify (docs): `sf/docs/tech_docs/05_semantic_analysis.md`, `07_lir_lowering.md`, `08_c89_emission.md`
- Report: `.superpowers/sdd/task-F1-builtin-report.md`

**Interfaces:**
- Consumes: I-RT + I-PAL reports (exact builtin signatures + `#ifdef` patterns).
- Produces: 6 builtins callable from Z98; the LIR instructions F4's std_io.zig will use.

**Emission (per I-PAL/I-RT — exact bodies from the reports):**

- [ ] **Step 1: Verify the intrinsic mechanism.** Read how existing intrinsics (`@ptrToInt`, `@intCast`, `@sizeOf`) are resolved in `semantic_analyzer.zig` (search `name_id` + intrinsic dispatch) and lowered in `lower.zig`. This is the pattern to follow. Record the mechanism in the report.
- [ ] **Step 2: Write the failing test.** Create `repro/mi_matrix/io_builtin_test/main.zig` exercising all 6 builtins:
```zig
extern fn __bootstrap_print_int(n: i32) void;
pub fn main() void {
    @putChar(@intCast(u8, 'H'));
    @putChar(@intCast(u8, 'i'));
    @stdoutWrite("Hello", 5);
    @stderrWrite("ERR", 3);
    __bootstrap_print_int(@intCast(i32, @getChar()));
    @exit(@intCast(u8, 0));
}
```
(adjust to the actual builtin syntax the compiler expects — the exact `@`-name + arg syntax comes from the intrinsic mechanism in Step 1). Run: dump rc=0 expected (RED — builtins not yet known).
- [ ] **Step 3: Implement sema entries.** Add the 6 intrinsics to the intrinsic-name table with correct signatures (per I-RT). `@exit` is noreturn. Verify types: `@putChar(u8)→void`, `@stdoutWrite([*]const u8, usize)→void`, `@stderrWrite([*]const u8, usize)→void`, `@getChar()→u8`, `@exit(u8)→noreturn`, `@sleepMs(u32)→void`.
- [ ] **Step 4: Implement lowerer LIR.** Add 6 LIR instruction variants (one per builtin). Lower each intrinsic call to its instruction with operand temps.
- [ ] **Step 5: Implement C89 emission.** Add emission for each LIR inst: `putchar(c);` / `fwrite(buf, 1, len, stdout);` / `fwrite(buf, 1, len, stderr);` / `getchar();` / `exit(code);` / `#ifdef`-guarded sleep. Verify no `#ifdef` needed for the 5 ISO-C89 ops.
- [ ] **Step 6: Build + verify.** Rebuild zig1. Run `io_builtin_test/`: dump rc=0, gcc rc=0, run rc=0. Verify expected output (H, i, Hello on stdout, ERR on stderr, getchar echo, exit 0).
- [ ] **Step 7: Update tech docs.** `05` (intrinsic table), `07` (LIR insts), `08` (emission) — `[updated: 2026-08-08]`.
- [ ] **Step 8: Commit.**
```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig sf/src/c89_emit.zig repro/mi_matrix/io_builtin_test/ sf/docs/tech_docs/05_semantic_analysis.md sf/docs/tech_docs/07_lir_lowering.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "feat: core I/O builtins (putChar, stdoutWrite, stderrWrite, getChar, exit, sleepMs)"
```

**Gate:** 6/6 builtins dump→gcc→run rc=0; correct output; tech docs updated.

---

### Task F2: Console builtins (4)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (`@isWindows` comptime, `@consoleClear`, `@consoleGotoxy`, `@consoleSetColor`)
- Modify: `sf/src/lower.zig` (4 LIR instructions)
- Modify: `sf/src/lir.zig` (LirInst union — new builtin variants live here)
- Modify: `sf/src/c89_emit.zig` (C emission with `#ifdef`)
- Create: `repro/mi_matrix/console_builtin_test/main.zig` + `NOTES.md`
- Modify (docs): same 3 tech docs
- Report: `.superpowers/sdd/task-F2-builtin-report.md`

**Interfaces:**
- Consumes: F1 (the builtin mechanism), I-PAL (platform patterns).
- Produces: 4 console builtins; `@isWindows` comptime-foldable.

**Emission (per I-PAL):**

- [ ] **Step 1: Implement `@isWindows` (comptime).** In sema: intrinsic returns TYPE_BOOL and comptime-unfolds to `true_literal(0)` (POSIX) or `true_literal(1)` (Win32) based on the compiler's target flag. Verify `if (@isWindows()) {...} else {...}` folds to only the active branch in emitted C.
- [ ] **Step 2: Write the failing test.** `console_builtin_test/main.zig`: call `@consoleClear()`, `@consoleGotoxy(5, 3)`, `@consoleSetColor(32, 40)`, `@isWindows()` in an `if`. Run: dump rc=0 (RED).
- [ ] **Step 3: Implement the 3 non-comptime builtins.** sema entries + 3 LIR insts + C89 emission (`#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else / #endif` per the catalog).
- [ ] **Step 4: Build + verify.** Rebuild zig1. Run `console_builtin_test/`: dump/gcc/run rc=0. Verify emitted C has the ANSI/POSIX branch (POSIX build) and `#ifdef` guards present.
- [ ] **Step 5: Update tech docs.** `[updated: 2026-08-08]`.
- [ ] **Step 6: Commit.**
```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig sf/src/c89_emit.zig repro/mi_matrix/console_builtin_test/ sf/docs/tech_docs/05_semantic_analysis.md sf/docs/tech_docs/07_lir_lowering.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "feat: console builtins (isWindows comptime, consoleClear, consoleGotoxy, consoleSetColor)"
```

**Gate:** 4/4 builtins dump→gcc→run rc=0; `@isWindows` comptime-folds (only active branch in C); tech docs updated.

---

### Task F3: std_arena.zig + json_parser migration

**Files:**
- Create: `sf/src/std_arena.zig`
- Modify: `examples/z98/json_parser/json.zig`, `file.zig`; `examples/z98/json_parser_workaround/json.zig`, `file.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (json_parser + json_parser_workaround cleared)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md` (arena extern note), example NOTES.md
- Test: `repro/mi_matrix/extern_runtime_symbol_xmod/`, `examples/z98/json_parser/`, `examples/z98/json_parser_workaround/`
- Report: `.superpowers/sdd/task-F3-arena-report.md`

**Interfaces:**
- Consumes: I2 report (`.superpowers/sdd/I-orphan-module-report.md` — arena_alloc_default analysis).
- Produces: `std.arena` module; json_parser + json_parser_workaround link + run with standard runtime.

**Context (I2):** `arena_alloc_default` extern (json.zig:253, file.zig:25) declared `zig_runtime.h:21-22`, defined ONLY in legacy `src/runtime/zig_runtime.c:154-156`. The legacy arena functions: `arena_create(initial_capacity)`, `arena_alloc(a, size)`, `arena_reset(a)`, `arena_destroy(a)`, `arena_alloc_default(size)`, `arena_free(ptr)` (src/runtime/zig_runtime.c:71-158).

- [ ] **Step 1: Write `std_arena.zig`.** Pure Z98 bump allocator mirroring the legacy semantics:
```zig
pub const Arena = struct {
    data: [*]u8,
    capacity: usize,
    used: usize,
};
pub fn create(initial_capacity: usize) Arena {
    // allocate via a fixed static buffer or the Z98 approach for a [*]u8
    // (follow the compiler's existing global/heap pattern — see how other
    //  examples allocate memory, or use a static array)
}
pub fn alloc(self: *Arena, size: usize) ?[*]u8 {
    // bump: if used+size <= capacity, return data+used and advance; else null
}
pub fn reset(self: *Arena) void { self.used = 0; }
```
(Exact allocator body depends on how the codebase provides raw memory — the implementer must verify against an existing example that allocates, e.g. heapsort or lzw, and follow that pattern. The Z98 API is `std.arena.create/alloc/reset`.)
- [ ] **Step 2: Write the failing test.** `extern_runtime_symbol_xmod/` is the gate (currently link rc=1 on `arena_alloc_default`). RED.
- [ ] **Step 3: Migrate json_parser + json_parser_workaround.** Replace `extern "c" fn arena_alloc_default` with `const std = @import("std");` + `std.arena.alloc(...)`. Update all call sites.
- [ ] **Step 4: Build + verify.** Rebuild zig1. `extern_runtime_symbol_xmod/` links rc=0 (standard runtime, no legacy file). json_parser + json_parser_workaround link rc=0 + run rc=0.
- [ ] **Step 5: Update EXPECTED_FAIL.md + NOTES.md** (deferred → fixed).
- [ ] **Step 6: Verify 4 MD5 gates.** json likely unchanged (emitted C — verify; re-baseline with runtime proof only if changed).
- [ ] **Step 7: Commit.**
```bash
git add sf/src/std_arena.zig examples/z98/json_parser/ examples/z98/json_parser_workaround/ repro/mi_matrix/EXPECTED_FAIL.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "feat: std.arena bump allocator + json_parser migration (deferred gap closed)"
```

**Gate:** `extern_runtime_symbol_xmod` + json_parser + json_parser_workaround link rc=0 with STANDARD runtime; run rc=0; EXPECTED_FAIL cleared; 4 MD5s verified.

---

### Task F4: std.zig + std_io.zig + migrate all 21 examples

**Files:**
- Create: `sf/src/std.zig`, `sf/src/std_io.zig`
- Modify: all 21 example `.zig` files (replace `extern fn __bootstrap_*` with `@import("std")`)
- Modify: `sf/src/include/zig_runtime.c` (remove dead `__bootstrap_*` I/O wrappers, keep cast helpers)
- Modify: all 21 `examples/z98/*/NOTES.md`
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md`, `07_lir_lowering.md`, `08_c89_emission.md`
- Report: `.superpowers/sdd/task-F4-stdlib-report.md`

**Interfaces:**
- Consumes: F1-F3 (builtins + arena), I-RT (bootstrap→builtin map).
- Produces: the std lib surface; all examples compiled off `__bootstrap_*`.

**Per I-RT mapping (exact per-example changes from the report).**

- [ ] **Step 1: Create `std.zig`.** Root package: `pub const io = @import("std_io.zig"); pub const arena = @import("std_arena.zig");` (+ os/net as they exist).
- [ ] **Step 2: Create `std_io.zig`.** `print`, `write`, `readByte`, `writeByte` using the builtins (F1):
```zig
pub const Writer = struct { /* write_fn via @stderrWrite or @putChar */ };
pub fn writeByte(self: *Writer, c: u8) void { @putChar(c); }
pub fn write(self: *Writer, data: []const u8) void {
    @stderrWrite(data.ptr, data.len);
}
```
(Exact API per I-RT's bootstrap→builtin map + the format/itoa helpers the examples use.)
- [ ] **Step 3: Migrate single-file examples.** hello, fibonacci, prime, mandelbrot, days_in_month, func_ptr_return, heapsort, quicksort, sort_strings, tco_factorial, tco_defer, tco_return_try. Replace each `extern fn __bootstrap_print*` with `const std = @import("std");` + `std.io.…`. One commit.
- [ ] **Step 4: Migrate multi-module examples.** game_of_life, lzw, lisp_interpreter, lisp_interpreter_adv, lisp_interpreter_curr, json_parser, json_parser_workaround. One commit.
- [ ] **Step 5: Migrate networking examples.** mud_server, rogue_mud — via std.io + (F5 for rogue_mud console, F6 for mud_server sockets). Verify mud_server keeps working (externs to net_runtime.c may stay until F6). One commit.
- [ ] **Step 6: Remove dead `__bootstrap_*` I/O wrappers** from `zig_runtime.c:67-72` (print/print_int/print_char/panic/write/sleep_ms — the example-facing ones per I-RT). KEEP the cast helpers.
- [ ] **Step 7: Build + verify all 21 examples.** Each dump rc=0, gcc rc=0, run rc=0 with expected output.
- [ ] **Step 8: Verify 4 MD5 gates.** Byte-identical unless re-baselined with runtime proof.
- [ ] **Step 9: Update all NOTES.md + tech docs.**
- [ ] **Step 10: Commit.** One commit per category (single-file, multi-module, net) + the runtime cleanup.

**Gate:** all 21 examples build + link + run; zero `__bootstrap_*` in example sources; `zig_runtime.c` cleaned (cast helpers remain); 4 MD5s verified; NOTES.md updated.

---

### Task F5: rogue_mud console migration

**Files:**
- Modify: `examples/z98/rogue_mud/ui.zig` (plat_console_* + plat_is_windows externs → console builtins)
- Modify: `examples/z98/rogue_mud/NOTES.md` (deferred → fixed)
- Modify: `repro/mi_matrix/plat_stubs_missing_xmod/NOTES.md` + `repro/mi_matrix/EXPECTED_FAIL.md` (cleared)
- Report: `.superpowers/sdd/task-F5-rogue-report.md`

**Interfaces:**
- Consumes: F2 (console builtins), F4 (std.io migration).
- Produces: rogue_mud links + runs with standard recipe.

**Context (I4):** 5 missing stubs (`plat_is_windows`, `plat_console_gotoxy/setcolor/putchar/clear`) at `ui.zig:11-14`. F2's builtins now provide all 5 (`@isWindows` + `@console*` + `@putChar`).

- [ ] **Step 1: Migrate `ui.zig`.** Replace the 5 bare externs with the console builtins (or `std.io`/`std.console` wrapper per F4's std lib). Update all call sites in rogue_mud modules.
- [ ] **Step 2: Build + verify.** Rebuild zig1. `plat_stubs_missing_xmod/` links rc=0 (standard recipe). rogue_mud dump rc=0, gcc rc=0, **link rc=0** (previously failed on 5 undefined refs), run rc=0 (server boots / console functions work — use `timeout 5` for the server loop).
- [ ] **Step 3: Update NOTES.md + EXPECTED_FAIL.md** (deferred → fixed).
- [ ] **Step 4: Verify 4 MD5 gates.**
- [ ] **Step 5: Commit.**
```bash
git add examples/z98/rogue_mud/ repro/mi_matrix/plat_stubs_missing_xmod/NOTES.md repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "feat: rogue_mud console builtins migration (deferred gap closed)"
```

**Gate:** `plat_stubs_missing_xmod` + rogue_mud link rc=0 standard recipe; run rc=0; EXPECTED_FAIL cleared; 4 MD5s verified.

---

## Phase 2 — Networking

### Task F6: Networking builtins (11) + std_net.zig + net_runtime.c port

**Files:**
- Modify: `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig` (11 builtins: socketCreate, socketBindListen, socketAccept, socketConnect, socketSend, socketRecv, socketSelect, socketFdZero, socketFdSet, socketFdIsset, socketClose)
- Create: `sf/src/std_net.zig` (Z98 wrappers over the 11 builtins — pure Z98, zero `extern "c"`)
- Modify: `examples/z98/mud_server/main.zig`, `examples/z98/rogue_mud/lib/net.zig` (+ any callers) — migrate off `plat_*` externs to `std_net`
- Create: `repro/mi_matrix/net_builtin_test/main.zig` + `NOTES.md` (or verify mud_server directly)
- Modify (docs): `08_c89_emission.md`
- Report: `.superpowers/sdd/task-F6-net-report.md`

**Interfaces:**
- Consumes: I-NET + I-PAL reports (exact socket `#ifdef` patterns + net_runtime.c function bodies), F1 (the builtin mechanism), operator ruling m0572 (std_net.zig required — net_runtime.c must be PORTED, not just wrapped).
- Produces: 11 networking builtins whose C89 emitter output REPLACES net_runtime.c (the emitter embeds the socket C bodies inline, `#ifdef`-guarded); `std_net.zig` library; mud_server + rogue_mud migrated off `plat_*` externs.

**Emission:** per I-NET/I-PAL exact per-platform bodies — the builtin C89 emission PORTs the 12 `plat_*` function bodies from `sf/src/include/net_runtime.c` into the emitter's `#ifdef _WIN32` / `#elif defined(__WATCOMC__)` / `#else` (POSIX) blocks. `socketConnect` is NEW C code (no source exists — both examples are servers; add the Win32/POSIX `connect()` body per the operator ruling, needed for future clients/telnet). The `fd` type is `i32` (arch-independence ruling m0544).

- [ ] **Step 1: Implement the 11 builtins.** sema entries + 11 LIR insts + C89 emission. The emitted C bodies are PORTED from `sf/src/include/net_runtime.c:18-153` (the 12 existing `plat_*` functions) into the `#ifdef`-guarded emitter blocks, plus the NEW `socketConnect` body (Win32: `connect(sock, (struct sockaddr*)&addr, sizeof(addr))`; POSIX: same libc call) — thin wrapper matching the existing pattern. Verify against the I-NET table.
- [ ] **Step 2: Create `std_net.zig`.** Z98 wrappers: `init`, `cleanup`, `createTcpServer(port)`, `bindListen(fd, backlog)`, `accept(fd)`, `connect(fd, port)`, `send(fd, buf, len)`, `recv(fd, buf, len)`, `close(fd)`, `select(...)`, `fdZero(s)`, `fdSet(fd, s)`, `fdIsset(fd, s)` — using the 11 builtins. Zero `extern "c"`.
- [ ] **Step 3: Migrate mud_server + rogue_mud** to `std_net`. Replace the `extern "c" fn plat_*` declarations in `examples/z98/mud_server/main.zig` and `examples/z98/rogue_mud/lib/net.zig` with `const std_net = @import("std_net.zig");` calls. **net_runtime.c link is REMOVED for migrated examples** — the builtin-emitted C replaces it.
- [ ] **Step 4: Build + verify.** `net_builtin_test/` (or mud_server): dump/gcc/link/run rc=0 WITHOUT linking net_runtime.c. For mud_server: `timeout 5` server boot + socket client interaction (use `sf/build/out_release/zig1` to compile; client via bash `/dev/tcp` or a small test client). For rogue_mud: dump/gcc/link rc=0 (5 `plat_*` undefined refs GONE).
- [ ] **Step 5: Update tech docs + NOTES.md.**
- [ ] **Step 6: Verify 4 MD5 gates.**
- [ ] **Step 7: Commit.**
```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig sf/src/c89_emit.zig sf/src/std_net.zig repro/mi_matrix/net_builtin_test/ examples/z98/mud_server/ examples/z98/rogue_mud/lib/net.zig sf/docs/tech_docs/08_c89_emission.md
git commit -m "feat: networking builtins + std_net.zig (port net_runtime.c into emitter, migrate mud_server+rogue_mud)"
```

**Gate:** networking builtins dump→gcc→run rc=0 WITHOUT net_runtime.c in the link; mud_server compiles + links + runs (timeout-gated socket interaction); rogue_mud compiles + links rc=0 with the 5 `plat_*` undefined refs GONE; `std_net.zig` has zero `extern "c"`; 4 MD5s verified.

---

## Closeout

### Task F7: Gate sweep + full matrix reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v29 — std-lib plan closeout)
- Modify: `docs/sf/QUICK_REF.md` (corpus baseline + MD5 table + gcc recipe if changed)
- Modify: `sf/docs/tech_docs/00_shared_infra.md`, `05_semantic_analysis.md`, `07_lir_lowering.md`, `08_c89_emission.md` (final line-ref verification)
- Report: `.superpowers/sdd/task-F7-sweep-report.md`

**Interfaces:**
- Consumes: F1-F6, all 21 examples, all repros.
- Produces: final manifest reflecting post-builtin corpus state.

- [ ] **Step 1: Run full 21-example matrix.**
- [ ] **Step 2: Verify 4 MD5 gates.**
- [ ] **Step 3: Verify test_analyzer_bin PASS.**
- [ ] **Step 4: Update EXPECTED_FAIL.md v29** (json_parser, json_parser_workaround, rogue_mud cleared).
- [ ] **Step 5: Update QUICK_REF.md baseline.**
- [ ] **Step 6: Final tech doc line-ref verification.**
- [ ] **Step 7: Commit.**

**Gate:** 21-example matrix (all OK — no gcc-FAIL or link-deferred remain except documented std-lib items); 4 MD5s verified; test_analyzer_bin PASS; manifest + QUICK_REF + tech docs consistent.

---

## Arch Independence (AMENDMENT 2026-08-08 — operator ruling)

**Design principle:** Z98 types abstract the architecture. The std lib source and the builtin signatures use Z98 types (`usize`, `u8`, `u32`, `i32`); the C89 emitter maps them to target C types per-arch. Arch width decisions live in the EMITTER, never in Z98 source.

| Layer | Arch-independent? | Where arch mapping happens |
|---|---|---|
| Std lib Z98 code (`std_io.zig`, `std_arena.zig`) | ✅ — uses `usize`/`u8`/`[]u8` | Compiler type mapper |
| Builtin Z98 signatures (catalog) | ✅ — use Z98 types (`u32`, `i32`, `usize`) | Compiler type mapper |
| C89 emission for each builtin | Per-arch — format strings, `int`/`long`/`size_t` mapping | The `.builtin_*` emit function in `c89_emit.zig` |
| Socket fd type (`i32`) | **Correct as `i32`** (operator ruling) | C89 emission maps `i32`→`int`; 16-bit fd truncation is a 16-bit-emission concern |

**16-bit compatibility is explicitly FUTURE work.** The operator's ruling: `i32` is correct for the builtin catalog. 16-bit targets are a problem for 16-bit *emission*, which is far in the future (likely after the zig0 bootstrap chain is long gone). The current architecture (Z98 types → C89 emitter per-arch mapping) is 16-bit-compatible in structure — no size assumptions in std lib source — but no 16-bit emission work is done here. The `#ifdef` catalog covers msvc6/openwatcom/posix only.

---

## Post-Plan

- **Self-hosted evolution (zig1.5 → zig2):** migrate zig1's own source to `@import("std")` — gated on zig1 self-compile (arena F5 scratch-arena OOM is the blocker). zig0 retires.
- **`zig_pal.c` reduction:** once builtins cover everything, shrink/remove `zig_pal.c` (bootstrap reference only).
- **Additional backends (LLVM IR, WASM, x86, 16-bit):** the one-LIR-per-builtin design lets each backend lower builtins independently. `@isWindows` comptime-fold adapts per target.
- **16-bit compatibility:** std lib makes no size assumptions (per the builtin catalog); actual 16-bit emission is future work.
