# mi_matrix corpus — expected-fail manifest (v4 idiomatic baseline)

## Totals (132 repros)
- **NEW (idiomatic): OK=117 / FAIL=14 / ICE=1 / CRASH=0**
- OLD (@as-era): OK=72 / FAIL=38 / CRASH=22
- Delta: **+45 OK, -24 FAIL, -22 CRASH, +1 ICE** (idiom shift + if_expr branch-join wiring + catch err-branch materialization + materializeInto error_src generalization, all through materializeInto).

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
