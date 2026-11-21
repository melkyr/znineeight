# lisp_interpreter Lowerer Defects Fix Design Spec

**Date:** 2026-08-13
**Status:** Approved by operator (design questions m0757/m0763: Option 1 full union_type support; both fixed at sema as upstream; R-task creates 2 minimal repros; F3 folds any further surfaced cleanup). Amended after F3 gate surfaced Defect C (operator ruling m0834: fix GENERAL nested-lvalue-field-store, add cross-module repro). Ready for plan.

## 1. Goal

Make `examples/z98/lisp_interpreter` (the only non-working example) compile + link + run end-to-end, achieving **21/21 examples**. Three lowerer defects gate it: (A) bare-union literal nested in a struct literal drops its construction (`5× zT_N undeclared`); (B) module-scope `var x: ?T = null` global init types the null temp `int` instead of the optional (`1× Opt_49` type mismatch); (C) nested field-access store drops the write-back (runtime SEGFAULT).

## 2. Problem Statement

The std-lib plan's F7 matrix is 20/21 examples end-to-end. The sole gcc-FAIL is `lisp_interpreter` (dumps rc=0, gcc-fails on 6 errors). Reproduced and characterized:

```
parser_F707FD5C.c:809  incompatible types when assigning to type 'zT_2FE68298_Opt_49' from type 'int'
token_89A7AC30.c:293,317,334,468,499  'zT_9'/'zT_25'/'zT_36'/'zT_106'/'zT_151' undeclared (5×)
```

Both are pre-existing lowerer defects, previously masked by the @ptrToInt sema block (F1 cleared it). NOT std-lib regressions. Both already tracked as EXPECTED_FAIL.md follow-up #3 (lines 1761-1764).

### Defect A — bare-union literal nested in struct literal (5× `zT_N` undeclared)

Source (`token.zig:42`): `Token{ .tag = TokenTag.Eof, .data = TokenData{ .Int = @intCast(i64, 0) } }` where `TokenData` is a **bare union** (`union { Int: i64, Symbol: []const u8 }`, token.zig:11-14) and `Token` is a plain struct (token.zig:16-19).

Emitted C: the inner `TokenData{ .Int = 0 }` construction is dropped — `zT_7.data = zT_9` references `zT_9`, which `hoistTemps` never declares because its type is VOID.

**Root cause — `union_type` is a missing type-kind in the struct-literal path:**
1. `semantic_analyzer.zig:1029` `semanticAnalyzerResolveStructInit` — handles `tagged_union_type` (:1038) + `struct_type` (:1066), falls through to `TYPE_VOID` (:1094) for `union_type`.
2. `lower.zig:3283-3423` struct_init field loop — handles `tagged_union_type` (:3379-3406) + `struct_type` (:3407-3420), no `union_type` branch → no assign emitted.
3. `c89_emit.zig:188` `emitFieldAssign` — no `union_type` branch (the sibling `store_field` at :4202 already handles unions; the asymmetry is specifically the struct-literal `assign_field` path).

### Defect B — module-scope optional `= null` global init typed `int` (1× `Opt_49`)

Source (`parser.zig:12`): `var global_symbol_list: ?*SymbolNode = null;`

Emitted C: `int zT_0; zT_0 = NULL; zG_... = zT_0;` — the null temp is `int` (getCTypeName null_type → "int"), assigned into the optional global → gcc type mismatch.

**Root cause — global-init path never records a coercion:**
- Function-body `var x: ?T = null` → `semantic_analyzer.zig:1862-1867` `coercionTableAdd(..., wrap_optional_null, decl_type)`. The lowerer null branch (`lower.zig:1267-1296`) then emits `set_optional_null` correctly.
- Module-scope globals → `main.zig:368` `phase_SemanticAnalysis` special block (`main.zig:400-441`) resolves the type + init but **never calls `tryRecordCoercion`/`coercionTableAdd`**. The null literal resolves to `TYPE_NULL`; the lowerer falls through to the fallback (`lower.zig:1298-1302`): `nextTemp(TYPE_NULL)` + `null_const` → `int`.

### Defect C — nested field-access store drops the write-back (runtime SEGFAULT)

Surfaced when F3's gate ran lisp_interpreter (post Defects A+B, it compiles+links but SEGFAULTS at run, rc=139). Source (`value.zig`): hand-rolled tagged unions — `v.data.Cons.car = car;` where `v: *Value`, `data: union { Cons: ConsData, ... }`, `ConsData = struct { car: *Value, cdr: *Value }`.

