# Multi-Module Emission Defects + Arena Self-Compile Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 3 multi-module C89 emission defects + the @ptrToInt void bug so all 21 z98 examples compile end-to-end, then resize arenas for zig1 self-compile within 16 MB.

**Architecture:** R1 (4 multi-module repros + rogue_mud NOTES.md) → I1-I5 batched investigation (each updates tech docs) → combined STOP for operator ruling → F1-F6 fixes + arena resize → F6 gate sweep.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), zig1 (`sf/build/out_release/zig1`), zig0 oracle (`sf/build/zig0`), gcc -m32 C89, repro battery (existing + 4 new), tech docs (`sf/docs/tech_docs/*.md`).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `sf/build/out_release/zig1` (already built). Multi-module recipe: `mkdir -p DIR && zig1 --dump-c89 --output-dir DIR main.zig`. Single-module: `zig1 --dump-c89 main.zig > /tmp/x.c`.
- **gcc compile recipe:** `cd DIR && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog`. mud_server/rogue_mud also link `net_runtime.c`.
- **RUNTIME gates mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 AND print the expected output. Compile-only gates are FORBIDDEN.
- **4 MD5 gates:** mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `fad411835b9e0aaea165260fbdc6857c`, json `c403f0799dbc5c56d548eee07bb9eebd` — byte-identical UNLESS operator-approved re-baseline with runtime proof (F-5 AMENDMENT B).
- **Corpus:** 230 repros, OK=223/FAIL=3/gg=4 (231 dirs). FAIL must not increase. The 4 new repros are OK-by-compile/runtime-gap-tracked (NOT added to FAIL).
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task MUST update the corresponding `sf/docs/tech_docs/*.md` — corrected line refs, descriptions, `[updated: 2026-08-08]` annotation. Check INDEX.md Table A for the covering doc.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present. On any issue, STOP.
- **I-tasks report then STOP for combined operator ruling** (all 5 I-tasks, one combined STOP). F-tasks do NOT start until the ruling.
- **D4 platform-stub gap is NOT a compiler bug** — documented as out-of-scope. `plat_stubs_missing_xmod` repro stays OK-by-gate/latent.
- **rogue_mud NOTES.md** has the full single-module + multi-module build recipe plus expected failure mode.

---

### Task R1: Create multi-module repros + rogue_mud NOTES.md

**Files:**
- Create: `repro/mi_matrix/ptr_to_int_void_xmod/main.zig`, `repro/mi_matrix/ptr_to_int_void_xmod/lib.zig`, `repro/mi_matrix/ptr_to_int_void_xmod/NOTES.md`
- Create: `repro/mi_matrix/mod_silent_drop_xmod/main.zig`, `repro/mi_matrix/mod_silent_drop_xmod/lib_a.zig`, `repro/mi_matrix/mod_silent_drop_xmod/lib_b.zig`, `repro/mi_matrix/mod_silent_drop_xmod/NOTES.md`
- Create: `repro/mi_matrix/zT_missing_fwd_xmod/main.zig`, `repro/mi_matrix/zT_missing_fwd_xmod/types.zig`, `repro/mi_matrix/zT_missing_fwd_xmod/NOTES.md`
- Create: `repro/mi_matrix/plat_stubs_missing_xmod/main.zig`, `repro/mi_matrix/plat_stubs_missing_xmod/console.zig`, `repro/mi_matrix/plat_stubs_missing_xmod/NOTES.md`
- Create: `examples/z98/rogue_mud/NOTES.md`

**Interfaces:**
- Consumes: the z98 example compilation matrix (MEM4), the defect list from the design spec.
- Produces: 4 multi-module repros (each pre-validated against zig0 oracle where applicable) + rogue_mud documentation.

- [ ] **Step 1: Create R1a — `ptr_to_int_void_xmod/`**

`lib.zig`:
```zig
pub fn getPtrAddr(ptr: [*]u8) usize {
    return @ptrToInt(ptr);
}
```

`main.zig`:
```zig
extern fn __bootstrap_print_int(n: i32) void;
const lib_mod = @import("lib.zig");

pub fn main() void {
    var buf: [10]u8 = undefined;
    var addr: usize = lib_mod.getPtrAddr(&buf[0]);
    if (addr != @intCast(usize, 0)) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
```

