# lisp_interpreter Lowerer Defects Fix Design Spec

**Date:** 2026-08-13
**Status:** Approved by operator (design questions m0757/m0763: Option 1 full union_type support; both fixed at sema as upstream; R-task creates 2 minimal repros; F3 folds any further surfaced cleanup). Ready for plan.

## 1. Goal

Make `examples/z98/lisp_interpreter` (the only non-working example) compile + link + run end-to-end, achieving **21/21 examples**. Two sema-rooted lowerer defects gate it: (A) bare-union literal nested in a struct literal drops its construction (`5× zT_N undeclared`); (B) module-scope `var x: ?T = null` global init types the null temp `int` instead of the optional (`1× Opt_49` type mismatch).

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

## 3. Architecture

Both defects are fixed at **sema as the upstream** (operator ruling m0759/m0761), with lowerer/emitter changes only as the necessary downstream completion of the sema resolution. This mirrors the F3 precedent (add the missing type-kind case at sema + lower + emitter) and the function-body coercion-record precedent.

**Defect A (3 layers, sema-rooted):**
1. **sema** `semantic_analyzer.zig:1029` — add `union_type` branch to `semanticAnalyzerResolveStructInit`, mirroring `struct_type` (`:1066-1093`): resolve to the union type, push per-field expected type + record coercion.
2. **lower** `lower.zig:3363-3421` — add `union_type` branch to the struct-init field loop, emitting the field assign (mirroring struct/tagged_union branches).
3. **emitter** `c89_emit.zig:188` `emitFieldAssign` — add `union_type` branch (the sibling `store_field` at :4202 already handles unions; this closes the assign_field asymmetry).

**Defect B (1 layer, sema):**
- `main.zig:400-441` — after resolving the global-init expression, add `classifyCoercion` + `coercionTableAdd` for `decl.child_1`, mirroring `semantic_analyzer.zig:1862-1867`. The existing lowerer null branch then emits `set_optional_null` typed as the optional. Covers `null` AND `undefined` global inits uniformly.

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

### 4.5 F3 — Gate sweep + fold further cleanup

Full 21-example matrix — **`lisp_interpreter` must dump/gcc/link/run rc=0** (the headline goal). 2 repros green. 4 MD5 gates byte-identical. Corpus no new FAIL. **If a THIRD pre-existing defect surfaces once lisp_interpreter fully compiles (the F1 lesson), STOP and present — do not silently expand scope.** EXPECTED_FAIL.md v30 + QUICK_REF + tech docs.

## 5. Gates

- `lisp_interpreter` dump/gcc/link/run rc=0 (21/21 examples)
- 2 new repros green (dump/gcc/link/run)
- 4 MD5s byte-identical: gol `b246a2fe…`, lisp `141994cc…`, json `f50ce1e6…`, mud `fd0fdaa4…` (mud not a gate)
- Corpus no new FAIL (current OK=233/FAIL=3/GG=4/240)
- test_analyzer_bin PASS

## 6. Blast Radius

- **Repro** `union_literal_nested_xmod` + `global_null_init_xmod`: FAIL→OK.
- **lisp_interpreter**: gcc-FAIL→FULL OK (if no third defect).
- **MD5 gates**: none use bare-union literals or module-scope optional null globals (verify in I) → byte-identical.
- **Corpus**: no new FAIL (the 2 repros are new, added to OK).

## 7. Out of Scope

- **The 3 Important latents from the std-lib final review** (WSAStartup Win gap, D2 std_arena instance bug, untested Win arms) — tracked separately.
- **The 6 Minor follow-ups** from the std-lib final review.
- **16-bit emission** — future concern.
