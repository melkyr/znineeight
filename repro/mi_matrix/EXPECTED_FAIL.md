# mi_matrix corpus — expected-fail manifest (v5 2026-07-14)

## Totals (145 repros)

- **CURRENT: OK=142 / FAIL=2 / ICE=1 / CRASH=0** (2026-07-14: corpus-failure-fix A1+B1 — EU payload mismatch hard error, optional type naming fix resolves 3 ??*T orelse FAILs)
- Prior: OK=136 / FAIL=5 / ICE=1 / CRASH=0 (2026-07-14: sema-diagnostics v2)
- Prior: OK=122 / FAIL=15 / ICE=1 / CRASH=0 (2026-07-13: xmod_field_store_index fixed)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline)

---

## ICE (1 — `error[3042]` ERR_9001_ICE, invalid temp index 0)

- `euvoid_val_catch` — `error[3042]`: invalid temp index 0 (len 0). Root cause: `lowerExprImpl` returns temp 0 for `AstKind.error_literal`, flowing into `materializeInto` → `getTempType(0)`. Dump rc=3, 0 bytes C output. Also produces sema warning[3000] but ICE fires regardless at lowerer.

---

## FAIL (2)

- `opt_extern_ptr_file` — gcc `incompatible types when assigning to type 'Opt_...' from type 'int'` (optional wrapping extern-fn pointer return, no null-wrap). Layer: sema/type-registry. Oracle: OK. **Must-not-fail per operator, deferred.**

- `lzw_local_var_undeclared` — gcc `'buf' undeclared` (local array in `else {}` block loses C declaration). Layer: lowerer/c89_emit local scope. **New repro 2026-07-14, deferred.**

---

## Repro added 2026-07-14

- `field_access_optional` — **FIXED (ERR_3000)** — `?S.x` now produces `error[3000]: cannot access field on optional type` instead of lowerer ICE. Matches zig0 oracle (rejects `.` on optional). Green guard — no C emitted.

- `lzw_error_set_typedef` — **GREEN at HEAD** — simple error-union case passes. Full lzw example triggers the gap via cross-module named error set references. Green guard kept.

- `lzw_local_var_undeclared` — **FAIL** — see above. Deferred.

---

## Previously FIXED (2026-07-14)

- `eu_assign_incompat_payload` — **FIXED** — `E!i64 → E!i32` now emits `error[3000]` at sema (EU payload mismatch severity check). Previously gcc FAIL.
- `euoptptr_val_orelse` — **FIXED** — optional C typedef naming now uses `getCTypeName` instead of `name_id=0`. Distinct C structs for `?*i32` vs `??*i32`.
- `optptr_val_orelse` — **FIXED** — same c89_emit fix.
- `optptr_null_orelse` — **FIXED** — same c89_emit fix.
- `eu_assign_incompat_errorset` — **WARNING** — different error sets produce warning[3000] but same C struct compiles. Correctly not blocking.
- `typeres_unhandled_node` — **FIXED (2026-07-14)** — range handler + lowerer demote.

## Previously FIXED (2026-07-13)

- `xmod_field_store_index` — EX1 fix (broad name-cache prepass)
- `array_value_copy` — EX3 fix (indexed elem type + emitter)
- `array_manyptr_type` — EX4 fix (c89_emit * sanitize)
- `func_ptr_return_type` — EX5 fix (FN_/FP_ prefix + ident_expr)
