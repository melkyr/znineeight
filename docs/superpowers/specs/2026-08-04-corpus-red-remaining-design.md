# Corpus-RED Remaining — 3-Plan Design Spec

**Date:** 2026-08-04
**Status:** Draft
**Predecessor:** `2026-08-03-corpus-red-fixes-design.md` (F-1..F-9 complete, corpus 184/8/0/0)

## Goal

Resolve the remaining corpus-RED work across three plans: (1) deferred items + defensive repros + runtime battery, (2) the 3 emission defects, (3) the frontend gaps + reclassifications.

## Architecture

Three independent plans, executed in order Plan 1 → Plan 2 → Plan 3. Each has its own repros, fixes, and gates. No functional dependency between plans.

```
Plan 1: Deferred items + defensive repros + 18-example runtime battery
Plan 2: 3 emission defects (array_tagged_union_read, ptroint_arena_offset, var_declared_void)
Plan 3: Frontend gaps (2 reclassify OK, 2 defer to std-lib, 2 investigate+fix)
```

---

# Plan 1: Deferred Items + Defensive Repros + Runtime Battery

## Scope

The F-1..F-9 changes shipped without full runtime verification, and 6 deferred items lack defensive repros. This plan creates repros for each deferred item (even those not yet triggerable), verifies the full example battery at runtime, and fixes what is fixable.

## Defensive Repros (5 new)

| Repro | Construct | Expected Today | Plan |
|-------|-----------|----------------|------|
| `xmod_global_field_access` | 2-file: `lib.zig` `pub var counter` + `bump()`; `main.zig` reads `lib.counter` | FAIL gcc (lower.zig:1851-1872 field-access path has no `SymbolKind.global` branch) | Fix: add global branch to module field-access path |
| `self_embed_optional_cycle` | `struct X { next: ?X }` | incomplete-type (2-cycle, topo drops both) | Documented residual — C89 cannot emit infinite-size type |
| `load_global_array_copy` | lisp-style 1MB buffer `pub var buf: [N]u8`; read/write/verify values | OK (correct values, wasteful dead copy temps) | Optimization note — future follow-up |
| `lisp_stressed_battery` | 8 expressions from `stress_expressions.md` | 7/8 expected; `(countdown 10000)` → OutOfMemory | Confirm current state |
| `example_full_battery` | All 18 z98 examples | 15 dump+compile+run (13 OK + json_parser + lisp_interpreter_adv), 3 BROKEN | Capture current error counts |

## Runtime Battery (gate)

All 18 examples: dump → gcc -c → link → run. Expected:
- 13 OK: hello, prime, fibonacci, quicksort, heapsort, lzw, days_in_month, func_ptr_return, sort_strings, mandelbrot, game_of_life, lisp_interpreter_curr, mud_server
- 1 OK-WITH-QUIRKS: json_parser (legacy runtime, needs test.json in CWD)
- 1 OK-WITH-BUG: lisp_interpreter_adv (define→call returns nil, pre-existing)
- 3 BROKEN re-measured: lisp_interpreter, json_parser_workaround, rogue_mud — capture current error counts (may have changed post-F-1..F-9)

## Fix: Cross-Module Global Field Access

**File:** `sf/src/lower.zig:1851-1872` (module field-access path)
**Root cause:** the `field_access` on a module symbol handles `type_alias`/`function` but not `SymbolKind.global`.
**Fix:** add a `SymbolKind.global` branch that emits `load_global` for the resolved symbol.
**Gate:** `xmod_global_field_access` repro gcc-clean + runs correct value. All 4 MD5s byte-identical.

## Deferred (documented, no fix)

- `self_embed_optional_cycle` — C89 cannot represent infinite-size types. Repro documents the residual.
- `load_global_array_copy` — correct but wasteful. Repro guards correctness; optimization is a future task.

---

# Plan 2: 3 Emission Defects

## Scope

The 3 repros that dump rc=0 but gcc rejects the emitted C. Each gets an investigation → fix → independent gate.

| Repro | Root Cause (known) | Realm | Method |
|-------|--------------------|-------|--------|
| `array_tagged_union_read` | I-R4 Bug 2: `c89_emit.zig:3532-3556` `.undefined_const` array copy writes only `.tag = 0` for tagged-union elements, payload never copied → reads wrong payload. Manifest entry STALE (says gcc error; actual runtime gap prints 6 not 7) | c89_emit.zig | Confirm root cause → fix array element copy for TU payloads |
| `ptroint_arena_offset` | NO prior I-R coverage. `@ptrToInt` + `@intToPtr` arena pointer arithmetic emits undeclared C temps | unknown | Full I-task investigation → A/B/C options → fix |
| `var_declared_void` | I-R1 Root Cause #3: `c89_emit.zig:2666` correctly suppresses TYPE_VOID temps; the sema gap is that `var x = void_expr;` is never rejected at compile time | semantic_analyzer.zig | Add void-var rejection in var_decl sema handler |