Emitted C: the store to a nested lvalue mutates throwaway locals, never written back:
```c
zT_6 = v.data;        /* load union into LOCAL */
zT_7 = zT_6.Cons;     /* copy member into LOCAL */
zT_7.car = car;       /* mutate the LOCAL copy — never written back to v.data */
```

**Root cause — nested lvalue field-store base lowered as an rvalue copy:** `lowerAssignLValue` (lower.zig:793) → `field_access` → `lowerFieldStore` (:844). `lowerFieldStore` computes `base_temp = lowerExpr(child_0)` (:860) for non-index bases — for a nested chain (`a.b.c = x`) the base `a.b` is lowered as an rvalue (`load_field` copies), so the outer `store_field` mutates a copy. `lowerLValueAddr` (:739) has NO `field_access` branch (only index/ident/deref/paren). **Valid Zig** (oracle zig0 runs identical code rc=0); **GENERAL** (any 2+ level field-access lvalue, struct or union, same-module + cross-module).

## 3. Architecture

Both defects are fixed at **sema as the upstream** (operator ruling m0759/m0761), with lowerer/emitter changes only as the necessary downstream completion of the sema resolution. This mirrors the F3 precedent (add the missing type-kind case at sema + lower + emitter) and the function-body coercion-record precedent.

**Defect A (3 layers, sema-rooted):**
1. **sema** `semantic_analyzer.zig:1029` — add `union_type` branch to `semanticAnalyzerResolveStructInit`, mirroring `struct_type` (`:1066-1093`): resolve to the union type, push per-field expected type + record coercion.
2. **lower** `lower.zig:3363-3421` — add `union_type` branch to the struct-init field loop, emitting the field assign (mirroring struct/tagged_union branches).
3. **emitter** `c89_emit.zig:188` `emitFieldAssign` — add `union_type` branch (the sibling `store_field` at :4202 already handles unions; this closes the assign_field asymmetry).

**Defect B (1 layer, sema, Option 2 — operator ruling m0792):**
- Add pub fn `semanticAnalyzerResolveModuleVarDecl` in `semantic_analyzer.zig` that owns resolve + coercion record (mirroring `:1862-1867`); `main.zig:400-441` calls it instead of hand-rolling. Coercion recording stays in ONE home (sema). Covers `null` AND `undefined` global inits. F2 re-baselines gol/lisp/json MD5s (module-scope int-literal coercion now recorded — identical to function-body behavior; operator ruling m0809).

**Defect C (1 layer, lowerer lvalue path, operator ruling m0834 — GENERAL fix):**
- Extend the lvalue/address path so a nested field-access store base lowers to its ADDRESS (store through pointer) instead of an rvalue copy. Locus: `lower.zig` `lowerLValueAddr` (:739, add `field_access` branch) and/or `lowerFieldStore` (:844, route nested-base through address). Verify against the store_field emitter (c89_emit:4134, pointer-base handling) + addr_of (:4289). Single-level field stores (`o.tag = 1`) and index bases (`arr[i].f = x`) must stay unchanged.

## 4. Tasks

### 4.1 R — Create 2 repros

**`repro/mi_matrix/union_literal_nested_xmod/`** (lib.zig + main.zig + NOTES.md):
- lib.zig: bare `union { Int: i64, Sym: i32 }` + plain `struct { tag: enum, data: <union> }` + `pub fn make(v: i64) Wrapper { return Wrapper{ .tag = .A, .data = Union{ .Int = v } }; }`
- main.zig: calls `lib_mod.make(...)`, reads `.data.Int` via std.io.printInt (local std.zig/std_io.zig copies)
- Pre-fix: dump rc=0, gcc-fails on `zT_N undeclared`; post-fix: gcc-clean, prints the value

**`repro/mi_matrix/global_null_init_xmod/`** (lib.zig + main.zig + NOTES.md):
- lib.zig: `var g: ?*Node = null;` at module scope + `pub fn get() ?*Node { return g; }`
- main.zig: imports lib, calls `get()`, prints 1 if null (std.io.printInt)
- Pre-fix: gcc-fails on `incompatible types ... Opt_NN from int`; post-fix: gcc-clean, prints `1`

### 4.2 I — Batched investigation (confirm at HEAD + tech docs)

