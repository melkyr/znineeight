# Multi-Module Emission Defects + Arena Self-Compile Fixes Design Spec

**Date:** 2026-08-08
**Status:** Approved by operator. Ready for plan.

## 1. Goal

Fix all known multi-module C89 emission defects so every z98 example compiles end-to-end (dump → gcc → run) via `--dump-c89 --output-dir DIR`. Then resize the static arenas to enable zig1 self-compile within the 16 MB hardware limit.

## 2. Problem Statement

A full 21-example compilation matrix (MEM4, `.superpowers/sdd/MEM4-full-example-matrix.md`) found:

- **16/21 examples work end-to-end** (12 FULL OK + 4 WARN OK)
- **5 examples don't pass the full cycle** — 1 dump fail, 3 gcc fail, 1 server (already functional with timeout)

The 5 gaps fall into 3 compiler defect areas + 1 platform-stub gap:

| # | Defect | Examples affected | Symptom |
|---|---|---|---|
| D1 | `@ptrToInt` returns void | lisp_interpreter (dump rc=2) | `error[3000]: cannot declare variable of type void` |
| D2 | Modules silently dropped from emission | json_parser (no arena.c), rogue_mud (scenario.c emitted but symbols unresolved) | gcc link: undefined references to module functions |
| D3 | Missing type forward-decls in headers | json_parser_workaround (6× zT_xx undeclared) | gcc compile: `'zT_NN' undeclared` |
| D4 | Missing platform stubs | rogue_mud (plat_is_windows, plat_console_*) | Link failure — `net_runtime.c` doesn't have console stubs |

The single-file emission path is solid (14/14 single-file examples pass). The gaps are all in the multi-module path.

Additionally, zig1 self-compile is blocked by the 1.5 MB static module arena (allocator.zig:75) which OOMs during `phase_ImportResolution` on any file >~1,500 lines. The module arena holds all modules' ASTs simultaneously and is never reset. The compiler source (35,316 lines across 37 modules) needs ~16–30 MB of module-arena capacity (MEM1/MEM3 reports).

## 3. Architecture

**Phase 1 — R (repros):** One task creates 4 multi-module repros exercising each defect + writes rogue_mud NOTES.md with the full build recipe.

**Phase 2 — I (investigation):** 5 batched I-tasks investigate each defect + arena sizing. Each updates the relevant tech doc. Combined STOP for operator ruling before any fix.

**Phase 3 — F (fixes):** F-tasks implement fixes per operator ruling. Arena resize (F5) at the end. F6 gate sweep reconciles the full matrix.

## 4. Tasks

### 4.1 R1 — Multi-module repros + rogue_mud NOTES.md

Create 4 multi-module repros and the rogue_mud status document. All repros use `--dump-c89 --output-dir DIR` (multi-module path). Pre-validated against zig0 oracle where applicable.

#### R1a: @ptrToInt void — `ptr_to_int_void_xmod/`

- `lib.zig`: function `fn getPtrAddr(ptr: [*]u8) usize { return @ptrToInt(ptr); }`
- `main.zig`: imports lib, calls `getPtrAddr`, prints result
- Expected: dump rc≠0 with `error[3000]: cannot declare variable of type void` — or dump rc=0 but gcc fails on void-typed temp
- Oracle: zig0 compiles clean, `@ptrToInt` → `usize`

#### R1b: Silent module drop — `mod_silent_drop_xmod/`

- `lib_a.zig`: `pub fn helper() i32 { return 42; }`
- `lib_b.zig`: imports lib_a, `pub fn wrapper() i32 { return lib_a.helper(); }`
- `main.zig`: imports lib_b, calls `wrapper`, prints result
- Expected: `lib_a.c` NOT emitted (or emitted but function not visible) → gcc link: `undefined reference to zF_*_helper`
- Minimal version of json_parser arena.c and rogue_mud generateDungeon patterns

#### R1c: Missing type forward-decl — `zT_missing_fwd_xmod/`

- `types.zig`: `pub const Point = struct { x: i32, y: i32 };`
- `main.zig`: imports types, `fn printPoint(p: types_mod.Point) void { ... }`
- Expected: `zT_NN` typedef for Point missing from `main_*.h` → gcc compile: `'zT_NN' undeclared`
- Minimal version of json_parser_workaround zT_xx pattern

