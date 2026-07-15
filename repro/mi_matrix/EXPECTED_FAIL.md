# mi_matrix corpus — expected-fail manifest (v5 2026-07-14)

## Totals (148 repros)

- **CURRENT: OK=144 / FAIL=1 / ICE=3 / CRASH=0** (2026-07-15: lowerer-errors-deep-dive — F1 euvoid_val_catch block handler FIXED, F2 SEGV→error[3042] diagnostic guard on C5/C6/C7, F3 lzw_local_var_undeclared cache FIXED)
- Prior: OK=142 / FAIL=3 / ICE=3 / CRASH=0 (2026-07-14: Phase D repros)
- Prior: OK=136 / FAIL=5 / ICE=1 / CRASH=0 (2026-07-14: sema-diagnostics v2)
- Prior: OK=122 / FAIL=15 / ICE=1 / CRASH=0 (2026-07-13: xmod_field_store_index fixed)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline)

---

## ICE (3 — clean error[3042] exits, no SEGV)

- `lzw_cross_module_error_set` — `error[3042]: non-value base expression in field access`. Cross-module error set reference. Diagnostic guard (F2) prevents SEGV. zig0 oracle: OK. **Deferred.**

- `lzw_error_set_member_comparison` — `error[3042]: non-value base expression in field access`. Error set member constant `E.A` in comparison triggers non-value base path. Diagnostic guard prevents SEGV. zig0 oracle: OK. **Deferred.**

- `lzw_eu_return_mismatch` — `error[3042]: non-value base expression in field access`. `catch |err| return err` TypeId mismatch triggers non-value base path. Diagnostic guard prevents SEGV. Same crash class, different trigger. zig0 oracle: OK. **Deferred.**

---

## FAIL (1)

- `opt_extern_ptr_file` — gcc `incompatible types when assigning to type 'Opt_...' from type 'int'` (optional wrapping extern-fn pointer return, no null-wrap). Layer: sema/type-registry. Oracle: OK. **Must-not-fail per operator, deferred.**

---

## FIXED (2026-07-15 — lowerer-errors-deep-dive)

- `euvoid_val_catch` — **FIXED (F1)** — `lowerExprImpl` now handles `AstKind.block` in expression context. `return {}` coerced to `E!void` no longer ICEs.
- `lzw_local_var_undeclared` — **FIXED (F3)** — sema now caches non-ident type annotations (`[256]u8`, `*T`, `?T`) in `resolvedTypeTable`. Lowerer can emit `decl_local` — `buf` declared in C.
- `lzw_error_set_member_comparison` — **PARTIAL (F2)** — SEGV converted to clean `error[3042]` diagnostic (no crash). Error set member emission still pending.
- `lzw_cross_module_error_set` — **PARTIAL (F2)** — SEGV converted to clean `error[3042]` diagnostic. Cross-module error set reference resolution still pending.
- `lzw_eu_return_mismatch` — **PARTIAL (F2)** — SEGV converted to clean `error[3042]` diagnostic. EU TypeId mismatch resolution still pending.

## Repro added 2026-07-14

- `field_access_optional` — **FIXED (ERR_3000)** — `?S.x` now produces `error[3000]: cannot access field on optional type` instead of lowerer ICE. Matches zig0 oracle (rejects `.` on optional). Green guard — no C emitted.

- `lzw_error_set_typedef` — **GREEN at HEAD** — simple error-union case passes. Full lzw example triggers the gap via cross-module named error set references. Green guard kept.

- `lzw_local_var_undeclared` — **FAIL** — see above. Deferred.

- `lzw_cross_module_error_set` — **ICE** — SEGV crash (AddressSanitizer) in lowerExprImpl. Cross-module error set reference. **New repro 2026-07-14, deferred.**

- `lzw_error_set_member_comparison` — **FAIL** — error set member constant C typedef never emitted. **New repro 2026-07-14, deferred.**

- `lzw_eu_return_mismatch` — **ICE** — SEGV crash (AddressSanitizer) in lowerExprImpl. `catch |err| return err` TypeId mismatch. Same crash class as lzw_cross_module_error_set. **New repro 2026-07-14, deferred.**

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
