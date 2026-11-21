# Corpus-RED Fixes Design Spec

**Date:** 2026-08-03
**Status:** Draft
**Investigation:** I-R1..I-R7 (`.superpowers/sdd/I-R1..I-R7-report.md`)

## Goal

Fix 7 root-cause clusters spanning 19 RED repros (FAIL+ICE+runtime-gap) in the Z98→C89 compiler pipeline. Principle: fix root causes at their source in the pipeline, not symptoms at emission sites. Each fix gates its repros from FAIL/ICE/gap to OK.

## Architecture

Fixes ordered from most upstream (pipeline orchestration) to most downstream (specific semantic gaps). All are pipeline-independent — no fix depends on another.

```
main.zig (pipeline) ──→ type_resolver.zig ──→ semantic_analyzer.zig ──→ lower.zig ──→ c89_emit.zig
     F-7                        F-1, F-2, F-3, F-4              F-6               F-5             —
```

## Fix Categories

### F-1: Bare Error Set = Inferred (I-R2)

**Repros (2):** `inferred_errorset_fnptr` (ICE 3011→OK), `inferred_errorset_xmod` (ICE 3011→OK)

**Files:** `sf/src/type_resolver.zig:727`, `sf/src/semantic_analyzer.zig:1160-1184`

**Root cause:** Design contract violation. `TYPE_SYSTEM_p2.md:183` specifies `error_set = 0` for bare/inferred `!T`. Implementation at `type_resolver.zig:727` hardcodes an empty concrete error_set (`typeRegistryGetOrCreateErrorSet(reg, 0, 0)`). `EUPayload.error_set` is immutable, no inference pass exists — returned `error.Bad` fails `typeRegistryErrorSetMemberIndex` → ERR_3011.

**Fix:** Restore design contract. `0` = inferred.
- `type_resolver.zig:727`: `eu_es_box[0] = @intCast(u32, 0);` (was: `typeRegistryGetOrCreateErrorSet(...)`)
- `semantic_analyzer.zig:1168`: add `es == 0` wildcard branch — return `top` (error_union_type) directly, accepting any error literal. Z98 spec §73 mandates this.

