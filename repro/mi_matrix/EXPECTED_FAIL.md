# mi_matrix corpus — expected-fail manifest (v5 2026-07-14)

## Totals (148 repros)

- **CURRENT: OK=142 / FAIL=3 / ICE=3 / CRASH=0** (2026-07-14: Phase D — lzw cross-module error_set + EU return mismatch SEGV ICEs, error member comparison FAIL)
- Prior: OK=136 / FAIL=5 / ICE=1 / CRASH=0 (2026-07-14: sema-diagnostics v2)
- Prior: OK=122 / FAIL=15 / ICE=1 / CRASH=0 (2026-07-13: xmod_field_store_index fixed)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline)

---

## ICE (3 — 1 pre-existing + 2 new via Phase D)

- `euvoid_val_catch` — `error[3042]`: invalid temp index 0 (len 0). Root cause: `lowerExprImpl` returns temp 0 for `AstKind.error_literal`, flowing into `materializeInto` → `getTempType(0)`. Dump rc=3, 0 bytes C output. Also produces sema warning[3000] but ICE fires regardless at lowerer.

- `lzw_cross_module_error_set` — **NEW** — SEGV (AddressSanitizer) in `lowerExprImpl` at 0x94 (null deref). Cross-module error set reference triggers crash. 0 bytes C output. zig0 oracle: OK (gcc rc=0). **New repro 2026-07-14, deferred.**

- `lzw_eu_return_mismatch` — **NEW** — SEGV (AddressSanitizer) in `lowerExprImpl` at 0x94 (null deref). `catch |err| return err` where returned EU TypeId differs from declared type. 0 bytes C output. zig0 oracle: OK (gcc rc=0). Same crash class as lzw_cross_module_error_set, different trigger. **New repro 2026-07-14, deferred.**

---

## FAIL (3)

- `opt_extern_ptr_file` — gcc `incompatible types when assigning to type 'Opt_...' from type 'int'` (optional wrapping extern-fn pointer return, no null-wrap). Layer: sema/type-registry. Oracle: OK. **Must-not-fail per operator, deferred.**

- `lzw_local_var_undeclared` — gcc `'buf' undeclared` (local array in `else {}` block loses C declaration). Layer: lowerer/c89_emit local scope. **New repro 2026-07-14, deferred.**

- `lzw_error_set_member_comparison` — **NEW** — gcc `unknown type name zT_C00BF080_E` + `'zT_3' undeclared`. Error set member constant `E.A` used in `e == E.A` comparison — C enum/#define never emitted. zig0 oracle: OK (gcc rc=0). **New repro 2026-07-14, deferred.**

---

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
