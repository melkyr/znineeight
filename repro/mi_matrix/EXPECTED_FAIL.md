# mi_matrix corpus — expected-fail manifest (v13 2026-07-30)

## Totals (179 repros)

- **CURRENT: OK=165 / FAIL=6 / ICE=7 / CRASH=0** (2026-07-30: syntax coverage — 13 new repros for categories A-E: hand-rolled tagged unions, bare error sets, catch blocks, ptr-to-int arena, module var, define-mutate-closure. 7 ICEs are hand-rolled tagged union field-stores (A1-A3) and inferred error set function pointers (B1-B2). All GREEN regression guards pass. 2 new FAILs from uninitialized union data (A2) and @intToPtr arena (D).)
- Prior: OK=162 / FAIL=4 / ICE=0 / CRASH=0 (2026-07-16: extern-fn ABI-wrap — c89_emit .call_direct wrapping for extern fn optional/EU returns; 5/5 extern-fn repros fixed; opt_extern_ptr_file FIXED; json_parser HARD gate 0 errors; EU representation (3) now FIXED by error-set pipeline)
- Prior: OK=148 / FAIL=14 / ICE=0 / CRASH=0 (2026-07-16: folded 13 ungated RED repros from top-level `repro/` tree into gated corpus)
- Prior: OK=148 / FAIL=1 / ICE=0 / CRASH=0 (2026-07-16: error-set crash fix chain — F-SEMA Gap A/B sema arms + shared helper `typeRegistryErrorSetMemberIndex`; F-C5C7 Fix A+B valid module/type_alias temps + Fix C symreg `populateTypePayload` error_set_decl case + Fix E/F lowerer member lookups + module-base field_access branch; F-LISP module-qualified fn refs via func_ref machinery; F-C6 c89_emit `emitErrorSetType` typedef + per-member `#define` constants; F-TEMPNONE dedicated temp-index sentinel `TEMP_NONE=0xFFFFFFFF`; F-REMOVE unconditional 3042 tripwire + module-as-value warning[3023] + observability repro)
- Prior: OK=147 / FAIL=1 / ICE=0 / CRASH=0 (2026-07-15: error-set pipeline fix — T1 symbol_reg, T2 sema, T3 lowerer, T4 c89_emit)
- Prior: OK=144 / FAIL=2 / ICE=2 / CRASH=0 (2026-07-14: Phase D repros — actual state; earlier manifest erroneously claimed 147/1/0/0)
- Prior: OK=136 / FAIL=5 / ICE=1 / CRASH=0 (2026-07-14: sema-diagnostics v2)
- Prior: OK=122 / FAIL=15 / ICE=1 / CRASH=0 (2026-07-13: xmod_field_store_index fixed)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline)

---

## ICE (7 — all from syntax coverage category A-E, 2026-07-30)

7 new ICE repros added for categories A-E. All hand-rolled tagged union patterns (A1-A3) trigger `error[3043]: internal: unsupported field-store base`. Inferred error set patterns (B1-B2) trigger `error[3011]: error literal not found in error set`.

### Error[3043] — hand-rolled tagged unions (3)
- `tu_field_store_ptr` — union field-store through @ptrCast pointer
- `tu_uninit_data_void` — uninitialized union data for void-variant tag
- `tu_ptrcast_copy` — hand-rolled tagged union copy through @ptrCast

### Error[3011] — bare `!` error sets (2)
- `inferred_errorset_fnptr` — @ptrCast to fn(!T) through *void
- `inferred_errorset_xmod` — cross-module bare ! error inference

### Error[2000] — parser (2, defined in category F)
- `define_mutate_closure` — `fn (i32) i32` type syntax not parseable
- `define_mutate_closure_green` — same parse failure

**Prior:** All error-set SEGV/ICE crashes eliminated. **Accidental-revert history:** commit `a4bb08c4` ("use structural hash for optional C typedef naming") accidentally reverted 4 earlier error-set commits — `9f2236e2` (c89_emit error_set typedef + member emission), `c0803328` (symreg error_set payload population), `d0104d33` (sema error_set member handlers), `b4d78651` (lowerer module-base field_access branch) — which is why an earlier manifest claimed 147/1/0/0 when actual was 144/2/2/0. This plan's upstream fix chain correctly restored all 4 layers.

- `lzw_cross_module_error_set` (C5) — **FIXED** — was ICE (SEGV at hoisted_temps[18] OOB). Fixed by: sema member resolution via shared helper, symreg payload, lowerer valid module temp + module-base field_access branch + member lookup via helper, c89_emit cross-module typedef emission.
- `lzw_error_set_member_comparison` (C6) — **FIXED** — was ICE → partial F2 error[3042] → now compilable C. Fixed by: sema Gap A/B arms, c89_emit `emitErrorSetType` typedef + per-member `#define` ordinals.
- `lzw_eu_return_mismatch` (C7) — **FIXED** — was ICE (SEGV same class as C5). Fixed by: sema member resolution, symreg payload, lowerer valid type_alias temp + member lookup via helper, `.is_error=1` wrap_error_err EU-wrap coercion path.

