# mi_matrix corpus — expected-fail manifest (v4 idiomatic baseline)

## Totals (138 repros)
- **CURRENT: OK=136 / FAIL=5 / ICE=1 / CRASH=0** (2026-07-14: sema-diagnostics v2 — range handler fixes typeres_unhandled_node, clearer type-mismatch warnings with source/target notes, diagnostic print at normal exit. euvoid_val_catch ICE renumbered 48→ERR_9001_ICE (3042) — same crash, different code, gate pattern updated.)
- Prior: OK=122 / FAIL=15 / ICE=1 / CRASH=0 (2026-07-13: xmod_field_store_index fixed; see EX1 fix)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline) — UNCHANGED by the 6 additions (no existing repro reclassified).
- OLD (@as-era): OK=72 / FAIL=38 / CRASH=22
- Delta (v4 idiomatic vs @as-era): **+45 OK, -24 FAIL, -22 CRASH, +1 ICE** (idiom shift + if_expr branch-join wiring + catch err-branch materialization + materializeInto error_src generalization, all through materializeInto).

---

## ICE (1 — `error[3042]` ERR_9001_ICE, invalid temp index 0)

- `euvoid_val_catch` — `error[3042]`: invalid temp index 0 (len 0). Root cause: `lowerExprImpl` returns temp 0 for `AstKind.error_literal`, flowing into `materializeInto` → `getTempType(0)` where `hoisted_temps` has no entry 0. ICE renumbered from hardcoded 48 to `ERR_9001_ICE` (3042) during sema-diagnostics v2. Dump rc=3, 0 bytes C output. Also produces a sema warning[3000] (type mismatch) but ICE fires regardless at lowerer.

---

## FAIL (5) grouped by gcc error

### `incompatible types when assigning to type 'zT_733AFA29_…` (2)
opteu_val_catch
optptr_null_orelse

### `incompatible types when assigning to type 'zT_4E757CD1_…` (3)
euopt_err_assign
euopt_err_var_decl
euoptptr_err_call_arg

### `incompatible types when assigning to type 'zT_0DA61B72_…` (2)
eu_err_assign
eu_err_var_decl

### `incompatible types when assigning to type 'zT_3F70E806_…` (2)
eunum_err_assign
eunum_err_var_decl

### `incompatible types when assigning to type 'zT_D4788E5A_…` (2)
euoptptr_err_assign
euoptptr_err_var_decl

### `incompatible types when assigning to type 'int *' from …` (2)
euoptptr_val_orelse
optptr_val_orelse

### `request for member 'has_value' in something not a struct…` (1)
opteu_null_orelse

---

## Layer attribution of the remaining 14 (reference)
- **error→EU sema gap (9)**: eu_err_assign, eu_err_var_decl, eunum_err_assign, eunum_err_var_decl, euopt_err_assign, euopt_err_var_decl, euoptptr_err_assign, euoptptr_err_var_decl, euoptptr_err_call_arg. Sema does not record `error.X → E!T` coercion at assign/var_decl/call_arg (value→E!T is recorded). Fix belongs in sema, not a lower patch.
- **`??*T` nested-optional-pointer representation (3)**: optptr_null_orelse, optptr_val_orelse, euoptptr_val_orelse. `Opt<*T>` ↔ raw `int*` collapse — type_registry/c89_emit representation.
- **opteu_val_catch (1)**: `var r: ?E!i32 = h()` — EU→optional wrap coercion not recorded (sema).
- **opteu_null_orelse (1)**: `(null) orelse 42` — degenerate null mistyped (sema).

---

## Example-derived RED repros (2026-07-12) — zig1 must eventually pass

These 6 repros isolate distinct compile failures found compiling `examples/z98/*` with
zig1 at HEAD b206a3f3. All are RED; zig1 must make them pass (fixes = separate future
plans). They ADD to the corpus (117/14/1/0 → 117/18/3/0); no pre-existing repro
reclassified.

- `xmod_field_store_index` — **FIXED (2026-07-13)** — ICE `error[48]` unsupported field-store base resolved by broad name-cache prepass covering non-ident_expr const inits + cross-module symbol lookup in type_resolver.zig. Root: `const N = 1` (int_literal) never cached in name cache → `resolveTypeExprFull` array_type handler could not resolve `[N]struct{...}` size → field type stayed TYPE_VOID → lowerer hit unsupported field-store base. Fix: `resolveNamedTypeExpressions` broad prepass + `varDeclInitNeedsNameCache` predicate + `symbolLookupAllModules` shared helper + `evalConstU32Full` cross-module fix + simplify array_type handler to delegate to `evalConstU32Full`. Repro now dump 0/gcc 0, matches oracle.
- `typeres_unhandled_node` — **FIXED (2026-07-14)** — sema now handles `range_exclusive`/`range_inclusive` node kinds (sets TYPE_U32). Lowerer demotes hardcoded TYPE_U32 fallback to read from resolved type table. Repro now dump 0/gcc 0, matches oracle.
- `array_value_copy` — **FIXED (2026-07-13)** — FAIL `assignment to expression with array type`; layer=lowerer (index_access ptr-to-array element-type now corrected via `typeRegistryIndexedElemType` helper) + c89_emit (`(*a)[i]` syntax emitter). Root: `lower.zig:1444-1445` + `semantic_analyzer.zig:1563-1573` + `c89_emit.zig:2286-2317,2699-2713`. Fix: DRY `typeRegistryIndexedElemType` helper in `type_registry.zig`, 3 index-elem sites converted, `emitBaseIdxAccess` for C89 syntax. Repro now dump 0/gcc 0/run→11, matches oracle.
- `array_manyptr_type` — **FIXED (2026-07-13)** — FAIL malformed typedef (stray `*` in mangled name) from `[4][*]const u8{...}`; layer=c89_emit type-name mangling. Root: `c89_emit.zig:501,1119` identifier-copy loops only sanitized space→`_` but not `*`. Fix: both loops now map `*` (byte 42)→`_`. Repro now dump 0/gcc 0/run→aa, matches oracle.
- `func_ptr_return_type` — **FIXED (2026-07-13)** — FAIL `unknown type name zT_..._FP_int_int_int` (FP-return typedef never emitted + ident_expr missing SymbolKind.function handler emitting `return param` instead of `return add`). Layer=c89_emit + lowerer. Root: `c89_emit.zig:644` cname prefix collision (plain fn vs fn_ptr shared `FP_` prefix causing dedup collision) + `lower.zig:1574` ident_expr handler missing SymbolKind.function arm (fallback returned temp 0 = param). Fix: FN_/FP_ prefix distinction in getCTypeName + explicit SymbolKind.function handler in ident_expr (func_ref emission). Repro now dump 0/gcc 0/run→15, matches oracle.
- `opt_extern_ptr_file` — **FAIL** `incompatible types when assigning to type 'zT_..._Opt_...' from type 'int'` (optional wrapping extern-fn pointer return, no null-wrap) via `const File=void; extern fn fopen(...) ?*File;`; layer=sema/type-registry. Oracle: OK (main.c gcc 0). Pure zig1 bug. (Used `?*File`/`const File=void` idiom, not `@cInclude`, because zig0 aborts on `@cInclude` in this mode; tracked as must-not-fail per operator.)