**Gate:** Both repros dump rc=0, gcc clean, print 0. Corpus `165/15/6/0` preserved. 4 md5s byte-identical (I-R2 repros weren't in the 4 gated examples).

---

### F-2: Struct FieldEntries Back-Patch (I-R3)

**Repros (1):** `fn_ptr_struct_field` (FAIL, gcc `void write_fn`→OK)

**Files:** `sf/src/type_resolver.zig:622-673`, `sf/src/c89_emit.zig:1438-1453`

**Root cause:** `type_resolver.zig:622-673` builds SEPARATE `anon_N` struct with resolved FieldEntry types but never back-patches the NAMED struct's FieldEntries → fields stay at pre-registered `TYPE_VOID`. `emitStructType` reads `fe.type_id` = TYPE_VOID → emits `void write_fn;`.

**Fix:**
- `type_resolver.zig:669-672`: after `anon_N` built, back-patch named struct's FieldEntries — resolve name_id from name cache, walk `fe_items[fields_start..+count]`, copy `type_id` from corresponding anon_N entries (~10 lines)
- `c89_emit.zig:1447`: defensive void-field guard (`if fe.type_id != TYPE_VOID`) matching `emitTaggedUnionType:1410` pattern

**Gate:** `fn_ptr_struct_field` gcc clean, header shows proper fn-ptr typedef (`void (*write_fn)(...);`). Corpus `165/15/6/0`. 4 md5s byte-identical.

---

### F-3: Bare Union Type Resolution + Field-Store (I-R5 T1b + I-R7 void-union)

**Repros (4):** `tu_field_store_ptr` (ICE→OK), `tu_ptrcast_copy` (ICE→OK), `xmod_amp_arena_union_store` (ICE→OK), `tu_uninit_data_void` (FAIL, gcc `void Int`→OK)

**Files:** `sf/src/type_resolver.zig:886-937`, `sf/src/lower.zig:763-793`

**Root cause:** `resolveDeclAggregateFieldTypes` has no `union_type` branch. Bare union fields stay `TYPE_VOID` → `emitStructType` emits `void fieldname;` (I-R7). `lowerFieldStore` has no union_type branch → ICE at `lower.zig:793` (I-R5 T1b).

**Fix:**
- `type_resolver.zig:911-934`: add `union_type` branch matching `struct_type` branch — resolve each field's type annotation (`child_0`) via `resolveTypeExprFull`, write into `fe_items[fs+i].type_id`
- `lower.zig:763-793`: add `union_type` branch in `lowerFieldStore` — same `store_field` emission as `struct_type` (bare unions share C struct representation)

**Gate:** All 4 repros gcc clean / no ICE. Corpus `165/15/6/0`. 4 md5s byte-identical.

---

### F-4: Cross-Module Resolved Type Cache (I-R1#2 + I-R5 T2)

**Repros (3):** `ptrcast_slice_field_type` (FAIL, gcc `'s' undeclared`→OK), `ptrcast_slice_field_void` (ICE→OK), `ptrcast_slice_field_xmod` (ICE→OK)

**Files:** `sf/src/semantic_analyzer.zig` (field_access resolution, struct_init resolution)

**Root cause:** `resolvedTypeTable` maps node_idx→TypeId. Lowerer queries it for `var s = S{...}` init (node.child_1) and `s.key = ...` field-store base (node.child_0). Cross-module types pass through semantic analysis correctly (struct_init resolves to proper TypeId, field_access resolves base type), but the cache entry isn't written at the node the lowerer queries — lowerer queries struct_init/field_access nodes, but cache entries may live only on the ident_expr leaf.

**Fix:** Ensure `resolvedTypeTableSet` at the struct_init node in `semanticAnalyzerResolveStructInit` (`semantic_analyzer.zig:937`) and at the field_access node in field-access resolution. Extend existing `9672c45f` precedent (~5-10 lines).

**Gate:** All 3 repros gcc clean / no ICE. Corpus `165/15/6/0`. 4 md5s byte-identical.

---

### F-5: Temp-Zero Sentinel Removal (I-R6)

**Repros (1):** `field_store_drop` (FAIL, gcc undeclared→OK)

**Files:** `sf/src/lower.zig:1398, :934-938, :662, :1626-1627`

**Root cause:** Temp id 0 is valid (first param), but is used as a secondary "no value" sentinel alongside `TEMP_NONE=0xFFFFFFFF`. `plain_assign:1398` skips store when `src == 0`, conflating "no value" with "first param value". `nameMapGet:937` returns 0 as not-found. Callers at `:662`, `:1626` default to 0.

**Fix:** Remove sentinel collision:
- `lower.zig:1398`: drop `or src == @intCast(u32, 0)` — only `src == TEMP_NONE` skips store
- `lower.zig:937`: `return TEMP_NONE;` (was: `return @intCast(u32, 0);`)
- `lower.zig:662`: `var operand_temp: u32 = TEMP_NONE;`
- `lower.zig:1626`: `var arr_temp: u32 = TEMP_NONE;`

**Gate:** `field_store_drop` gcc clean. Corpus `165/15/6/0`. 4 md5s byte-identical.

---

### F-6: Orelse RHS Resolution (I-R4 Bug 1)

**Repros (1):** `anon_init_orelse_rhs` (FAIL, gcc incompatible types→OK)

**Files:** `sf/src/semantic_analyzer.zig:794-820`

**Root cause:** `semanticAnalyzerResolveOrelseExpr` resolves `child_0` (optional) but never `child_1` (RHS fallback). Anon struct-init on RHS has no expected type → TYPE_VOID → lowerer falls to plain-int temp → gcc incompatible types. Prior operator deferral 2026-07-09.

**Fix:** Push `opt.payload` as expected type, resolve `node.child_1`, pop. Same pattern as var-decl init at `semantic_analyzer.zig:1602` (~5 lines).

**Gate:** `anon_init_orelse_rhs` gcc clean, emits proper `.payload.Go._0 = 6` on orelse path. Regression: corpus sweep to verify `orelse_void`/`optstar_void_orelse` still byte-identical.

---

### F-7: Module-Global Init (I-R1#1 + I-R7 comptime)

**Repros (6):** `module_var_mutable` (FAIL→OK), `module_pub_var_int` (runtime gap→prints 43), `module_pub_var_struct` (runtime gap→prints 7), `module_const_fn_call` (runtime gap→prints 42), `comptime_neg_int` (runtime gap→prints -5), `var_declared_void` (FAIL→OK or stays FAIL if sema rejects void vars)

**Files:** `sf/src/main.zig:587-588`, `sf/src/lower.zig:1020-1028`, `sf/src/c89_emit.zig`

**Root cause:** Pipeline wall. `phase_LIRLowering` loop at `main.zig:580-588` only handles `AstKind.fn_decl` → empty `else {}`. Module-scope `var_decl`/`const` is correctly parsed, symbol-registered, type-resolved, and semantically analyzed — but never lowered to LIR. `load_global`/`store_global` LIR insts (lir.zig:73-74, c89_emit.zig:3012-3033) exist but are never emitted by the lowerer.

**Fix — Option A (module constructor function):**
- `main.zig:587-588`: for each `var_decl` with `child_1 != 0` (has init), create a synthesized `__module_init` LIR function with `store_global` for each init. Append to `lir_fns`.
- `lower.zig:1020-1028` (`lowerGlobalRef`): for mutable globals or non-literal-inits, emit `load_global` (not `decl_local`). Existing code handles immutable literal consts fine.
- `c89_emit.zig`: new emission pass in `emitModule`/`emitModuleFile` for global variable C declarations (`int x;` / `struct Writer out;`). If `__module_init` in fns, call it in main wrapper before dispatching to user `main()`.

**Sub-options rejected:**
- Option B (inline-init in main): doesn't work for multi-module — each module needs its own init
- Option C (C initializer): fails for function-call inits (not valid C89 initializer expression)

**Gate:** All 6 repros verify: 3 FAIL→gcc clean, 3 runtime gap→correct values (43, 7, 42, -5). `var_declared_void`: if sema doesn't reject void vars, gcc still fails ('x' undeclared) — acceptable, the deeper fix is sema rejecting void-typed variables. Regression: all 4 md5 baselines byte-identical. Corpus `165/15/6/0`.

---

## Dependency Order

All fixes are pipeline-independent (no fix depends on another). Recommended execution order by pipeline phase (most upstream first):

```
Build 1 — type system correctness (type_resolver + sema):
  F-1 → F-2 → F-3 → F-4

Build 2 — semantic + lowerer:
  F-5 → F-6

Build 3 — pipeline foundation (main + lower + c89_emit):
  F-7
```

## Success Criteria

- All 19 RED repros verified from FAIL/ICE/gap → OK
- Corpus baseline `165/15/6/0` (no regression, FAIL count decreases)
- 4 md5 baselines byte-identical (mud `9fde02d8`, gol `d0d3051d`, lisp `10d09c99`, json `3492a935`)
- Build 0 errors, `test_analyzer_bin` PASS
- `build_test.sh` identical to pre-fix baseline (5/4)