---

## FIXED (2026-07-16 — optional-wrap coercion family: 6/7)

### Orelse unwrap (F-REPROFIX + F-SEMA-ORELSE)
- `orelse_void` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (orelse void coercion). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.
- `optstar_void_orelse` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (*void orelse coercion). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.
- `file_const_single` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (file-level const optional). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.

### Catch EU unwrap (F-SEMA-CATCH + F-CATCHRETURN)
- `eu_optional_value` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (error union optional value). Fixed by: sema :1187 coercion recording + lower.zig `lowerExprOrBlock` stmt routing.
- `mi_eu_opt_val` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (module-import variant of eu_optional_value). Fixed by: sema :1187 coercion recording + lower.zig `lowerExprOrBlock` stmt routing.

### Var_decl type pollution (F-LOWERIDENT2)
- `opt_value_decl` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (optional payload in decl init). Previously fixed by band-aid `3c8c1e92`, now fixed at ROOT via sema :1559 guard against resolvedTypeTable pollution.

---

### FIXED by extern-fn ABI-wrap (1)
- `opt_extern_ptr_file` — **FIXED (F-ABI)** — was deferred `??*T FILE* gateway`. extern-fn ABI-wrap (`c89_emit .call_direct` wrapping for extern fn optional/EU returns) now wraps raw `FILE*` into `Opt_*` type. gcc 0 errors. No longer deferred.
---

## FAIL (6)

### VOID decl-skip / undeclared-temp (2) — out-of-scope
- `var_declared_void` — gcc `'x' undeclared` (VOID-typed variable skipped in C decl emission).
- `field_store_drop` — gcc `'zT_23'/'zT_32' undeclared` (undeclared temps from field-store lowering; related to var_declared_void VOID-decl-skip path).

### Aggregate / anon-init (2) — out-of-scope
- `anon_init_orelse_rhs` — gcc `incompatible types` (anonymous init on orelse RHS).
- `array_tagged_union_read` — gcc `incompatible types` (tagged union indexing on array).

### Syntax coverage new FAILs (2) — 2026-07-30
- `tu_uninit_data_void` — gcc `void tag/data declared` (hand-rolled tagged union with uninitialized data variant).
- `module_var_mutable` — gcc `'x' undeclared` (global mutable var, C emission misses global declaration).

Note: FAIL=4 count reflects 2 remaining out-of-scope families (VOID decl-skip, aggregate/anon-init) = 4 repros total (2+2). EU representation (3 repros: eu_err_ret, eu_value_ret, mi_eu_err) now FIXED by error-set pipeline (F-C5C7 Fix A/B) — gcc 0 errors.

---

## Folded 13 RED repros (2026-07-16)

Gated 13 ungated top-level repros into `repro/mi_matrix/` corpus. **As of 2026-07-16, 9/13 FIXED (see FIXED sections above).** Remaining 4 still classify as FAIL (gcc errors):

- **EU representation** (3): `eu_err_ret`, `eu_value_ret`, `mi_eu_err` — **FIXED by error-set pipeline (F-C5C7 Fix A/B)** — gcc 0 errors. Was previously FAIL (incompatible types in error-union payload/return coercion).
- **VOID decl-skip / undeclared-temp** (2): `var_declared_void` — `'x' undeclared` (VOID-typed variable skipped in C declaration). `field_store_drop` — `'zT_23'/'zT_32' undeclared` (undeclared temps from field-store lowering; same root cause as var_declared_void VOID-decl-skip path). Fix owned by future plan.
- **Aggregate / anon-init** (2): `anon_init_orelse_rhs` — anon init on orelse RHS. `array_tagged_union_read` — tagged union indexing on array.

---

## Repro added 2026-07-16

- `module_as_value` — **OK (warning[3023] non-fatal)**. Bare module ident in value position (`_ = h;`) emits `warning[3023]: module used as value expression`. VOID temp prevents C-decl pollution (TYPE_VOID=1 skipped by c89_emit decl loop). zig0 oracle: accepts silently (rc=0). C compiles cleanly (gcc 0 errors). Class: OK.

---


