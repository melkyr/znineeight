# Multi-Module Emission Defects + Arena Self-Compile Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the confirmed compiler defects so all 21 z98 examples compile end-to-end: D1 @ptrToInt void (sema), D3 cross-module enum-member resolution, D6 cross-module tagged-union `==` SEGV — plus resize arenas for zig1 self-compile within 16 MB. Document D2 (extern arena symbols) and D4 (plat_ stubs) as deferred to the std-lib plan.

**Architecture:** R1 (4 repros, DONE) → R2 (1 new repro: cross-module tagged-union `==` SEGV) → I6 (investigate the SEGV, update tech doc) → combined STOP for operator ruling → F1 (@ptrToInt fix) → F2 (document D2 deferred + extern-link repro) → F3 (enum-member fix) → F4 (document D4 deferred) → F5 (arena resize) → F6 (tagged-union SEGV fix) → F7 (gate sweep + full matrix).

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), zig1 (`sf/build/out_release/zig1`), zig0 oracle (`sf/build/zig0`), gcc -m32 C89, repro battery, tech docs (`sf/docs/tech_docs/*.md`).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `sf/build/out_release/zig1`. **F1 prerequisite: REBUILD zig1 first** (current binary is stale vs `sf/src/parser.zig` — unknown VARCVINT markers). Build: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: sf/build/out_release/zig1 ===`.
- Multi-module recipe: `mkdir -p DIR && zig1 --dump-c89 --output-dir DIR main.zig`. Single-module: `zig1 --dump-c89 main.zig > /tmp/x.c`.
- **gcc compile recipe:** `cd DIR && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog`. mud_server/rogue_mud also link `net_runtime.c`.
- **RUNTIME gates mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 AND print the expected output. Compile-only gates are FORBIDDEN.
- **4 MD5 gates:** mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `fad411835b9e0aaea165260fbdc6857c`, json `c403f0799dbc5c56d548eee07bb9eebd` — byte-identical UNLESS operator-approved re-baseline with runtime proof (F-5 AMENDMENT B). **Known: F1 re-baselines lisp** (lisp_interpreter_curr uses @ptrToInt) — approved in operator ruling, runtime proof required.
- **Corpus:** 230 repros, OK=223/FAIL=3/gg=4 (231 dirs). FAIL must not increase. The 4 R1 repros + new repros are OK-by-compile/runtime-gap-tracked (NOT added to FAIL).
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task MUST update the corresponding `sf/docs/tech_docs/*.md` — corrected line refs, descriptions, `[updated: 2026-08-08]` annotation. Check INDEX.md Table A for the covering doc.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present. On any issue, STOP.
- **I-tasks report then STOP for combined operator ruling** (R2 + I6, one combined STOP). F-tasks do NOT start until the ruling.
- **D2 (extern arena symbols) and D4 (plat_ console stubs) are DEFERRED to the std-lib plan** — NOT fixed in this plan. Documented via F2/F4. Neither is a compiler defect (I2: runtime-library gap class (b); I4: runtime-library gap, zig0 fails identically).
- **D6 (cross-module tagged-union `==` SEGV) MUST arrive fixed** at the end of this plan (operator ruling m0381) — F6 is a real compiler fix, not documentation.
- **I5 ruling:** per-module arena reset REJECTED (module arena is a program-lifetime cross-module store; OOM fires in phase-1 import). F5 is resize-only: perm 4MB / module 8MB / scratch 2MB + `--max-mem 16M`.

---

### Task R1: Create multi-module repros + rogue_mud NOTES.md — ✅ COMPLETE (commit ba9e6a93, review clean)

**Result:** 4 repros created + rogue_mud NOTES.md. R1 findings that reshaped the plan (operator ruling m0368 "Rescope and continue"):
- **D1 @ptrToInt void CONFIRMED:** `ptr_to_int_void_xmod/` dump rc=2 error[3000]. Faithful trigger = untyped `const` + `& ~mask` chain.
- **D2 "module silent drop" FALSE:** all modules emit in all probed graph shapes; `mod_silent_drop_xmod/` links clean (kept as regression guard). json_parser's arena.zig is a never-imported orphan; the real gap is extern `arena_alloc_default` (runtime-library class (b)).
- **D3 zT_xx CONFIRMED, different trigger:** `zT_missing_fwd_xmod/` gcc 'zT_2' undeclared — cross-module enum-literal comparison, NOT struct-by-value.
- **D4 plat stubs CONFIRMED:** `plat_stubs_missing_xmod/` link fails on 5 stubs; zig0 identical failure (runtime gap). Catalog: 12 existing (socket, net_runtime.c), 5 missing (console + plat_is_windows).
- rogue_mud NOTES.md: all 20 modules emit, gcc compile rc=0, link fails on exactly the 5 plat_* stubs in both modes.

---

### Task R2: Create tagged_union_cmp_xmod repro (cross-module tagged-union `==` SEGV)

**Files:**
- Create: `repro/mi_matrix/tagged_union_cmp_xmod/lib.zig`, `main.zig`, `NOTES.md`
- Report: `.superpowers/sdd/task-R2-rogue-report.md`

**Interfaces:**
- Consumes: I3's separate finding (cross-module tagged-union `==` SEGVs the compiler).
- Produces: a reproducible SEGV gate for I6/F6.

**Context:** I3 found that while plain-enum cross-module member access silently resolves to TYPE_VOID, cross-module **tagged-union** member access in an `==` comparison **crashes the compiler (SEGV)**. The repro must exercise the faithful pattern: `lib.zig` defines a tagged union `Types`; `main.zig` imports it and compares `if (v == lib.Types.Member)`.

- [ ] **Step 1: Write the repro**

`repro/mi_matrix/tagged_union_cmp_xmod/lib.zig`:
```zig
pub const Shape = union(enum) {
    Circle: i32,
    Square: i32,
    Triangle: i32,
};
```

`repro/mi_matrix/tagged_union_cmp_xmod/main.zig`:
```zig
const lib_mod = @import("lib.zig");

fn kindName(s: lib_mod.Shape) i32 {
    if (s == lib_mod.Shape.Circle) {
        return @intCast(i32, 1);
    }
    return @intCast(i32, 0);
}

pub fn main() void {
    extern fn __bootstrap_print_int(n: i32) void;
    var c = lib_mod.Shape{ .Circle = @intCast(i32, 5) };
    __bootstrap_print_int(kindName(c));
}
```

- [ ] **Step 2: Run it — confirm the SEGV**

Run: `mkdir -p /tmp/r2 && sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/r2 repro/mi_matrix/tagged_union_cmp_xmod/main.zig 2>/tmp/r2/err; echo "rc=$?"`
Expected: **SEGV** (rc 139 or ICE) — confirm this is the crash I3 found. Record the exact symptom (which phase, stderr, rc).

- [ ] **Step 3: Run zig0 oracle on a /tmp copy**

zig0 writes beside the source — copy to /tmp. Expected: compiles clean (rc=0), emits correct C. This is the post-fix reference.

- [ ] **Step 4: Write NOTES.md**

Mirror `repro/mi_matrix/ptr_to_int_void_xmod/NOTES.md` format: What it tests / The compiler gap (SEGV symptom, not error[3000] — a crash, classified DUMP FAIL / compiler crash) / Measured result (rc, stderr) / Oracle verification (zig0 clean) / Expected classification.

- [ ] **Step 5: Write the R-report**

Write `.superpowers/sdd/task-R2-rogue-report.md`: repro files, SEGV confirmation (rc + stderr), oracle reference, classification.

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/tagged_union_cmp_xmod/
git commit -m "repro: cross-module tagged-union == comparison SEGV (tagged_union_cmp_xmod)"
```

**Gate:** SEGV reproduced with evidence; zig0 oracle clean (post-fix reference); NOTES.md written; committed.

---

### Task I6: Cross-module tagged-union `==` SEGV investigation

**Files:**
- Investigate: `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig` — the cross-module tagged-union comparison path
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Report: `.superpowers/sdd/I-taggedunion-cmp-report.md`

**Interfaces:**
- Consumes: R2 repro `tagged_union_cmp_xmod/`, I3 report (separate-finding context).
- Produces: crash locus + root cause, tech-doc update, blast radius, fix recommendation for the combined ruling.

**Context:** Cross-module `x == mod.TaggedUnion.Member` SEGVs the compiler. Same-module tagged-union `==` works. I3 confirmed the enum-member path resolves cross-module members to TYPE_VOID for PLAIN enums; tagged unions take a different path that crashes instead of degrading gracefully.

- [ ] **Step 1: Reproduce + isolate the crash**

Run `tagged_union_cmp_xmod` under gdb (if available) or with the ASan build to capture the crash site (file:line + backtrace). If gdb is unavailable, narrow by: (a) same-module control (`v == Shape.Circle` inside lib.zig) — works? (b) cross-module without the `==` (just `var x = lib.Shape.Circle;`) — works? (c) cross-module `==` — crashes? Record which combination crashes.

- [ ] **Step 2: Locate the crash locus**

Read `sf/src/semantic_analyzer.zig` around `:260-300` (ident_expr base enum-member resolution), `:440-470` (resolveFieldAccess), and the tagged-union comparison handling in `lower.zig` (search "tagged_union", union comparison, `.eq` on union types). Find where a null/invalid pointer or missing member lookup is dereferenced for the cross-module case. The likely locus: the same branch that resolves PLAIN enums to VOID (`:459` else) dereferences something for tagged-union members that isn't there cross-module (missing type-registry entry for the union tag member in the importing module).

- [ ] **Step 3: Compare against the I3 enum fix target**

Determine whether F6's fix is: (a) the SAME Option-A dispatch fix as F3 (add tagged-union member case alongside enum_type), which would ALSO fix the SEGV by handling cross-module tagged-union members like same-module; or (b) a DISTINCT locus that F3 wouldn't touch. This determines whether F3 and F6 share code or are independent. Read the same-module tagged-union member path (`semantic_analyzer.zig:260-271` ident-expr branch; lower.zig `:1981-1999`) to see what the cross-module path must mirror.

- [ ] **Step 4: Assess blast radius**

Which examples use cross-module tagged-union comparisons or values? Grep `examples/z98/` for `==` on imported union members. mud/gol/lisp use tagged-union `switch` (works); the `==` form is the gap. Report which examples flip with a fix.

- [ ] **Step 5: Update tech doc `08_c89_emission.md`**

Document: (a) the cross-module tagged-union comparison SEGV (crash locus, file:line); (b) how the same-module path differs; (c) `[updated: 2026-08-08]`. Do NOT fix compiler code.

- [ ] **Step 6: Write the I-report**

Write `.superpowers/sdd/I-taggedunion-cmp-report.md`: crash locus (file:line + mechanism), the (a)-or-(b) determination vs F3, blast radius, recommended fix option(s), concerns.

**Gate:** crash reproduced + locus identified with file:line; (a)-vs-(b) relationship to F3 determined; blast radius assessed; tech doc updated with `[updated: 2026-08-08]`. No compiler code changes.

**Report back after I6 — combined STOP with R2 findings for the operator ruling** (F1-F6 do not start until the ruling).

---

### Task F1: Fix @ptrToInt type resolution (per ruling)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (hoist ptrtoint check above `ec.len` dispatch, around `:1284-1297`)
- Modify (docs): `sf/docs/tech_docs/03_type_resolution.md`
- Test: `repro/mi_matrix/ptr_to_int_void_xmod/`, `examples/z98/lisp_interpreter/`

**Interfaces:**
- Consumes: I1 report (`I-ptrtoint-void-report.md`), operator ruling.
- Produces: `@ptrToInt(x)` resolves to TYPE_USIZE regardless of arg count.

**Context (I1):** `semantic_analyzer.zig:1289-1292` sets `@ptrToInt → TYPE_USIZE` but it's dead code nested under `ec.len >= 2` at `:1284`. Single-arg `@ptrToInt(x)` falls through to `:1296-1297`, returning the ARGUMENT's type (pointer). Untyped const → pointer → `& ~mask` → VOID → error[3000]. Lowerer already correct (lower.zig:2626-2634).

- [ ] **Step 1: REBUILD zig1 first** (prerequisite — current binary stale vs parser.zig)

```bash
bash sf/scripts/build_release.sh
```
Gate: `=== [release] Done: sf/build/out_release/zig1 ===`. Then re-verify `ptr_to_int_void_xmod` still reproduces on the fresh binary (dump rc=2 error[3000]).

- [ ] **Step 2: Write the failing test (repro gate)**

`ptr_to_int_void_xmod/` is the test. Run it pre-fix: expect dump rc=2, `error[3000]: cannot declare variable of type void`. This is the red state.

- [ ] **Step 3: Implement the fix**

In `sf/src/semantic_analyzer.zig`, hoist the ptrtoint check above the `ec.len >= 2` dispatch. Find the intrinsic-name check (`ptrtoint_name_id` — verify the exact identifier in source) and move/duplicate it to fire for single-arg `@ptrToInt`, returning `type_mod.TYPE_USIZE`. Mirror the lowerer's already-correct handling (lower.zig:2626-2634). Do NOT change the `ec.len >= 2` multi-arg path semantics.

- [ ] **Step 4: Build + verify the repro goes green**

Rebuild zig1. Run `ptr_to_int_void_xmod/`: dump rc=0, emitted C has `(unsigned int)ptr` cast, gcc compile rc=0, run rc=0. Run `examples/z98/lisp_interpreter/`: dump rc=0 (previously error[3000]).

- [ ] **Step 5: Verify 4 MD5 gates — lisp re-baselines**

Run the 4 gates. gol/mud/json byte-identical. **lisp re-baselines** (lisp_interpreter_curr util.zig:54-55 uses @ptrToInt — emitted C changes). Verify lisp runtime output is byte-identical to pre-fix (AMENDMENT B), record new MD5.

- [ ] **Step 6: Update tech doc `03_type_resolution.md` to FIXED**

- [ ] **Step 7: Commit**

```bash
git add sf/src/semantic_analyzer.zig sf/docs/tech_docs/03_type_resolution.md
git commit -m "fix: @ptrToInt resolves to usize for single-arg calls (ptr_to_int_void_xmod)"
```

**Gate:** rebuild done; repro green (dump/gcc/run rc=0); lisp_interpreter dump rc=0; 4 MD5s verified (lisp re-baselined with runtime proof); tech doc updated.

---

### Task F2: Document D2 deferred to std-lib + create extern-link repro (per ruling)

**Files:**
- Create: `repro/mi_matrix/extern_runtime_symbol_xmod/lib.zig`, `main.zig`, `NOTES.md`
- Modify: `examples/z98/json_parser/NOTES.md`, `examples/z98/json_parser_workaround/NOTES.md`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`
- Report: `.superpowers/sdd/task-F2-rogue-report.md`

**Interfaces:**
- Consumes: I2 report (`I-orphan-module-report.md`), operator ruling (D2 deferred to std-lib).
- Produces: the extern-link pattern covered by a corpus repro; json_parser + json_parser_workaround officially documented as deferred (std-lib).

**Context (I2):** `arena_alloc_default` is an extern (json.zig:253, file.zig:25) declared in `zig_runtime.h:21-22` but defined ONLY in the legacy `src/runtime/zig_runtime.c`, absent from `sf/src/include/zig_runtime.c`. Class (b) runtime-library gap. **Operator ruling: deferred to the std-zig1 library — NOT fixed here.** `mod_silent_drop_xmod` does NOT cover the extern pattern.

- [ ] **Step 1: Create the extern-link repro**

`repro/mi_matrix/extern_runtime_symbol_xmod/lib.zig`:
```zig
extern "c" fn arena_alloc_default(n: u32) [*]u8;

pub fn alloc(n: u32) [*]u8 {
    return arena_alloc_default(n);
}
```

`repro/mi_matrix/extern_runtime_symbol_xmod/main.zig`:
```zig
const lib_mod = @import("lib.zig");

pub fn main() void {
    extern fn __bootstrap_print_int(n: i32) void;
    var p = lib_mod.alloc(@intCast(u32, 16));
    __bootstrap_print_int(@intCast(i32, @ptrToInt(p) == @intCast(usize, 0)));
}
```

- [ ] **Step 2: Verify the failure mode**

Multi-module dump rc=0, all modules emit; gcc link rc=1 with `undefined reference to arena_alloc_default` (standard recipe). zig0 oracle on /tmp copy: same link failure — confirms runtime gap, not compiler. **Classification: OK-by-gate/latent, NOT a corpus FAIL.** This repro is the std-lib plan's spec.

- [ ] **Step 3: Update json_parser + json_parser_workaround NOTES.md**

Add a "Deferred to std-lib" section: arena_alloc_default extern needs std-lib runtime; link recipe with legacy `src/runtime/zig_runtime.c` makes it work (documented API, runtime_api.md:38-48); standard recipe fails on 5 undefined refs.

- [ ] **Step 4: Update EXPECTED_FAIL.md**

Add the deferred record for json_parser + json_parser_workaround + the new `extern_runtime_symbol_xmod` repro (OK-by-gate/latent, std-lib-deferred).

- [ ] **Step 5: Write the F-report**

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/extern_runtime_symbol_xmod/ examples/z98/json_parser/NOTES.md examples/z98/json_parser_workaround/NOTES.md repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "docs: defer extern arena symbols to std-lib + extern_runtime_symbol_xmod repro"
```

**Gate:** repro created + link-failure verified + zig0-oracle-identical; NOTES.md + EXPECTED_FAIL.md document the deferral; no compiler changes.

---

### Task F3: Fix cross-module enum-member resolution (per ruling)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (add enum_type member case to generic base-type dispatch, `:281` module branch or `:459` else)
- Modify: `sf/src/lower.zig` (mirror at `:2016`)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Test: `repro/mi_matrix/zT_missing_fwd_xmod/`, `examples/z98/json_parser_workaround/`

**Interfaces:**
- Consumes: I3 report (`I-missing-fwd-report.md`), operator ruling.
- Produces: cross-module plain-enum member access (`x == mod.Type.Member`) resolves to the member value (enum_const), not TYPE_VOID.

**Context (I3):** NOT a header forward-decl gap — the importing .h includes the defining module's .h and the enum typedef IS in scope. The gap is sema/lowering: `mod.Type.Member` parses as nested field_access; `semanticAnalyzerResolveFieldAccess` (semantic_analyzer.zig:459) + lower's field-access branch resolve it to TYPE_VOID (enum-member lookup only fires for ident_expr base, `:260-271`/`:1981-1999`). `emitHoistedDecls` skips the VOID temp (c89_emit.zig:2897).

- [ ] **Step 1: Write the failing test**

`zT_missing_fwd_xmod/` is the test. Pre-fix: dump rc=0, gcc compile of `main_*.c` fails `'zT_2' undeclared`.

- [ ] **Step 2: Implement the fix (Option A)**

Add an `enum_type` member-literal case to the generic base-type dispatch in `semantic_analyzer.zig` (the module branch at `:281` or the `:459` else — read the code to pick the correct spot, mirroring how same-module `ident_expr` enum members are resolved at `:260-271`). Mirror in `sf/src/lower.zig` at `:2016` to emit `.enum_const`. Verify the enum member ordinal lookup path (enum_value_table) used by the same-module case works cross-module (the defining module's enum is already in the shared registry).

- [ ] **Step 3: Build + verify repro green**

Rebuild zig1. `zT_missing_fwd_xmod/`: dump rc=0, gcc compile rc=0 (enum value emitted), run rc=0. `json_parser_workaround/`: 6× zT_xx resolved, gcc compile rc=0.

- [ ] **Step 4: Verify 4 MD5 gates**

All 4 byte-identical (mud/gol/lisp/json use switch, not the `==`-form; no enum-member cross-module `==` in the gates — verify).

- [ ] **Step 5: Update tech doc `08_c89_emission.md` to FIXED**

- [ ] **Step 6: Commit**

```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig sf/docs/tech_docs/08_c89_emission.md
git commit -m "fix: cross-module plain-enum member access resolves (zT_missing_fwd_xmod)"
```

**Gate:** repro + json_parser_workaround gcc-clean + run rc=0; 4 MD5 gates byte-identical; tech doc updated.

---

### Task F4: Document D4 plat-stub gap deferred to std-lib (per ruling)

**Files:**
- Modify: `repro/mi_matrix/plat_stubs_missing_xmod/NOTES.md` (classification + std-lib reference)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (plat_stubs_missing_xmod row, OK-by-gate/latent)
- Modify: `examples/z98/rogue_mud/NOTES.md` (final status — still blocked at link on 5 plat_* stubs)
- Modify: `docs/sf/QUICK_REF.md` (deferral note)
- Report: `.superpowers/sdd/task-F4-rogue-report.md`

**Interfaces:**
- Consumes: I4 catalog, operator ruling (D4 deferred to std-lib).
- Produces: the platform-stub gap formally documented as deferred in the corpus manifest.

**Context (I4):** 12 plat_ symbols exist (all socket-family, net_runtime.c); 5 missing (plat_is_windows, plat_console_gotoxy, plat_console_setcolor, plat_console_putchar, plat_console_clear) — all rogue_mud-only. zig0 fails identically. **Deferred to std-lib plan.**

**Gate:** repro properly classified (OK-by-gate/latent, NOT FAIL); EXPECTED_FAIL.md + rogue_mud NOTES.md + QUICK_REF.md updated; no compiler changes.

---

### Task F5: Arena resize for self-compile (per ruling)

**Files:**
- Modify: `sf/src/allocator.zig` (arena buffer sizes: perm 4MB / module 8MB / scratch 2MB)
- Modify: `sf/src/main.zig` (DEV_MAX_MEM / RELEASE_MAX_MEM → 16MB, `--max-mem 16M` default)
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md` (new sizes + budget)
- Test: `sf/src/main.zig` self-compile dump (import phase no OOM)

**Interfaces:**
- Consumes: I5 analysis (`I-arena-sizing-report.md`) + operator ruling.
- Produces: zig1 self-compile dump passes import phase (no module-arena OOM).

**Context (I5):** Per-module reset REJECTED — module arena is a program-lifetime cross-module store (shared AstStore main.zig:159 + resolved/LIR/global_decls main.zig:161-192); OOM fires in phase-1 import before emission. Resize-only: perm 4MB (was 1, source-text closure 1.3MB risk) / module 8MB (was 1.5, single-file c89_emit 2.35MB + cumulative) / scratch 2MB (was 1.5). Projected self-compile RSS ~12-14MB within 16MB.

- [ ] **Step 1: Resize arena buffers in `sf/src/allocator.zig`**

Change the three `[N]u8` arena arrays: perm `[1 MB]` → `[4 MB]`, module `[1572864]`/`[1.5 MB]` → `[8 MB]`, scratch `[1.5 MB]` → `[2 MB]`. Verify the exact constant names in source first.

- [ ] **Step 2: Update memory limits in `sf/src/main.zig`**

DEV_MAX_MEM / RELEASE_MAX_MEM → 16MB (and/or the `--max-mem` default). Keep the `checkCombinedPeak` gate but at 16MB.

- [ ] **Step 3: Build + self-compile import-phase attempt**

Rebuild zig1 (full zig0 → zig1 bootstrap). Run: `mkdir -p /tmp/z5 && sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/z5 sf/src/main.zig 2>/tmp/z5/err`. **Gate: passes import phase (no `OOM: used=...` rc=3).** Record peak arena usage via `--track-memory --markers`.

- [ ] **Step 4: Verify 4 MD5 gates**

Emitted C unchanged → 4 MD5s byte-identical (arena size doesn't change codegen). If any re-baseline with runtime proof, record.

- [ ] **Step 5: Verify test_analyzer_bin PASS**

- [ ] **Step 6: Update tech doc `00_shared_infra.md` with new sizes**

- [ ] **Step 7: Commit**

```bash
git add sf/src/allocator.zig sf/src/main.zig sf/docs/tech_docs/00_shared_infra.md
git commit -m "feat: resize arenas for self-compile (perm 4M/mod 8M/scr 2M, 16M budget)"
```

**Gate:** self-compile dump passes import phase (no OOM); 4 MD5 gates byte-identical; test_analyzer_bin PASS; tech doc updated.

---

### Task F6: Fix cross-module tagged-union `==` SEGV (per ruling)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` and/or `sf/src/lower.zig` (per I6 locus + ruling)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md`
- Test: `repro/mi_matrix/tagged_union_cmp_xmod/`

**Interfaces:**
- Consumes: I6 ruling, R2 repro `tagged_union_cmp_xmod/`.
- Produces: cross-module tagged-union `==` compiles and runs (no SEGV).

- [ ] **Step 1: Implement per I6 ruling** (mirror the same-module tagged-union member path for cross-module; if I6 determined it's the same Option-A dispatch as F3, ensure F6 handles the tagged-union member case F3's enum_type case doesn't)
- [ ] **Step 2: Build + verify repro: dump rc=0, gcc rc=0, run rc=0 printing `1`**
- [ ] **Step 3: Verify no regression on F3's repros (zT_missing_fwd_xmod, json_parser_workaround still green)**
- [ ] **Step 4: Verify 4 MD5 gates**
- [ ] **Step 5: Update tech doc `08_c89_emission.md` to FIXED**
- [ ] **Step 6: Commit**

**Gate:** repro green (dump/gcc/run rc=0, prints `1`); F3 repros still green; 4 MD5 gates OK; tech doc updated.

---

### Task F7: Gate sweep + full matrix reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v28 — F1-F6 fix records, full matrix)
- Modify: `docs/sf/QUICK_REF.md` (corpus baseline + MD5 table)
- Modify: `sf/docs/tech_docs/03_type_resolution.md`, `08_c89_emission.md`, `00_shared_infra.md` (final line-ref verification)
- Modify: `examples/z98/rogue_mud/NOTES.md` (final status)

**Interfaces:**
- Consumes: F1-F6 fixes, all 21 examples, all R1+R2 repros.
- Produces: final manifest reflecting post-fix corpus state.

- [ ] **Step 1: Run full 21-example matrix (MEM4 recipe)**
- [ ] **Step 2: Verify 4 MD5 gates** (post-F1 lisp re-baseline + post-F2 F5 gates)
- [ ] **Step 3: Verify test_analyzer_bin PASS**
- [ ] **Step 4: Update EXPECTED_FAIL.md v28**
- [ ] **Step 5: Update QUICK_REF.md baseline**
- [ ] **Step 6: Final tech doc line-ref verification**
- [ ] **Step 7: Update rogue_mud NOTES.md final status**
- [ ] **Step 8: Commit**

**Gate:** 21-example matrix recorded (expect: lisp_interpreter + json_parser_workaround cleared, tagged_union_cmp_xmod cleared, json_parser still deferred to std-lib, rogue_mud still deferred at link); 4 MD5 gates verified; test_analyzer_bin PASS; manifest + QUICK_REF + tech docs + rogue_mud NOTES.md consistent.

---

## Post-Plan

- **std-lib plan** (next): implement arena_alloc_default + plat_ console stubs in the std zig1 library — fed by the I2 + I4 catalogs, the `extern_runtime_symbol_xmod` repro, and the `plat_stubs_missing_xmod` repro. Unblocks json_parser + rogue_mud.
- **rogue_mud full end-to-end run** after the std-lib plan provides plat_ stubs.
- **Self-compile full cycle** (zig1 → zig1.c → gcc → zig2) — F5 only targets passing the import phase; full emission + gcc-compilation of the 37-module output is the next milestone.
- **0-FAIL corpus goal** remains blocked by 2 std-lib-deferred FAILs (field_store_drop, test_stub_0) + 1 C89 fundamental (self_embed_optional_cycle).
- **Cross-module tagged-union `==`** must be fixed (F6) — operator ruling m0381.