#### R1d: Platform stub gap — `plat_stubs_missing_xmod/`

- `console.zig`: `extern "c" fn plat_is_windows() bool; extern "c" fn plat_console_putchar(c: i32) void;`
- `main.zig`: imports console, calls `plat_is_windows` and `plat_console_putchar('X')`
- Expected: dump rc=0, gcc link: `undefined reference to plat_is_windows`, `plat_console_putchar`
- NOTES.md documents which plat_ symbols are in `net_runtime.c` (socket family — present) vs missing (console family)
- This repro feeds a future std-lib plan; NOT fixed in F-tasks

#### R1e: `examples/z98/rogue_mud/NOTES.md`

Write the build recipe and current status:
- Single-module recipe (`--dump-c89 > file` — merges all modules; gcc cc + link)
- Multi-module recipe (`--dump-c89 --output-dir DIR` — per-module .c; gcc compile + link)
- Current expected failure mode (link: plat_is_windows, plat_console_*, plus some module symbols unresolved)
- Error pattern description (which symbols, which modules affected)
- Classification: the plat_ symbols are platform-stub gap (tracked by D4); the module-symbol gaps are D2 (tracked by `mod_silent_drop_xmod` repro)

### 4.2 I1-I5 — Investigation tasks (batched, combined STOP)

Each I-task reads the compiler source, identifies the exact mechanism, writes a report to `.superpowers/sdd/`, and updates the relevant tech doc with `[updated: 2026-08-08]`. No compiler code changes.

#### I1: @ptrToInt void type resolution

- **Locus:** `sf/src/type_resolver.zig` or `sf/src/semantic_analyzer.zig` — intrinsic return type mapping
- **Tech doc:** `sf/docs/tech_docs/03_type_resolution.md`
- **Report:** `.superpowers/sdd/I-ptrtoint-void-report.md`

#### I2: Module silent drop in multi-module emission

- **Locus:** `sf/src/c89_emit.zig` — per-module .c file emission ordering/dependency tracking
- **Tech doc:** `sf/docs/tech_docs/08_c89_emission.md`
- **Report:** `.superpowers/sdd/I-silent-drop-report.md`

#### I3: Missing type forward-decls in multi-module headers

- **Locus:** `sf/src/c89_emit.zig` — header generation for modules that import types
- **Tech doc:** `sf/docs/tech_docs/08_c89_emission.md`
- **Report:** `.superpowers/sdd/I-missing-fwd-report.md`

#### I4: Platform stub gap catalog

- **Locus:** `sf/src/include/net_runtime.c`, `sf/src/include/zig_runtime.c`, `sf/src/include/zig_pal.c`
- **Tech doc:** none (runtime, not compiler). Report documents for future std-lib plan.
- **Report:** `.superpowers/sdd/I-platstub-gap-report.md`
- **Output:** table of existing plat_ symbols in each runtime file vs missing symbols needed by examples

#### I5: Arena sizing analysis for self-compile

- **Locus:** `sf/src/allocator.zig:74-76` (static arena buffers) + main.zig phase orchestration
- **Input:** MEM1/MEM2/MEM3 arena data, single-module OOM measurements, `sf/src/*.zig` file line counts
- **Tech doc:** `sf/docs/tech_docs/02_memory_budget.md` (if it exists) or `sf/docs/tech_docs/INDEX.md`
- **Report:** `.superpowers/sdd/I-arena-sizing-report.md`
- **Analysis:** compute minimum module-arena size to hold the single largest file's AST; compute the effect of adding `sandReset(&alloc.module)` after per-module emission (key architectural change: module arena becomes per-module, not cumulative); propose new arena sizes that fit within 16 MB; estimate self-compile RSS after resize

### 4.3 F1-F6 — Fix tasks (per operator ruling, after combined STOP)

Implemented after the operator rules on I1-I5 findings. Each fix is gated by the R1 repros + the 4 MD5 gate examples.

#### F1: Fix @ptrToInt type resolution

- **Per I1 ruling.** Expected: add `@ptrToInt` → `usize` mapping to intrinsic return-type table
- **Gate:** `ptr_to_int_void_xmod` dump rc=0, gcc rc=0, run rc=0. lisp_interpreter dump rc=0
- **Tech doc:** `03_type_resolution.md` updated to FIXED

#### F2: Fix module silent drop in emission