## Investigation Method (per defect)

1. Read docs (tech docs 03/05/07/08/09 + INDEX + LIR_C89_Emission_p2)
2. Reproduce the error with `zig1 --dump-c89` + gcc
3. Trace root cause with markers/GDB
4. Blast radius analysis
5. A/B/C fix options with file:line
6. Implement → gate repro individually

## Gates

- Each repro: dump rc=0, gcc-clean, runs correct output
- 4 MD5s byte-identical: mud `4644ad13...`, gol `d0d3051d...`, lisp `f84c8748...`, json `3492a935...`
- Corpus: FAIL count decreases by the fixed defects, no new FAILs

---

# Plan 3: Frontend Gaps + Reclassifications

## Scope

The 5 frontend-gap repros (dump rc!=0) plus the anonymous-error-set comparison item moved from Plan 1's deferred list.

## Reclassify to OK (correct rejections, docs-only)

| Repro | Error | Reason |
|-------|-------|--------|
| `eu_assign_incompat_payload` | error[3000] | EU payload mismatch correctly rejected. Matches zig0 oracle. Green guard, not a defect. |
| `field_access_optional` | error[3000] | `.` on optional correctly rejected. Matches zig0 oracle. Green guard, not a defect. |

Update EXPECTED_FAIL.md + QUICK_REF.md corpus counts: these 2 are CORRECT rejections (green guards) whose dump emits 0 .c. Reclassify to a distinct "green-guard (correct rejection)" bucket, separate from the FAIL counts, so the corpus numbers remain: 184 emission/sema OK + 2 green-guards + 2 import-gap FAIL + 3 emission-defect FAIL + 1 catch-block FAIL = 192. The classifier doc update is part of this plan.

## Defer to std-lib (documented, no fix)

| Repro | Error | Deferred Until |
|-------|-------|----------------|
| `field_store_drop` | error[3048] cannot import `"pal"` | real std lib |
| `test_stub_0` | error[3048] cannot import `"std"` | real std lib |

## Active Investigation: anon-set comparison

**Repro:** `anon_errset_comparison` — bare-`!` fn returning `error.Bad`; caller does `err == error.Bad`.
**Root cause hypothesis:** anonymous error-set literals carry the raw error name_id as C integer code (F-1 behavior). `err == error.Bad` compares raw codes, which may be semantically wrong (multiple error names can collide or miscompare).
**Investigation:** create repro → determine actual behavior (is `==` correct today or silently wrong?) → A/B/C options.
**Realm:** sema or c89_emit (may need a proper anonymous error-code registry).
**Gate:** repro behaves correctly (matches zig0 oracle) OR documented as known limitation with clear semantics.

## Active Investigation: catch_block_value_producing

**Repro:** `catch_block_value_producing` — `catch |err| { _ = err; 99 }`.
**Root cause (confirmed from source):** `parserParseBlock` (parser.zig:1746) loops `parserParseStatement`, and `parserParseExprStmt` (:1223) always requires a trailing `;` (:1258 `parserExpect(semicolon)`). The value-producing trailing expression `99` (no semicolon before `}`) fails → error[2000]. The lowering side (`lower.zig:2576-2641` `lowerExprOrBlock` + materialize) would work if the AST was valid.
**Standalone I-task** (tech docs do NOT cover this — confirmed: no spec/design/tech doc mentions the limitation; they imply blocks-as-catch-fallback works).
**Fix realm:** parser.zig (allow value-producing block: final expression statement without trailing `;` in block context), then verify sema + lowerer handle the produced value.
**Gate:** repro dumps rc=0, gcc-clean, runs correct value (99 on error path).

---

## Success Criteria (all 3 plans)

- All 18 examples: 15 verified OK at runtime, 3 BROKEN re-measured with current error counts documented
- Corpus: 184/8/0/0 → improves (emission defects fixed, green-guards reclassified). Import-gap FAILs (field_store_drop, test_stub_0) remain documented as std-lib-deferred.
- 4 MD5s byte-identical throughout
- Build 0 errors
- Every deferred item has a defensive repro in the corpus
- test_analyzer_bin PASS

## Execution Order

```
Plan 1 (repros + battery + cross-module global fix) → Plan 2 (3 emission defects) → Plan 3 (gaps + reclassifications)
```