## FIXED (2026-07-16 — extern-fn ABI-wrap: 5/5)
- `opt_extern_ptr_file` — **FIXED (F-ABI)** — was deferred `??*T FILE* gateway`. extern-fn ABI-wrap (`c89_emit .call_direct` wrapping for extern fn optional/EU returns) now wraps raw `FILE*` into `Opt_*` type. gcc 0 errors. No longer deferred.
- `extern_fn_opt_return` — **OK (F-ABI)** — optional return from extern fn; ABI-wrap emits wrapper that calls extern, builds `Opt_*` struct from raw return. gcc 0 errors.
- `extern_fn_opt_return_cross` — **OK (F-ABI)** — cross-module variant of extern_fn_opt_return. gcc 0 errors.
- `extern_fn_eu_return` — **OK (F-ABI)** — error-union return from extern fn; ABI-wrap emits caller-side wrapper. gcc 0 errors.
- `error_set_unknown_member` — **OK (F-ABI)** — error-set member resolution across modules; was expected FAIL per original plan but passes gcc 0 errors after extern-fn ABI fixes. Class: OK (not fail).

---

## FIXED (2026-07-15 — lowerer-errors-deep-dive)

- `euvoid_val_catch` — **FIXED (F1)** — `lowerExprImpl` now handles `AstKind.block` in expression context. `return {}` coerced to `E!void` no longer ICEs.
- `lzw_local_var_undeclared` — **FIXED (F3)** — sema caches non-ident type annotations (`[256]u8`, `*T`, `?T`) in `resolvedTypeTable`. Lowerer emits `decl_local` — `buf` declared in C.

## Repro added 2026-07-14

- `field_access_optional` — **FIXED (ERR_3000)** — `?S.x` now produces `error[3000]: cannot access field on optional type` instead of lowerer ICE. Matches zig0 oracle (rejects `.` on optional). Green guard — no C emitted.
- `lzw_error_set_typedef` — **GREEN at HEAD** — simple error-union case passes.

## Previously FIXED (2026-07-14)

- `eu_assign_incompat_payload` — **FIXED** — `E!i64 → E!i32` now emits `error[3000]` at sema (EU payload mismatch severity check).
- `euoptptr_val_orelse` — **FIXED** — optional C typedef naming uses `getCTypeName` instead of `name_id=0`.
- `optptr_val_orelse` — **FIXED** — same c89_emit fix.
- `optptr_null_orelse` — **FIXED** — same c89_emit fix.
- `eu_assign_incompat_errorset` — **WARNING** — different error sets produce warning[3000] but same C struct compiles.
- `typeres_unhandled_node` — **FIXED (2026-07-14)** — range handler + lowerer demote.

## Previously FIXED (2026-07-13)

- `xmod_field_store_index` — EX1 fix (broad name-cache prepass)
- `array_value_copy` — EX3 fix (indexed elem type + emitter)
- `array_manyptr_type` — EX4 fix (c89_emit * sanitize)
- `func_ptr_return_type` — EX5 fix (FN_/FP_ prefix + ident_expr)

---

## Syntax Coverage Repro — 2026-07-30 (13 repros, categories A-F)

Repros discovered from broken examples (lisp_interpreter, json_parser_workaround, rogue_mud, lisp_adv). All hand-rolled tagged union patterns trigger error[3043]. Inferred error set patterns trigger error[3011]. GREEN regression guards pass where applicable.

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| A1 | `tu_field_store_ptr` | OK | ICE(3043) | union field-store through @ptrCast ptr |
| A2 | `tu_uninit_data_void` | — | FAIL | uninitialized union data for void tag |
| A3 | `tu_ptrcast_copy` | — | ICE(3043) | hand-rolled tagged union copy |
| B1 | `inferred_errorset_fnptr` | OK | ICE(3011) | @ptrCast to fn(!T) through *void |
| B2 | `inferred_errorset_xmod` | OK | ICE(3011) | cross-module bare ! error set |
| C1 | `catch_block_implicit_expr` | OK | OK(no RED) | catch block expression works |
| D | `ptroint_arena_offset` | OK | FAIL | @intToPtr/@ptrToInt arena arithmetic |
| E | `module_var_mutable` | OK | FAIL | global mutable var missing C decl |
| F | `define_mutate_closure` | ICE(2000) | ICE(2000) | fn ptr type not parseable by zig1 |

**Total: 13 new (10 unique + 3 GREEN guards), 2 new FAILs, 7 ICEs, 4 OK (all GREEN + C1 RED that unexpectedly passes)**

---

## Syntax Coverage G — 2026-07-30 (3 repros, cross-module struct literal)

Cross-module struct literal pattern discovered from json_parser_workaround. Creating a struct literal with an imported struct type causes the variable declaration to be missing from C output. Adding a field-store after the literal escalates to ICE(3043).

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| G1 | `ptrcast_slice_field_void` | OK | ICE(3043) | xmod struct + slice field + field-store |
| G2 | `ptrcast_slice_field_xmod` | OK | ICE(3043) | xmod struct + scalar fields + field-store |
| G3 | `ptrcast_slice_field_type` | OK | FAIL | xmod struct literal only (no field-store, undeclared var) |

**Note:** Category F (define_mutate_closure) removed from corpus — `fn (i32) i32` syntax not parseable by zig1. Total active repros in v14: 182. Classification: OK=167, FAIL=7, ICE=10, CRASH=0.