`NOTES.md` — standard format (What it tests, The compiler gap, Measured result, Oracle verification, Expected classification). Doc: `@ptrToInt` returns void (error[3000]), should return usize. Oracle: zig0 compiles clean.

Run zig1 dump: expected rc≠0 with `error[3000]: cannot declare variable of type void`.

- [ ] **Step 2: Create R1b — `mod_silent_drop_xmod/`**

`lib_a.zig`:
```zig
pub fn helper() i32 { return 42; }
```

`lib_b.zig`:
```zig
const a = @import("lib_a.zig");
pub fn wrapper() i32 { return a.helper(); }
```

`main.zig`:
```zig
const b = @import("lib_b.zig");
pub fn main() void { _ = b.wrapper(); }
```

`NOTES.md`: lib_a.c is not emitted by multi-module dump → gcc link fails with `undefined reference to zF_*_helper`. Minimal version of json_parser arena.c + rogue_mud scenario/room pattern.

Run zig1 with `--dump-c89 --output-dir DIR` — verify lib_a.c is NOT in the output dir.

- [ ] **Step 3: Create R1c — `zT_missing_fwd_xmod/`**

`types.zig`:
```zig
pub const Point = struct { x: i32, y: i32 };
```

`main.zig`:
```zig
const t = @import("types.zig");
pub fn printPoint(p: t.Point) void { _ = p; }
pub fn main() void {}
```

`NOTES.md`: `zT_XX` struct typedef missing from main header → gcc compile fails with `'zT_XX' undeclared`. Minimal version of json_parser_workaround zT_xx pattern.

Run zig1 with `--dump-c89 --output-dir DIR`, then gcc compile each .c — expected compile error on `main_*.c` with undeclared zT_xx.

- [ ] **Step 4: Create R1d — `plat_stubs_missing_xmod/`**

`console.zig`:
```zig
extern "c" fn plat_is_windows() bool;
extern "c" fn plat_console_putchar(c: i32) void;

pub fn doConsole() void {
    if (plat_is_windows()) {
        plat_console_putchar('X');
    }
}
```

`main.zig`:
```zig
const c = @import("console.zig");
pub fn main() void { c.doConsole(); }
```

`NOTES.md`: gcc link fails with `undefined reference to plat_is_windows`, `plat_console_putchar`. Existing `net_runtime.c` has `plat_socket_*` (14 symbols) but no console/platform-detection stubs. Catalog: present (socket family — 14 symbols), missing (console family — 5 symbols: plat_is_windows, plat_console_gotoxy, plat_console_setcolor, plat_console_putchar, plat_console_clear). This repro feeds the future std-lib plan. Classification: OK-by-gate/latent.

Run zig1 with `--dump-c89 --output-dir DIR`, gcc compile modules, link — expected link failure.

- [ ] **Step 5: Write `examples/z98/rogue_mud/NOTES.md`**

Format matching existing `examples/z98/mud_server/NOTES.md`:

```
## What it tests: rogue-like dungeon crawler with multi-module game engine

Single-module recipe: `zig1 --dump-c89 main.zig > /tmp/rm.c && gcc ... -o /tmp/rm`

Multi-module recipe: `mkdir -p /tmp/rm_dir && zig1 --dump-c89 --output-dir /tmp/rm_dir main.zig && cd /tmp/rm_dir && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c /workspace/znineeight/sf/src/include/net_runtime.c -o rm`

Status as of 2026-08-08:
- dump rc=0 (all 20 modules emit .c files)
- gcc compile rc=0 (0 errors, 5 warnings — pointer-to-int conversions in BSP/Room generics)
- gcc LINK FAILS: ~15 undefined references —
    - Module symbol gaps: generateDungeon (scenario.zig), Room_centerX/Y (room.zig), scenario_addQuest, scenario_addShop, pathfinding_findPath, bsp_connectRooms, plus ~8 more — modules ARE emitted but their function symbols are not visible to other modules
    - Platform stub gaps: plat_is_windows, plat_console_gotoxy, plat_console_setcolor, plat_console_putchar, plat_console_clear — missing from all runtime files, tracked as D4 (out-of-scope, feeds std-lib plan)

The module-layer gaps match the D2 (silent module drop / symbol visibility) defect tracked by `repro/mi_matrix/mod_silent_drop_xmod/`. Run with timeout (server application).
```

- [ ] **Step 6: Pre-validate all repros against zig0 oracle**