Two I-tasks confirm both mechanisms at HEAD (the explore found the loci; re-confirm the source at HEAD, verify the 2 repros reproduce the exact errors), verify MD5 blast radius (grep the 4 gates — gol/lisp/json/mud — for bare-union literals + module-scope optional null globals; expected: none, so byte-identical), update tech docs `05_semantic_analysis.md`, `07_lir_lowering.md`, `08_c89_emission.md`. Combined STOP for operator ruling.

### 4.3 F1 — Defect A fix

Add `union_type` to sema `resolveStructInit` (:1029) + lower field-loop (:3363-3421) + `emitFieldAssign` (c89_emit.zig:188). Gate: `union_literal_nested_xmod` green (dump/gcc/run rc=0, prints value).

### 4.4 F2 — Defect B fix

Add coercion record to `main.zig:400-441` global-init path. Gate: `global_null_init_xmod` green (dump/gcc/run rc=0, prints `1`).

### 4.5 R2 — Create 2 Defect-C repros

**`repro/mi_matrix/nested_field_store_xmod/`** (same-module): struct-in-struct (`Outer { tag, inner: Inner { a, b } }`), `build()` does `o.inner.a = v; o.inner.b = v+1;`, main prints `.inner.a/.inner.b`. Pre-fix: dump/gcc rc=0, run prints garbage (write-back dropped); zig0 oracle prints `4243`.

**`repro/mi_matrix/nested_field_store_xmod2/`** (cross-module): types defined in lib.zig, store in main.zig. Pre-fix: garbage; oracle prints `78`.

### 4.6 I2 — Defect-C investigation

Confirm mechanism at HEAD (both repros run garbage), determine fix locus + approach (extend `lowerLValueAddr` field_access vs route `lowerFieldStore` nested-base through address), assess blast radius (which examples/repros/gates use nested field-store), update `07_lir_lowering.md`. Combined STOP for operator ruling.

### 4.7 F4 — Defect C fix

Per I2 ruling. Gate: both repros green (correct values); lisp_interpreter no longer SEGFAULTS; F1/F2 repros green; 4 MD5s byte-identical or re-baselined per AMENDMENT B.

### 4.8 F3 — Gate sweep + fold further cleanup

Full 21-example matrix — **`lisp_interpreter` must dump/gcc/link/run rc=0** (the headline goal). 4 repros green. 4 MD5 gates byte-identical. Corpus no new FAIL. **If ANOTHER pre-existing defect surfaces once lisp_interpreter fully compiles, STOP and present — do not silently expand scope.** EXPECTED_FAIL.md v30 + QUICK_REF + tech docs.

## 5. Gates

- `lisp_interpreter` dump/gcc/link/run rc=0 (21/21 examples)
- 4 new repros green (dump/gcc/link/run, correct runtime output)
- 4 MD5s byte-identical UNLESS operator-approved re-baseline: gol `ff47d18d…`, lisp `c1cb748b…`, json `376fd681…` (post-F2 re-baseline — module-scope int-literal coercion now recorded, runtime byte-identical per AMENDMENT B), mud `fd0fdaa4…` (mud not a gate)
- Corpus no new FAIL (current OK=235/FAIL=3/GG=4/242)
- test_analyzer_bin PASS

## 6. Blast Radius

- **Repros** `union_literal_nested_xmod` + `global_null_init_xmod` + `nested_field_store_xmod` + `nested_field_store_xmod2`: FAIL→OK.
- **lisp_interpreter**: gcc-FAIL→FULL OK (Defects A+B+C all fixed; no SEGFAULT at run).
- **Defect C general scope**: any `a.b.c = x` (2+ level field-access lvalue) across struct/union/ptr, same-module + cross-module. I2 audits which examples/repros currently use nested field-store; gates using it would re-baseline (AMENDMENT B). `lisp_interpreter_curr` uses whole-value assignment (unaffected).
- **MD5 gates**: none use bare-union literals or module-scope optional null globals (verify in I) → byte-identical.
- **Corpus**: no new FAIL (the 2 repros are new, added to OK).

## 7. Out of Scope

- **The 3 Important latents from the std-lib final review** (WSAStartup Win gap, D2 std_arena instance bug, untested Win arms) — tracked separately.
- **The 6 Minor follow-ups** from the std-lib final review.
- **16-bit emission** — future concern.
