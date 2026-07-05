# mi_matrix corpus — expected-fail manifest (v4 idiomatic baseline)

## Totals (132 repros)
- **NEW (idiomatic): OK=111 / FAIL=20 / ICE=1 / CRASH=0**
- OLD (@as-era): OK=72 / FAIL=38 / CRASH=22
- Delta: **+39 OK, -18 FAIL, -22 CRASH, +1 ICE** (+22/+17 OK from idiom shift + if_expr branch-join wiring through materializeInto).

---

## ICE (1 — diagnosed, caught by ERR_9001 guard, no SEGV)

- `euvoid_val_catch` — `error[48]`: invalid temp index 0 (len 0). Root cause: `lowerExprImpl` returns 0 for `AstKind.block` (the `{}` void value), flowing into `materializeInto` → `getTempType(0)` where `hoisted_temps.len==0`. Now caught by `ERR_9001_ICE` guard instead of SEGV. Trigger: `E!void` with implicit coercion (block `{}` → error union). `@as(E!void, h()) catch {}` does NOT reproduce (rc=2 parse error).

---

## FAIL (20) grouped by gcc error

### `incompatible types when assigning to type 'zT_733AFA29_…` (6)
euoptptr_err_catch
euoptptr_val_catch
opteu_err_if_expr
  - NOTE: opteu_err_if_expr is a residual — materializeInto's error_src fast-path does not wrap when the outer layer is optional (?E!T); tracked for a separate materializeInto task.
opteu_err_switch
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

### `incompatible types when assigning to type 'zT_0BF1F60F_…` (2)
euopt_err_catch
euopt_val_catch

### `incompatible types when assigning to type 'zT_D4788E5A_…` (2)
euoptptr_err_assign
euoptptr_err_var_decl

### `incompatible types when assigning to type 'int *' from …` (2)
euoptptr_val_orelse
optptr_val_orelse

### `request for member 'has_value' in something not a struct…` (1)
opteu_null_orelse
