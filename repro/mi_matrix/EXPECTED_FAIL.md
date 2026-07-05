# mi_matrix corpus — expected-fail manifest (v4 idiomatic baseline)

## Totals (132 repros)
- **NEW (idiomatic): OK=94 / FAIL=37 / CRASH=1**
- OLD (@as-era): OK=72 / FAIL=38 / CRASH=22
- Delta: **+22 OK, -1 FAIL, -21 CRASH** — expected shift: corpus now tests implicit coercion (no `@as`, named error sets, `?E!T` kept as target).

---

## CRASH (1 — SEGV / ASAN abort, not a parse error)

- `euvoid_val_catch` — `zF_96d35854_63f9b65b_getTempType` SEGV

---

## FAIL (37) grouped by gcc error

### `incompatible types when assigning to type 'zT_733AFA29_…` (11)
euoptptr_err_catch
euoptptr_val_catch
opteu_err_if_expr
opteu_err_switch
opteu_null_if_expr
opteu_val_catch
optopt_null_if_expr
optopt_val_if_expr
optptr_null_if_expr
optptr_null_orelse
optptr_val_if_expr

### `incompatible types when assigning to type 'zT_4E757CD1_…` (5)
euopt_err_assign
euopt_err_if_expr
euopt_err_var_decl
euopt_val_if_expr
euoptptr_err_call_arg

### `incompatible types when assigning to type 'zT_0DA61B72_…` (4)
eu_err_assign
eu_err_if_expr
eu_err_var_decl
eu_val_if_expr

### `incompatible types when assigning to type 'zT_3F70E806_…` (4)
eunum_err_assign
eunum_err_if_expr
eunum_err_var_decl
eunum_val_if_expr

### `incompatible types when assigning to type 'zT_0BF1F60F_…` (4)
euopt_err_catch
euopt_val_catch
opt_null_if_expr
opt_val_if_expr

### `incompatible types when assigning to type 'zT_D4788E5A_…` (3)
euoptptr_err_assign
euoptptr_err_if_expr
euoptptr_err_var_decl

### `incompatible types when assigning to type 'zT_30A21E0E_…` (2)
optnum_null_if_expr
optnum_val_if_expr

### `incompatible types when assigning to type 'int *' from …` (2)
euoptptr_val_orelse
optptr_val_orelse

### `incompatible types when assigning to type 'zT_D67AD017_…` (1)
euoptptr_val_if_expr

### `request for member 'has_value' in something not a struct…` (1)
opteu_null_orelse