- **Per I2 ruling.** Expected: fix module-to-C-file dependency tracking so all referenced modules emit .c files
- **Gate:** `mod_silent_drop_xmod` all modules emit .c files, link rc=0. json_parser arena.c emitted. rogue_mud module symbols resolve (D2 part)
- **Tech doc:** `08_c89_emission.md` updated to FIXED

#### F3: Fix missing type forward-decls in headers

- **Per I3 ruling.** Expected: emit struct typedef forward-decls in importing module's header
- **Gate:** `zT_missing_fwd_xmod` zT_xx present in header, gcc compile rc=0. json_parser_workaround types resolve
- **Tech doc:** `08_c89_emission.md` updated to FIXED

#### F4: Platform stub gap documentation

- **NOT a compiler fix.** Document I4 findings in the repro NOTES.md + EXPECTED_FAIL.md. The `plat_stubs_missing_xmod` repro is OK-by-gate/latent (parallel to `opt_slice_null_return` precedent). Feeds a future std-lib plan.
- **Gate:** repro stays as known-gap, NOT counted as FAIL. rogue_mud NOTES.md updated with platform-stub gap note.

#### F5: Arena resize for self-compile

- **Per I5 analysis.** Resize static arenas in allocator.zig; add `sandReset(&alloc.module)` after per-module C89 emission in main.zig
- **Gate:** `sf/src/main.zig` dump-c89 no longer OOMs on module arena (import phase completes). The 4 MD5 gate examples byte-identical or re-baselined with runtime proof
- **Tech doc:** `02_memory_budget.md` (or index) updated with new arena sizes

#### F6: Gate sweep + full matrix reconciliation

- Re-run full 21-example matrix (MEM4). Verify F1–F5 fixes bring all compiler-defect examples to OK.
- Update EXPECTED_FAIL.md v28 + QUICK_REF.md baseline + all tech docs.
- rogue_mud NOTES.md final status: D2 resolved (module symbols), D4 remains (platform stubs out-of-scope).

## 5. Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — ⭐ SUBAGENT CHEAT-SHEET (lines 1-60). Copy exact commands; do not improvise flags.
- **Compiler under test:** `sf/build/out_release/zig1` (already built). Multi-module recipe: `mkdir -p DIR && zig1 --dump-c89 --output-dir DIR main.zig`
- **gcc compile recipe:** `-m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c *.c` then link with `zig_runtime.c zig_pal.c`. mud_server/rogue_mud also link `net_runtime.c`.
- **RUNTIME gates mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 and print expected output. Compile-only gates FORBIDDEN.
- **4 MD5 gates** byte-identical UNLESS operator-approved re-baseline with runtime proof (F-5 AMENDMENT B): mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `fad411835b9e0aaea165260fbdc6857c`, json `c403f0799dbc5c56d548eee07bb9eebd`.
- **Corpus:** 230 repros, OK=223/FAIL=3/gg=4 (231 dirs). FAIL must not increase.
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task updates the corresponding `sf/docs/tech_docs/*.md` — corrected line refs, `[updated: 2026-08-08]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present.
- **I-tasks report then STOP for combined operator ruling.** F-tasks do NOT start until the ruling.
- **D4 platform-stub gap is NOT a compiler bug** — documented as out-of-scope, feeds future std-lib plan. The `plat_stubs_missing_xmod` repro is OK-by-gate/latent.
- **Proven corpus precedent:** `comptime_neg_int` and `opt_slice_null_return` are OK-by-gate/type-incorrect, tracked separately in classification. The `plat_stubs_missing_xmod` repro follows this pattern.
- **rogue_mud NOTES.md** has the full single-module + multi-module build recipe, plus current expected failure mode. This is the long-lived status document.

## 6. Out of Scope

- **Windows console platform layer** — `plat_console_*` stubs are for a future std-lib plan, not this spec
- **Single-module emission fixes** — the single-file path is solid at 14/14
- **@ptrToInt sema/MIX coverage** — only the type-resolution void bug is in scope; the char_literal switch-case fix was done in the previous plan
- **rogue_mud full end-to-end gameplay** — only compile-to-link is in scope; the plat_ gap blocks linking, which is documented
- **0-FAIL corpus goal** — blocked by 2 std-lib-deferred FAILs + 1 C89 fundamental
- **std-lib implementation** — the platform-stub catalog feeds that plan, but isn't part of this one
