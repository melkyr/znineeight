# mi_matrix corpus — expected-fail manifest (v4 idiomatic baseline)

## Totals (138 repros)
- **CURRENT: OK=117 / FAIL=18 / ICE=3 / CRASH=0** (2026-07-12: +6 example-derived RED repros — see section below)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline) — UNCHANGED by the 6 additions (no existing repro reclassified).
- OLD (@as-era): OK=72 / FAIL=38 / CRASH=22
- Delta (v4 idiomatic vs @as-era): **+45 OK, -24 FAIL, -22 CRASH, +1 ICE** (idiom shift + if_expr branch-join wiring + catch err-branch materialization + materializeInto error_src generalization, all through materializeInto).

---

## ICE (1 — diagnosed, caught by ERR_9001 guard, no SEGV)

- `euvoid_val_catch` — `error[48]`: invalid temp index 0 (len 0). Root cause: `lowerExprImpl` returns 0 for `AstKind.block` (the `{}` void value), flowing into `materializeInto` → `getTempType(0)` where `hoisted_temps.len==0`. Now caught by `ERR_9001_ICE` guard instead of SEGV. Trigger: `E!void` with implicit coercion (block `{}` → error union). `@as(E!void, h()) catch {}` does NOT reproduce (rc=2 parse error).

---

## FAIL (14) grouped by gcc error

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

- `xmod_field_store_index` — **ICE** `error[48]` unsupported field-store base (node 37); layer=lowerer (`iceFieldStoreUnsupported` lower.zig:733/758). Real trigger (Task 7): cross-module `@import` + named-const-sized array-of-struct `[N]struct{x:i32}` + array-element field store `t.arr[0].x=1`; each factor load-bearing (single-file / `[1]` literal / no-store-fn all compile clean). NOT the simple `arr[i].field=x`. Oracle: OK (zig0 dump rc=0, gcc 0). Pure zig1 bug.
- `typeres_unhandled_node` — **ICE** `error[3002]` unhandled node kind in type resolution; layer=type resolution. Minimal trigger: bare range-for `for (1..13) |i| {}`. Oracle: OK (zig0 dump rc=0). Pure zig1 bug.
- `array_value_copy` — **FAIL** `assignment to expression with array type`; layer=c89_emit (array-value copy from `*[N]T` deref should be element-copy loop). Oracle: OK (main.c gcc 0). Pure zig1 bug.
- `array_manyptr_type` — **FAIL** malformed `zT_..._Arr_unsigned_char*_[4]` typedef (stray `*` in mangled name) from `[4][*]const u8{...}`; layer=c89_emit type-name mangling. Oracle: OK (main.c gcc 0). Pure zig1 bug.
- `func_ptr_return_type` — **FAIL** `unknown type name zT_..._FP_int_int_int` (FP-return typedef referenced, never emitted) from `fn(i32,i32) i32` return type; layer=c89_emit. Oracle: OK (main.c gcc 0). Pure zig1 bug.
- `opt_extern_ptr_file` — **FAIL** `incompatible types when assigning to type 'zT_..._Opt_...' from type 'int'` (optional wrapping extern-fn pointer return, no null-wrap) via `const File=void; extern fn fopen(...) ?*File;`; layer=sema/type-registry. Oracle: OK (main.c gcc 0). Pure zig1 bug. (Used `?*File`/`const File=void` idiom, not `@cInclude`, because zig0 aborts on `@cInclude` in this mode; tracked as must-not-fail per operator.)