For R1a-R1c: compile each repro's main.zig with `sf/build/zig0 --dump-c89 > /tmp/x.c` (zig0 writes beside source — use /tmp copies). Verify zig0 produces correct output (no errors for R1a/R1c; all modules emitted for R1b).

For R1d: zig0 should also fail to link (same missing stubs) — verify. This confirms the gap is in the runtime library, not the compiler.

- [ ] **Step 7: Commit**

```bash
git add repro/mi_matrix/ptr_to_int_void_xmod/ repro/mi_matrix/mod_silent_drop_xmod/ repro/mi_matrix/zT_missing_fwd_xmod/ repro/mi_matrix/plat_stubs_missing_xmod/ examples/z98/rogue_mud/NOTES.md
git commit -m "repro: multi-module emission defect repros + rogue_mud NOTES.md"
```

**Gate:** 4 repro dirs each with main.zig + module .zig + NOTES.md; rogue_mud NOTES.md present; all pre-validated against zig0 oracle where applicable; REPROS-ONLY (no sf/src/*.zig changes).

---

### Task I1: @ptrToInt void type resolution investigation

**Files:**
- Investigate: `sf/src/type_resolver.zig` (constant evaluation / intrinsic return types), `sf/src/semantic_analyzer.zig` (expression type resolution)
- Modify (docs): `sf/docs/tech_docs/03_type_resolution.md`
- Report: `.superpowers/sdd/I-ptrtoint-void-report.md`

**Interfaces:**
- Consumes: R1 repro `ptr_to_int_void_xmod/`, lisp_interpreter sand.zig error[3000].
- Produces: mechanism confirmation (file:line), tech-doc update, blast radius, fix recommendation.

**Context:** `@ptrToInt(sand.pos)` where sand.pos is `[*]u8`. zig1 resolves the return type as void, causing `error[3000]: cannot declare variable of type void`. zig0 resolves it as usize.

- [ ] **Step 1: Confirm the mechanism**

Search `sf/src/type_resolver.zig` and `sf/src/semantic_analyzer.zig` for `@ptrToInt` handling (grep for "ptrToInt" or the intrinsic enum value). Find the intrinsic return-type table or case branch. Confirm the return type is void/null/unknown where it should be usize. Check if there's a general intrinsic table (e.g. `intrinsicReturnType` or similar) that omits `@ptrToInt`. Report the exact file:line.

- [ ] **Step 2: Verify symptom on repro + oracle reference**

Run zig1 on `ptr_to_int_void_xmod/main.zig` → confirm the exact error message. Run zig0 oracle on a /tmp copy → confirm it compiles clean and the emitted C uses usize.

- [ ] **Step 3: Assess blast radius**

Grep `sf/src/*.zig` for `@ptrToInt` usage — does the compiler itself use this intrinsic? If yes, which files and in what context? The fix might affect zig1's own compilation path. Grep examples/ for `@ptrToInt` usage — which examples use it and would be affected? lisp_interpreter is the only known hit.

- [ ] **Step 4: Update tech doc `03_type_resolution.md`**

Find the intrinsic type resolution section. Document: (a) the current gap — `@ptrToInt` return type is void/missing from the intrinsic table; (b) the correct type is usize; (c) cite the file:line of both the gap and the intended fix location; (d) add `[updated: 2026-08-08]`.

- [ ] **Step 5: Write I-report**

Write `.superpowers/sdd/I-ptrtoint-void-report.md`: mechanism (file:line), symptom + oracle reference, blast radius, recommended fix option (expected: add `@ptrToInt` → `usize` entry to intrinsic return-type table), concerns.

**Gate:** mechanism confirmed with file:line; tech doc updated with `[updated: 2026-08-08]`; blast radius assessed. No compiler code changes.

---

### Task I2: Module silent drop in multi-module emission investigation

**Files:**
- Investigate: `sf/src/c89_emit.zig` — per-module .c file emission ordering, module dependency graph, `emitModule` or equivalent
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Report: `.superpowers/sdd/I-silent-drop-report.md`

**Interfaces:**
- Consumes: R1 repro `mod_silent_drop_xmod/`, json_parser arena.c gap, rogue_mud scenario/room function visibility gap.
- Produces: mechanism confirmation, tech-doc update, blast radius, fix recommendation.

**Context:** In `mod_silent_drop_xmod`, lib_a.c is not emitted. In json_parser, arena.c is not emitted. In rogue_mud, scenario.c and room.c ARE emitted but their function symbols are unreachable from main.c — probably the same root cause: the per-module C89 emission dependency graph is incomplete (modules imported by a module that also imported something else may be skipped).

- [ ] **Step 1: Trace the module-to-C-file emission**

Read `sf/src/c89_emit.zig` for the emission loop (search for "foreach", "modules", emitModule, or the iteration that produces per-module .c files). Trace: how does zig1 decide which modules get a .c file? Is it driven by the import graph? By the resolved module list? By the symbol table? Find the exact iteration that determines which modules are emitted, and the condition that would skip a module (e.g. an early-exit, a missing entry in a map, an ordering constraint).

- [ ] **Step 2: Verify on the repros**

Run `mod_silent_drop_xmod` with `--dump-c89 --output-dir DIR` — confirm lib_a.c is missing. Run json_parser — confirm arena.c is missing. Run rogue_mud — confirm scenario.c IS present but generateDungeon unresolved. Analyze whether these are one defect or two (missing file vs missing symbol visibility). Check the emitted per-module .h files for the "missing symbol" case — is the function declared in the header but the definition missing from the .c? Or not declared at all?

- [ ] **Step 3: Assess blast radius**

Grep for multi-module examples that exercise the same pattern (module A imported by B, used transitively by main). Which examples exercise this correctly? gol (no multi-module), lisp (8+ modules), rogue_mud (20 modules), json_parser (4 modules). Which of these currently work — and why? This is a clue to the mechanism.

- [ ] **Step 4: Update tech doc `08_c89_emission.md`**

Find the multi-module emission section. Document: (a) the current module-to-file emission loop and its gap (modules can be skipped under certain import-graph configurations); (b) cite the exact file:line of the loop and the skip condition; (c) add `[updated: 2026-08-08]`.

- [ ] **Step 5: Write I-report**

Write `.superpowers/sdd/I-silent-drop-report.md`: mechanism (file:line), repro verification, blast radius, recommended fix option(s), concerns.

**Gate:** mechanism confirmed with file:line; 3 repros verified; tech doc updated; blast radius assessed. No compiler code changes.

---

### Task I3: Missing type forward-decls in multi-module headers investigation

**Files:**
- Investigate: `sf/src/c89_emit.zig` — header generation (`emitHeader`, `emitTypeDecl`, forward-decl loops)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Report: `.superpowers/sdd/I-missing-fwd-report.md`

**Interfaces:**
- Consumes: R1 repro `zT_missing_fwd_xmod/`, json_parser_workaround 6× zT_xx undeclared.
- Produces: mechanism confirmation, tech-doc update, blast radius, fix recommendation.

**Context:** When module A defines a struct and module B imports A and uses that struct in a function signature, module B's emitted header does not include the zT_xx typedef for that struct. The typedef exists in module A's .h but is not forwarded to module B's .h.

- [ ] **Step 1: Trace header generation**

Read `sf/src/c89_emit.zig` for the per-module header emission. Find where zT_xx typedefs are emitted (search for "typedef struct" or "zT" in the emitter). Find the condition that determines which types get a forward declaration in an importing module's header vs which are emitted only in the defining module. This is likely a "type ownership" decision — the emitter may think only the defining module needs the typedef, but gcc needs it in every module that uses the type.

- [ ] **Step 2: Verify on repros**

Run `zT_missing_fwd_xmod` — confirm which zT_xx types are in main_*.h vs missing. Run json_parser_workaround — confirm the 6 specific zT_xx that are missing. Categorize: are these all struct types? Optional/generic types? Error-set types? The category narrows the search.

- [ ] **Step 3: Assess blast radius**

Which currently-working multi-module examples emit headers correctly? lisp_curr (8+ modules) works with 9 warnings but 0 errors — its types resolve. What makes its types resolve vs json_parser_workaround's fail? The lisp types are mostly primitives + tagged unions; json_parser_workaround defines structs. This suggests the gap is struct-type-specific.

- [ ] **Step 4: Update tech doc `08_c89_emission.md`**

Find the header emission section. Document: (a) the current type-declaration emission logic and the gap (struct typedefs not forwarded to importing module headers); (b) cite file:line; (c) add `[updated: 2026-08-08]`.

- [ ] **Step 5: Write I-report**

Write `.superpowers/sdd/I-missing-fwd-report.md`: mechanism, repro verification, blast radius, recommended fix, concerns.

**Gate:** mechanism confirmed; repros verified; tech doc updated; blast radius assessed. No compiler code changes.

---

### Task I4: Platform stub gap catalog

**Files:**
- Investigate: `sf/src/include/net_runtime.c`, `sf/src/include/zig_runtime.c`, `sf/src/include/zig_pal.c`
- Report: `.superpowers/sdd/I-platstub-gap-report.md`

**Interfaces:**
- Consumes: R1 repro `plat_stubs_missing_xmod/`, rogue_mud NOTES.md plat_ requirements.
- Produces: catalog of existing vs missing plat_ symbols across all runtime files. Tech doc NOT updated (runtime, not compiler).

**Context:** Some z98 examples use `extern "c" fn plat_*` to call platform-layer functions. zig1's runtime library has `net_runtime.c` (14 socket symbols) but no console/UI stubs. This task catalogs the gap for a future std-lib plan. This is a documentation-only task.

- [ ] **Step 1: Catalog existing plat_ symbols**

Grep each runtime .c file for `plat_` function definitions. Build a table: file | symbol | signature | category (socket, file, memory, console, etc.).

- [ ] **Step 2: Catalog needed plat_ symbols from examples**

Grep `examples/z98/` for `extern "c" fn plat_` declarations. Cross-reference against the existing-symbol catalog. Build a "missing" table.

- [ ] **Step 3: Categorize**

Group missing symbols: console UI (rogue_mud — plat_console_*), platform detect (rogue_mud — plat_is_windows). What other examples use plat_ externs? mud_server uses plat_socket_* (already in net_runtime.c). Check game_of_life/mandelbrot for file/display externs.

- [ ] **Step 4: Write I-report**

Write `.superpowers/sdd/I-platstub-gap-report.md`: existing symbols table, needed symbols table, missing symbols table, category breakdown. This is the input to a future std-lib plan.

**Gate:** complete catalog of plat_ symbols across all 3 runtime files + all z98 examples; categorized (existing vs missing, by family). No compiler code changes.

---

### Task I5: Arena sizing analysis for self-compile

**Files:**
- Investigate: `sf/src/allocator.zig:74-76` (static arena sizes), `sf/src/main.zig` (phase orchestration, sandReset calls)
- Input: MEM1/MEM2/MEM3 arena reports (`.superpowers/sdd/MEM{1,2,3}-*.md`)
- Report: `.superpowers/sdd/I-arena-sizing-report.md`

**Interfaces:**
- Consumes: MEM1/MEM3 arena measurements, single-module OOM data (c89_emit.zig 5071 lines OOMs 1.5MB module arena), zig1 source file line counts.
- Produces: recommended arena sizes, per-module reset strategy, projected self-compile RSS.

**Context:** Current arenas: perm 1MB / mod 1.5MB / scr 1.5MB (4MB total static). Module arena holds cumulative ASTs across all modules and is NEVER reset. Self-compile OOMs at `used=938560 new=1724992 total=1572864` during import. Single largest file (c89_emit.zig 5071 lines) alone needs ~1.9MB module arena for its AST.

- [ ] **Step 1: Measure single-largest-file arena need**

Use the MEM3 data: c89_emit.zig standalone OOM `used=1094588 new=1881020 total=1572864`. Compute minimum module-arena size for the single largest file: ~1.9MB + margin → target 2–4MB for single-file safety + per-module reset.

- [ ] **Step 2: Model per-module reset impact**

If `sandReset(&alloc.module)` is added after each module's C89 emission in main.zig, the module arena peak becomes max(single-module-AST-burst) rather than sum(all-modules). Compute the module-arena peak with per-module reset: the single largest module's import-resolution AST. What's the single largest module by AST size? (c89_emit.zig at 5071 lines is the biggest source file; its AST estimated at ~1.9MB).

- [ ] **Step 3: Compute new arena sizes within 16 MB**

Target breakdown:
| Arena | Current | Proposed | Rationale |
|---|---|---|---|
| perm | 1.0 MB | 1.0 MB | Symbol table for 37 modules fits; unchanged |
| module | 1.5 MB | 4.0 MB | Holds largest single file AST (~1.9 MB) + import overhead + margin |
| scratch | 1.5 MB | 2.0 MB | Per-phase burst for 5K-line module lowering |
| **static total** | **4.0 MB** | **7.0 MB** | |
| Binary+runtime | ~1.8 MB | ~1.8 MB | |
| **peak RSS** | ~8.5 MB | **~12 MB** | Well within 16 MB |

Verify arithmetic against MEM3 data: module ≈ 464 B/line → c89_emit (5071 lines) → 2.35 MB. With the style density of zig1's own source (~800-900 B/line per MEM1 standalone measurements) → ~4.5 MB worst case. 4 MB module arena with per-module reset covers the likely worst case with margin.

- [ ] **Step 4: Check cross-phase accumulation**

The perm arena is never reset and accumulates interned strings, type registry entries, symbol tables across all 37 modules. At 140 B/line (MEM3 measurement) × 35,316 lines → ~4.9 MB — this would overflow the 1 MB perm arena. Analyze whether this is a real risk (most perm allocations are during symbol registration, not proportional to source lines; the 140 B/line was for rogue_mud's ecosystem, not zig1 self-compile). If perm needs growth, include in the proposal.

- [ ] **Step 5: Write I-report**

Write `.superpowers/sdd/I-arena-sizing-report.md`: per-file AST estimates, per-module reset impact, proposed sizes, projected self-compile RSS, risiks for the perm-arena accumulation.

**Gate:** recommended arena sizes computed from measurements; per-module reset strategy defined; projected self-compile RSS within 16 MB. No compiler code changes.

---

### Task F1: Fix @ptrToInt type resolution (per ruling)

**Files:**
- Modify: `sf/src/type_resolver.zig` or `sf/src/semantic_analyzer.zig` (per I1 locus)
- Modify (docs): `sf/docs/tech_docs/03_type_resolution.md`
- Test: `ptr_to_int_void_xmod/`, `examples/z98/lisp_interpreter/`

**Interfaces:**
- Consumes: I1 ruling, R1 repro `ptr_to_int_void_xmod/`.
- Produces: @ptrToInt returns usize; repro + lisp_interpreter compile clean.

- [ ] **Step 1: Implement per I1 ruling**
- [ ] **Step 2: Build + verify repro dump rc=0, gcc rc=0, run rc=0**
- [ ] **Step 3: Verify lisp_interpreter now dump rc=0**
- [ ] **Step 4: Verify 4 MD5 gates byte-identical (or re-baselined)**
- [ ] **Step 5: Update tech doc `03_type_resolution.md` to FIXED**
- [ ] **Step 6: Commit**

**Gate:** repro dump/gcc/run all rc=0; lisp_interpreter dump rc=0; 4 MD5 gates byte-identical or re-baselined; tech doc updated.

---

### Task F2: Fix module silent drop (per ruling)

**Files:**
- Modify: `sf/src/c89_emit.zig` (per I2 locus)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Test: `mod_silent_drop_xmod/`, `examples/z98/json_parser/`, `examples/z98/rogue_mud/`

**Interfaces:**
- Consumes: I2 ruling, R1 repro `mod_silent_drop_xmod/`.
- Produces: all imported modules emit .c files; json_parser arena.c emitted; rogue_mud module symbols resolve.

- [ ] **Step 1: Implement per I2 ruling**
- [ ] **Step 2: Build + verify repro: all modules emit .c files, gcc link rc=0**
- [ ] **Step 3: Verify json_parser: arena.c emitted, link rc=0**
- [ ] **Step 4: Verify rogue_mud: module-function symbols resolve (partially — plat_ stub gap remains)**
- [ ] **Step 5: Verify 4 MD5 gates**
- [ ] **Step 6: Update tech doc `08_c89_emission.md` to FIXED**
- [ ] **Step 7: Commit**

**Gate:** repro + json_parser + rogue_mud module symbols resolve; 4 MD5 gates OK; tech doc updated.

---

### Task F3: Fix missing type forward-decls (per ruling)

**Files:**
- Modify: `sf/src/c89_emit.zig` (per I3 locus)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Test: `zT_missing_fwd_xmod/`, `examples/z98/json_parser_workaround/`

**Interfaces:**
- Consumes: I3 ruling, R1 repro `zT_missing_fwd_xmod/`.
- Produces: zT_xx typedefs present in importing module headers; json_parser_workaround types resolve.

- [ ] **Step 1: Implement per I3 ruling**
- [ ] **Step 2: Build + verify repro: zT_xx in header, gcc compile rc=0**
- [ ] **Step 3: Verify json_parser_workaround: 6 zT_xx types resolve, gcc compile rc=0**
- [ ] **Step 4: Verify 4 MD5 gates**
- [ ] **Step 5: Update tech doc `08_c89_emission.md` to FIXED**
- [ ] **Step 6: Commit**

**Gate:** repro + json_parser_workaround gcc clean; 4 MD5 gates OK; tech doc updated.

---

### Task F4: Platform stub gap documentation (per ruling)

**Files:**
- Modify: `repro/mi_matrix/plat_stubs_missing_xmod/NOTES.md` (classification + std-lib reference)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (add `plat_stubs_missing_xmod` row, OK-by-gate/latent)
- Modify: `examples/z98/rogue_mud/NOTES.md` (update status with F2/F3 progress)

**Interfaces:**
- Consumes: I4 catalog, F2/F3 fixes.
- Produces: platform-stub gap formally documented in corpus manifest.

**Gate:** repro properly classified (OK-by-gate/latent, NOT FAIL). EXPECTED_FAIL.md updated. rogue_mud NOTES.md reflects F2/F3 status. No compiler changes.

---

### Task F5: Arena resize for self-compile (per ruling)

**Files:**
- Modify: `sf/src/allocator.zig` (arena buffer sizes)
- Modify: `sf/src/main.zig` (add per-module sandReset after emission)
- Modify (docs): tech doc covering allocator/memory budget
- Test: `sf/src/main.zig` self-compile dump (should no longer OOM)

**Interfaces:**
- Consumes: I5 analysis + ruling.
- Produces: zig1 self-compile dump passes import phase (no module-arena OOM).

- [ ] **Step 1: Implement per I5 ruling — resize arena buffers + add per-module reset**
- [ ] **Step 2: Build zig1 with new arena sizes (full zig0 → zig1 bootstrap)**
- [ ] **Step 3: Self-compile attempt: `zig1 --dump-c89 sf/src/main.zig` → passes import phase**
- [ ] **Step 4: Verify 4 MD5 gates — emitted C unchanged (or re-baselined with runtime proof)**
- [ ] **Step 5: Verify test_analyzer_bin PASS**
- [ ] **Step 6: Update tech doc with new arena sizes**
- [ ] **Step 7: Commit**

**Gate:** self-compile dump passes import phase (no module-arena OOM); 4 MD5 gates byte-identical or re-baselined; test_analyzer_bin PASS; tech doc updated with new sizes.

---

### Task F6: Gate sweep + full matrix reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v28 — F1-F5 fix records, full matrix)
- Modify: `docs/sf/QUICK_REF.md` (corpus baseline + MD5 table)
- Modify: `sf/docs/tech_docs/03_type_resolution.md`, `08_c89_emission.md` (final line-ref verification)
- Modify: `examples/z98/rogue_mud/NOTES.md` (final status)

**Interfaces:**
- Consumes: F1-F5 fixes, all 21 examples, all R1 repros.
- Produces: final manifest reflecting post-fix corpus state.

- [ ] **Step 1: Run full 21-example matrix (MEM4 recipe)**
- [ ] **Step 2: Verify 4 MD5 gates**
- [ ] **Step 3: Verify test_analyzer_bin PASS**
- [ ] **Step 4: Update EXPECTED_FAIL.md v28**
- [ ] **Step 5: Update QUICK_REF.md baseline**
- [ ] **Step 6: Final tech doc line-ref verification**
- [ ] **Step 7: Update rogue_mud NOTES.md final status**
- [ ] **Step 8: Commit**

**Gate:** 21-example matrix recorded; 4 MD5 gates byte-identical or re-baselined; test_analyzer_bin PASS; manifest + QUICK_REF + tech docs + rogue_mud NOTES.md consistent.

---

## Post-Plan

- **rogue_mud full end-to-end run** after the platform-stub gap is addressed by the std-lib plan
- **Self-compile full cycle** (zig1 → zig1.c → gcc → zig2) after the arena resize — this plan only targets passing the import phase; full emission + gcc-compilation of the 37-module output is the next milestone
- **0-FAIL corpus goal** remains blocked by 2 std-lib-deferred FAILs + 1 C89 fundamental
- **Platform-stub std-lib plan** fed by the I4 catalog + `plat_stubs_missing_xmod` repro
