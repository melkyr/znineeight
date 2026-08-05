# mi_matrix corpus — expected-fail manifest (v13 2026-07-30)

## Totals (179 repros)

- **CURRENT: OK=165 / FAIL=6 / ICE=7 / CRASH=0** (2026-07-30: syntax coverage — 13 new repros for categories A-E: hand-rolled tagged unions, bare error sets, catch blocks, ptr-to-int arena, module var, define-mutate-closure. 7 ICEs are hand-rolled tagged union field-stores (A1-A3) and inferred error set function pointers (B1-B2). All GREEN regression guards pass. 2 new FAILs from uninitialized union data (A2) and @intToPtr arena (D).)
- **2026-08-01 ADD: `comptime_neg_int`** — RUNTIME GAP, not counted in the compile-only totals above. `const N = @intCast(i32, -5);` dumps rc=0, gcc clean, but emitted C never assigns `N` (comptime-folded negative dropped) → run prints garbage not `-5`. Tracks via runtime gate; the gcc-exit classifier reports it OK. Reproduces "comptime int cannot be negative". **FIXED post-F-1..F-8 (2026-08-04): prints `-5` correctly.**
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

## FAIL (6) — [2 remain FAIL post-F-1..F-8; see F-1..F-8 section above]

### VOID decl-skip / undeclared-temp (2) — out-of-scope
- `var_declared_void` — gcc `'x' undeclared` (VOID-typed variable skipped in C decl emission). **Still FAIL post-F-1..F-8** (sema doesn't reject void vars).
- `field_store_drop` — **STILL FAIL post-F-1..F-8** — now via `error[3048]: could not resolve imported file 'pal'` (its `const pal = @import("pal")` can't be resolved — pre-existing import-resolver gap; F-5 AMENDMENT C).

### Aggregate / anon-init (2) — out-of-scope
- `anon_init_orelse_rhs` — gcc `incompatible types` (anonymous init on orelse RHS). **FIXED post-F-1..F-8 (F-6+F-8)** → OK.
- `array_tagged_union_read` — gcc `incompatible types` (tagged union indexing on array). **Still FAIL post-F-1..F-8** (union payload assigned from `unsigned int`).

### Syntax coverage new FAILs (2) — 2026-07-30
- `tu_uninit_data_void` — gcc `void tag/data declared` (hand-rolled tagged union with uninitialized data variant). **FIXED post-F-1..F-8 (F-3)** → OK.
- `module_var_mutable` — gcc `'x' undeclared` (global mutable var, C emission misses global declaration). **FIXED post-F-1..F-8 (F-7)** → OK.

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
  - **REGRESSION + F-9 FIX (2026-08-04):** post-F-1..F-8 this was FAIL — emitted `main_6D0C3706.c` had
    `(void)zT_0;` with `zT_0` undeclared (module-ident branch returned a VOID temp). **Fixed F-9** (module
    branch now returns `TEMP_NONE`) — classified **OK** again.

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

- `field_access_optional` — **FIXED (ERR_3000)** — `?S.x` now produces `error[3000]: cannot access field on optional type` instead of lowerer ICE. Matches zig0 oracle (rejects `.` on optional). Green guard — no C emitted. → reclassified **green-guard (P3-1)**; see Green-guards section.
- `lzw_error_set_typedef` — **GREEN at HEAD** — simple error-union case passes.

## Previously FIXED (2026-07-14)

- `eu_assign_incompat_payload` — **FIXED** — `E!i64 → E!i32` now emits `error[3000]` at sema (EU payload mismatch severity check). → reclassified **green-guard (P3-1)**; see Green-guards section.
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
| A1 | `tu_field_store_ptr` | OK | **OK (F-3)** | union field-store through @ptrCast ptr |
| A2 | `tu_uninit_data_void` | — | **OK (F-3)** | uninitialized union data for void tag |
| A3 | `tu_ptrcast_copy` | — | **OK (F-3)** | hand-rolled tagged union copy |
| B1 | `inferred_errorset_fnptr` | OK | **OK (F-1)** | @ptrCast to fn(!T) through *void |
| B2 | `inferred_errorset_xmod` | OK | **OK (F-1)** | cross-module bare ! error set |
| C1 | `catch_block_implicit_expr` | OK | OK(no RED) | catch block expression works |
| D | `ptroint_arena_offset` | OK | FAIL | @intToPtr/@ptrToInt arena arithmetic |
| E | `module_var_mutable` | OK | **OK (F-7)** | global mutable var missing C decl |
| F | `define_mutate_closure` | ICE(2000) | ICE(2000) | fn ptr type not parseable by zig1 |

**Total (A-F): 13 new (10 unique + 3 GREEN guards), 2 new FAILs, 7 ICEs, 4 OK (all GREEN + C1 RED that unexpectedly passes)**

---

## Syntax Coverage G — 2026-07-30 (3 repros, cross-module struct literal)

Cross-module struct literal pattern discovered from json_parser_workaround. Creating a struct literal with an imported struct type causes the variable declaration to be missing from C output. Adding a field-store after the literal escalates to ICE(3043).

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| G1 | `ptrcast_slice_field_void` | OK | **OK (F-4)** | xmod struct + slice field + field-store |
| G2 | `ptrcast_slice_field_xmod` | OK | **OK (F-4)** | xmod struct + scalar fields + field-store |
| G3 | `ptrcast_slice_field_type` | OK | **OK (F-4)** | xmod struct literal only (no field-store, undeclared var) |

**Note:** Category F (define_mutate_closure) removed from corpus — `fn (i32) i32` syntax not parseable by zig1.

---

## Syntax Coverage H — 2026-07-30 (1 repro, cross-module &extern_var + union field-store)

Full json_parser_workaround chain: `&zig_default_arena` (address-of extern var) → `arena_alloc_default` → `@ptrCast` to struct with union data → field-store to union member → ICE(3043).

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| H1 | `xmod_amp_arena_union_store` | OK | **OK (F-3)** | &extern_var + extern alloc + @ptrCast + union field-store |

## Std-Lib Phase 1 — 2026-08-03 (6 repros, std-lib migration syntax-gap candidates)

Defensive repros for the std-lib migration design spec — each probes a Z98 syntax feature with ZERO prior corpus coverage. Classified per QUICK_REF (dump + per-file gcc -c). Full evidence in each dir's `NOTES.md`.

| Pattern | Repro | Result | Note |
|---------|-------|--------|------|
| struct fn-ptr field (vtable) | `fn_ptr_struct_field` | OK | **FIXED (F-2)** — was FAIL (`'write_fn' declared void`); struct FieldEntries back-patch + void-field guard |
| pub module var (scalar) | `module_pub_var_int` | OK | **runtime gap FIXED (F-7)** — `= 42` init now emitted; prints `43` |
| pub module var (struct) | `module_pub_var_struct` | OK | **runtime gap FIXED (F-7)** — prints `7` |
| module const fn-call init | `module_const_fn_call` | OK | **runtime gap FIXED (F-7)** — `getInit()` now called; prints `42` |
| local fn-ptr (bare, no errset) | `fn_ptr_local_bare` | OK | gcc-clean, runs correctly (prints 3); sema warning[3000] non-fatal |
| cross-module `extern "c"` | `import_extern_c` | OK | 2 .c emitted, gcc-clean, runs correctly (prints hello) |

**Total active repros in v16: 192. Classification: OK=173, FAIL=8, ICE=11, CRASH=0.** *(pre-F-1..F-8 snapshot — see F-1..F-9 section for post-fix OK=184 / FAIL=8 / ICE=0)*

---

## F-1..F-9 corpus-RED fixes — 2026-08-04 (measured with /tmp/zb/zig1)

Post-fix state: **OK=184 / FAIL=8 / ICE=0 / CRASH=0** over 192 repros.

Post-P1+guard state (this file, 197 repros): **OK=188 / FAIL=9 / ICE=0 / CRASH=0** — see
"Defensive repros (Plan 1, 2026-08-04)" below. The +1 FAIL is `self_embed_optional_cycle`
(its own documented F-8 residual); the other 4 new repros classify OK.

All 6 pre-fix `error[3043]` ICEs eliminated (moved to OK):
- `tu_field_store_ptr`, `tu_ptrcast_copy`, `xmod_amp_arena_union_store`, `struct_field_store_subscript`
  (F-3), `ptrcast_slice_field_void`, `ptrcast_slice_field_xmod` (F-4).

Former FAIL/ICE repros now OK (verified per-file gcc clean):
- `inferred_errorset_fnptr`, `inferred_errorset_xmod`, `bare_error_union_return` (F-1 error[3011] fixed)
- `fn_ptr_struct_field` (F-2)
- `tu_uninit_data_void`, `tu_field_store_ptr`, `tu_ptrcast_copy`, `xmod_amp_arena_union_store`,
  `struct_field_store_subscript` (F-3)
- `ptrcast_slice_field_type`, `ptrcast_slice_field_void`, `ptrcast_slice_field_xmod` (F-4)
- `anon_init_orelse_rhs` (F-6+F-8)
- `module_var_mutable` (F-7)
- `opteu_err_if_expr`, `opteu_err_switch`, `module_as_value` (F-9)
- Runtime gaps now FIXED (run-verified): `comptime_neg_int` → `-5`, `module_pub_var_int` → `43`,
  `module_pub_var_struct` → `7`, `module_const_fn_call` → `42`.

Remaining 8 FAIL (0 ICE) — as measured with /tmp/zb/zig1 pre-P2; see the P2-3 green-guard
section below for the var_declared_void/euvoid_val_catch reclassification:
- **Emission defects (dump rc=0, gcc rejects):** `array_tagged_union_read` (**FIXED by P2-2**,
  2026-08-04), `ptroint_arena_offset` (**FIXED by P2-4**, 2026-08-05), `var_declared_void` (**now a
  green-guard, P2-3**).
  - NOTE: `module_as_value`, `opteu_err_if_expr`, `opteu_err_switch` were FAIL in the F-1..F-8
    baseline (undeclared `zT_0` temp / incompatible int→`Opt_` assign) but are now **OK — fixed F-9
    2026-08-04** (Option B optional-of-EU unwrap in the error-literal sema handler + module branch
    `TEMP_NONE`). Verified per-file gcc clean; see "Former FAIL/ICE repros now OK" above.
- **Frontend gaps (5, 0 `.c` emitted; 2 now green-guards P3-1):** `catch_block_value_producing`
  (error[2000]), `eu_assign_incompat_payload` (error[3000] — **now a green-guard, P3-1**),
  `field_access_optional` (error[3000] — **now a green-guard, P3-1**), `field_store_drop`
  (error[3048], pal-import — see QUICK_REF known-issues), `test_stub_0`
  (error[3048], imports nonexistent `"std"`).

---

## Defensive repros (Plan 1, 2026-08-04) — +4 repros (192 → 196)

Four defensive repros guarding deferred items from the F-1..F-9 review (cross-module global
field-access, F-8 optional self-embed residual, F-7 array `load_global` copy-loop, anonymous
error-set comparison). Classified with `/tmp/zb/zig1` per the QUICK_REF corpus classifier
(dump rc + emitted `.c` count + per-file `gcc -c`; runtime verified for the runnable ones).

| Repro | RED | GREEN | Classification (measured) | Guards |
|-------|-----|-------|---------------------------|--------|
| `xmod_global_field_access` | runtime gap | OK (prints 2) | **FIXED (P1-2)** — dump rc=0, gcc-clean, prints `2` (two bumps → counter=2) | F-7 review I-1: cross-module global field-access — FIXED by Plan 1 Task P1-2 (lower.zig SymbolKind.global branch + header extern decls) |
| `self_embed_optional_cycle` | FAIL | — | **FAIL** — dump rc=0, 1 `.c`, gcc `unknown type name 'zT_DD0C1E27_X'` (incomplete-type) | F-8 residual: `struct X { next: ?X }` → infinite-size C type; guards, not fixes |
| `load_global_array_copy` | OK | — | **OK** — dump rc=0, 1 `.c`, gcc clean, runs: prints `3` and `15` (concatenated `315`, print_int adds no newline) | F-7 array `load_global` copy-loop correctness (dead copy-temps, correct but wasteful) |
| `anon_errset_comparison` | OK (prints 1) | OK (prints 1) | **OK (semantically verified, P3-3)** — dump rc=0, 1 `.c`, gcc clean, RED prints `1`, GREEN prints `1`; RED==GREEN==1 on zig1 AND zig0 oracle (matches oracle) | bare-`!` error-set member comparison (`err == error.Bad`) — **semantically correct (P3-3)**: anon error literal carries the raw name_id (unique-per-name, program-stable interner code), so same name ⟹ same code, distinct names never collide |

**Updated totals: OK=187 / FAIL=9 / ICE=0 / CRASH=0 over 196 repros.** The +1 FAIL is exactly
`self_embed_optional_cycle`'s own documented status (F-8 residual). The other 3 new repros
classify OK, so the FAIL increase does not exceed the new repros' own documented status; no
regressions in the existing 192.

**Notes:**
- `xmod_global_field_access` was a RUNTIME GAP (counted OK in the compile-only gate) and is now **FIXED by Plan 1 Task P1-2** — prints `2` (was 1).
- `self_embed_optional_cycle` FAIL is the documented F-8 residual. Naive C emission would produce
  `struct X { struct X next; int has_value; }`; today the struct typedef is dropped entirely
  (`unknown type name`), so the residual is guarded, not fixed.
- `anon_errset_comparison`: RED and GREEN both print `1` — the bare-`!` set comparison is
  **semantically correct (P3-3, Option A)**. name_id is a unique-per-name, program-stable
  interner code; same name ⟹ same code, distinct names can never collide within one program.
  Verified RED==GREEN==1 on zig1 and the zig0 oracle. Investigation resolved — see the P3-3
  section below.

---

## Task P1-4 guard repro — 2026-08-04 (+1 repro, 196 → 197)

Guards the analyzer `analyzeExpr` builtin_call crash that crashed `examples/z98/lzw` at HEAD
(regression `532420cb`, last-good `7bc6e4d1`). Single-file repro of `main.zig:17`:
`@intCast` inside an `if` condition. `builtin_call.child_0` is the builtin's **name_id**, not a
node index (parser.zig:611); `analyzeExpr`'s generic child fallback recursed into it and formed a
cycle when the name_id collided with the enclosing `if_stmt`'s node index → infinite recursion →
stack overflow. Full analysis: `.superpowers/sdd/I-lzw-regression-report.md`.

| Repro | RED | Classification (measured) | Guards |
|-------|-----|---------------------------|--------|
| `lzw_builtin_call_crash` | CRASH pre-fix | **CRASH pre-fix** (dump rc=139 SIGSEGV, 0 `.c`; bypassed by `--no-null-check --no-lifetime-check --no-leak-check`); **OK post-fix** (dump rc=0, gcc-clean, links, runs → prints `invalid` on stdin EOF) | P1-4 analyzer `builtin_call` arg-walk fix (analyzer.zig:495-502) |

**Updated totals post-fix: OK=188 / FAIL=9 / ICE=0 / CRASH=0 over 197 repros.** The +1 total is
the new repro, which counts OK post-fix. FAIL count unchanged (9) vs the P1-3 baseline; no existing
repro flipped OK→FAIL; the lzw example itself now dumps, compiles, links, and runs.

---

## Green-guards (correct rejection, not a defect) — P2-3 (2026-08-04)

Reclassified per operator ruling (AMENDMENT P2-3). A green-guard is a valid-Z98 program that is
CORRECTLY rejected by the frontend with a diagnostic — it guards the rejection, it is not a compiler
gap. Green-guards are counted SEPARATELY from FAIL; a green-guard moving to OK/FAIL is a regression.
Classifier rule: dump emits 0 `.c` with the documented `error[NNNN]` diagnostic.

| Repro | Classification | Correct rejection (measured; P2 rows /tmp/p2v/zig1, P3-1 rows /tmp/p3/zig1) |
|-------|----------------|--------------------------------------------------|
| `var_declared_void` | **green-guard (was emission-defect FAIL)** | dump rc=2, `error[3000]: cannot declare variable of type void`, 0 `.c` emitted. `var x = noop();` (void init) — sema now rejects VOID-typed var decls (semantic_analyzer.zig:1674-1677) |
| `euvoid_val_catch` | **green-guard (was OK)** | dump rc=2, `error[3000]: cannot declare variable of type void`, 0 `.c` emitted. `var r = h() catch {};` (void-typed init) — latent void-var acceptance bug; Zig forbids void variables |
| `eu_assign_incompat_payload` | **green-guard (was frontend-gap FAIL)** | dump rc=2, `error[3000]: type mismatch in assignment — internal type representations differ`, 0 `.c` emitted. `E!i64 → E!i32` payload mismatch at sema; zig0 oracle rejects identically (`error: type mismatch`) |
| `field_access_optional` | **green-guard (was frontend-gap FAIL)** | dump rc=2, `error[3000]: cannot access field on optional type; use .? to unwrap first`, 0 `.c` emitted. `.` on `?S`; zig0 oracle rejects identically (`error: type mismatch`) |

Post-P2-3 accounting: **OK=188 / FAIL=7 / green-guards=2 / ICE=0 / CRASH=0 over 197 repros.**
(var_declared_void: FAIL→green-guard; euvoid_val_catch: OK→green-guard; FAIL 9→7 counting
green-guards separately; array_tagged_union_read moved FAIL→OK in P2-2.) No other repro flipped.

**Post-P3-1 accounting (2026-08-05): OK=189 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197
repros** (189 + 4 + 4 = 197). `eu_assign_incompat_payload` and `field_access_optional` reclassified
FAIL→green-guard (verified correct rejections matching the zig0 oracle — see table). No other repro
flipped.

**Updated totals (raw classifier, 197 repros): OK=189 / FAIL=8 / ICE=0 / CRASH=0.** Of the 8
classifier-FAILs, 4 are green-guards (this section): `eu_assign_incompat_payload`,
`field_access_optional`, `var_declared_void`, `euvoid_val_catch` (green-guards are a sub-bucket of
the raw 8, counted separately from FAIL).

---

## P2-4 — ptroint_arena_offset FIXED (2026-08-05)

`ptroint_arena_offset` moves emission-defect **FAIL → OK** via **Option A + SCOPED Option B**:

- **Option A (root cause, semantic_analyzer.zig:495,498):** `semanticAnalyzerResolveArithmetic`
  now treats `TYPE_INT_LIT` as a valid pointer-arithmetic offset (`&buf + 64` → pointer type
  instead of TYPE_VOID), covering `ptr ± lit` and `lit + ptr`.
- **SCOPED Option B (emission hardening, c89_emit.zig:2729,2732):** the `written_type` override in
  `emitHoistedDecls` now applies only when the hoisted temp's `type_id ∈ {TYPE_VOID, TYPE_UNDEFINED}`
  AND the derived `written_type` is valid (`!= 0xFFFFFFFF`) and `!= TYPE_VOID`. Zero-blast-radius
  (verified in `.superpowers/sdd/P2-optB-report.md`); the unscoped variant regressed the corpus.
- **Gates:** self-host build 0 gcc errors; repro dump rc=0, gcc-clean, links, runs rc=0
  (`zT_8` declared as `Arr_unsigned_char_6*`); full corpus **OK=189 / FAIL=8 / ICE=0 / CRASH=0**
  (raw classifier; FAIL −1 exactly, `ptroint_arena_offset` removed, no other flips); 4 MD5 gates
  byte-identical (mud `4644ad13…`, gol `d0d3051d…`, lisp `f84c8748…`, json `3492a935…`).

**Post-P2-4 accounting: OK=189 / FAIL=6 / green-guards=2 / ICE=0 / CRASH=0 over 197 repros**
(189 + 6 + 2 = 197). FAIL 9→8 raw; the 2 green-guards (`var_declared_void`, `euvoid_val_catch`)
count separately. Remaining 6 FAIL: 5 frontend gaps (`catch_block_value_producing`,
`eu_assign_incompat_payload`, `field_access_optional`, `field_store_drop`, `test_stub_0`) and
1 gcc-visible emission defect `self_embed_optional_cycle` (F-8 residual) — all documented above.

---

## P3-1 — reclassify 2 correct rejections as green-guards (2026-08-05)

`eu_assign_incompat_payload` and `field_access_optional` are **CORRECT rejections** matching the
zig0 oracle — green-guards, not defects (both documented as FIXED above; now formally reclassified
out of the FAIL count into the "Green-guards" section). Verified with /tmp/p3/zig1:

| Repro | zig1 (dump rc, error) | 0 `.c` | zig0 oracle |
|-------|------------------------|--------|-------------|
| `eu_assign_incompat_payload` | rc=2, `error[3000]: type mismatch in assignment — internal type representations differ` | yes | rejects: `error: type mismatch` (rc=1) |
| `field_access_optional` | rc=2, `error[3000]: cannot access field on optional type; use .? to unwrap first` | yes | rejects: `error: type mismatch` (rc=1) |

**Post-P3-1 accounting: OK=189 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros**
(189 + 4 + 4 = 197). Raw classifier FAIL stays **8** (green-guards are a sub-bucket of the raw 8).
The 4 green-guards: `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`,
`euvoid_val_catch`. The 4 real FAILs: 2 import-gap (`field_store_drop`, `test_stub_0`, both
`error[3048]`) + `catch_block_value_producing` (`error[2000]`) + `self_embed_optional_cycle`
(F-8 residual, gcc incomplete-type). No other repro flipped.

---

## P3-2 — defer 2 import-gap repros to the std-lib milestone (2026-08-05)

`field_store_drop` and `test_stub_0` remain classified **FAIL** but are now tracked as
**std-lib-deferred** — NOT compiler defects. Both fail via `error[3048]` because user programs
cannot import compiler-internal modules; no std lib exists yet. **Will pass when zig1 gains a real
std lib.** (Both already documented in QUICK_REF.md "3 frontend-gap repros" / known-issues.)

| Repro | Class | Cause | Will pass |
|-------|-------|-------|-----------|
| `field_store_drop` | FAIL (std-lib-deferred) | `const pal = @import("pal")` → `error[3048]: could not resolve imported file 'pal'` — pre-existing import-resolver gap; a user program cannot import compiler-internal modules | when zig1 gains a real std lib |
| `test_stub_0` | FAIL (std-lib-deferred) | imports nonexistent `"std"` → `error[3048]` | when zig1 gains a real std lib |

**Deferral changes no counts.** Accounting stays **OK=189 / FAIL=4 / green-guards=4 / ICE=0 /
CRASH=0 over 197 repros** (189 + 4 + 4 = 197; raw classifier FAIL stays **8**). The 4 real FAILs:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`catch_block_value_producing` (`error[2000]`) + `self_embed_optional_cycle` (F-8 residual, gcc
incomplete-type). No other repro flipped.

---

## P3-3 — anon_errset_comparison OK (semantically verified) + adjacent defects (2026-08-05)

Per the P3-3 operator ruling (**Option A**, docs-only closeout): the bare-`!`
`err == error.Bad` comparison is **semantically correct**. An anonymous error literal stores the
raw **name_id** as its C error code (`lower.zig:1191-1206`, `semantic_analyzer.zig:1182`), and
name_id is a **unique-per-name, program-stable interner code** — `string_interner.zig:88-122`
dedups by exact content (`mem_eql` at `:101`), one interner per program (`main.zig:146`), so same
name always yields the same name_id and distinct names can never collide within one program.
Measured **RED==GREEN==1** on zig1 AND the zig0 oracle (matches oracle); all pure-anonymous probes
(`==`/`!=`, cross-fn, distinct-name) match the oracle (`.superpowers/sdd/P3-anonerr-report.md`).

`anon_errset_comparison` upgraded from `**OK**` to **OK (semantically verified)** — it was already
OK since Plan 1 P1-1; this records the semantic justification. **Counts unchanged: OK=189 /
FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros** (189+4+4=197; raw classifier FAIL
stays 8). No other repro flipped.

**2 adjacent defects found by P3-3 — tracked as follow-ups, NOT fixed (out of scope):**

1. **Switch-on-error exhaustiveness → P3-5.** Switch-case collection in `lower.zig:2919-2934`
   handles only `int_literal`/`enum_literal` case nodes; an `error_literal` case falls to
   `continue` → zero SwitchCase entries → `switch (err) { default: ... }` always takes `default`.
   Affects named AND anonymous error sets; the oracle emits proper `case ERROR_Bad:`. No corpus
   repro or MD5 gate exercises it today. Clean upstream fix (mirror the enum_literal branch).
2. **Error-code representation unification → I3-5 / P3-6.** zig1 accepts inferred→named error-set
   coercions that real Zig also accepts (subset→superset is legal; zig0/z98 is stricter), but then
   MISCOMPARES: anonymous-set errors carry the raw name_id, named-set errors carry the ordinal.
   Only reachable through programs the zig0 oracle rejects, so it is not a corpus classification
   issue. Investigate (I3-5), then implement per ruling (P3-6).

---

## P3-4 + P3-7 — catch_block_value_producing FAIL → OK (2026-08-05)

`catch_block_value_producing` is now **OK** — the last of the 5 frontend-gap repros. Two tasks
flipped it:

- **P3-4 (commit a50e2910, value-producing blocks):** the catch block's trailing bare `99` (no `;`)
  no longer errors `error[2000]: expected ';' but found '}'` — the trailing `;` is now optional
  before `}` in `parserParseExprStmt` (parser.zig:1256-1260) — and `lowerExprOrBlock`
  (lower.zig:3223-3238) now returns the last child's temp, so the catch fallback materializes the
  real `99` instead of an uninitialized local (was garbage `-366458289`).
- **P3-7 (this commit, inline error-set types in type positions):** `helper.zig:1`
  `pub fn try_compute() error{Bad}!i32` — an INLINE error-set declaration in a type position — is
  now fully supported:
  - **Parser (parser.zig:902-930):** the `kw_error` branch of `parserParseType` now checks for a
    trailing postfix `!` after `parserParseErrorSetDecl` and, when present, parses the payload type
    and builds an `error_union_type` node (mirroring the base+`!` path at :914-921). Before: the
    `!` fell out of the type parser → `error[2000]: expected '{' but found token`.
  - **Type-resolver (type_resolver.zig:738-755):** `resolveTypeExprFull` now has an
    `error_set_decl` case — it appends the member name_ids to the registry `xn_items` table and
    registers an anonymous `error_set_type` via `typeRegistryGetOrCreateErrorSet` (content-deduped
    through the registry `es_cache`, mirroring `symbol_registrator.zig:195-210`/`:357-372` named-set
    population). Before: `error{Bad}` (no `!`) fell through to `TYPE_UNDEFINED` (:901-903) and the
    fn return type resolved void → ICE `error[3043]: internal: invalid temp index 0`.
  - **C89 emission (c89_emit.zig):** the anonymous (`name_id==0`) `error_set_type` is now included
    in the synthetic-type emission whitelists (`computeSharedSet`, `emitSharedHeader` sub-passes
    2a/2b, `emitSpecialTypes` sub-passes 2a/2b), so its `typedef int <cname>;` + per-member
    `#define <cname>_<member> <ordinal>` macros are emitted. Before: the whitelist excluded
    `error_set_type`, so the error-code temp's type name was undefined → gcc error.

**Measured (this build):** dump rc=0, 2 `.c` emitted (main + helper), gcc-clean, links, runs
printing **`99`** rc=0. `error{Bad}!i32` parses; bare `error{Bad}` (no `!`) no longer ICEs (dumps
clean, gcc-clean, prints `0`). 4 MD5 gates byte-identical (mud `4644ad13…`, gol `d0d3051d…`,
lisp `f84c8748…`, json `3492a935…`).

**Post-P3-7 accounting: OK=190 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros**
(190 + 3 + 4 = 197). Raw classifier FAIL **8 → 7** (green-guards remain a sub-bucket of the raw
count). `catch_block_value_producing` moved FAIL→OK. The remaining 3 real FAILs:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
No other repro flipped.

---

## P3-5 — switch-on-error exhaustiveness FIXED (2026-08-05) — +2 repros (197 → 199)

`switch (err)` over a caught error value (named OR anonymous error set) now emits real
`case <value>:` entries instead of an empty `switch (err) { default: ... }`.

- **Root cause (P3-3 investigation finding #3):** switch-case collection in `lower.zig:2919-2934`
  (and its statement-site twin `lower.zig:3644-3658`) handled only `int_literal` and `enum_literal`
  case nodes; an `error_literal` case node fell to `continue` → zero SwitchCase entries → the
  emitted C `switch (err) { default: ... }` always took `default`.
- **Fix (lower.zig):** added an `error_literal` branch to both switch-case collection sites,
  mirroring the `enum_literal` branch — value resolves via `enum_value_table` (ordinal) when an
  entry is present, else falls back to the raw `node.payload` name_id (anonymous-set case,
  matching the error_literal lowering at `lower.zig:1191-1206`).
- **Companion fix (semantic_analyzer.zig, `semanticAnalyzerResolveSwitchExpr`):** when the switch
  cond type is an `error_set_type` (or `error_union_type`), resolve `error_literal` case nodes
  against the cond error set (pushExpectedType + resolveExpr) so `enum_value_table` gets the
  ordinal — mirroring how `enum_literal` case nodes are resolved for tagged-union switches. Without
  this, a NAMED-set case value would fall back to the raw name_id and never match the produced
  ordinal-coded error.

| Repro | RED (pre-fix) | GREEN (post-fix) | Notes |
|-------|---------------|------------------|-------|
| `switch_on_error_named` | prints `0` (default taken; emitted `switch (err) { default: }`, 0 case entries) | prints `1` (emitted `case 0:`/`case 1:`) | `const E = error{ Bad, Other }`; `E!i32` returns `error.Bad`; catch switch |
| `switch_on_error_anon` | prints `0` (default taken) | prints `1` (emitted `case 23:`/`case 28:` = raw name_ids) | bare `!i32` returns `error.Bad`; catch switch |

Both classify **OK** per the QUICK_REF gate (dump rc=0, 1 `.c`, gcc-clean) in BOTH states — the
defect is runtime-wrong, not a compile failure — so these are new OK repros with a runtime-gap-now-
fixed annotation, NOT FAIL→OK moves. The zig0 oracle emits `case ERROR_Bad:` / `case ERROR_Other:`
and prints `1`; zig1 now matches that runtime behavior.

**Post-P3-5 accounting: OK=192 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 199 repros**
(192 + 3 + 4 = 199; corpus total grows 197 → 199 by 2 new OK repros). Raw classifier FAIL stays
**7** (green-guards remain a sub-bucket of the raw count). The 3 real FAILs unchanged:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
4 MD5 gates byte-identical (mud `4644ad13…`, gol `d0d3051d…`, lisp `f84c8748…`, json
`3492a935…`). No other repro flipped.

---

## P3-6 — error-code representation unification: per-name registry + `ERROR_<name>` prologue (2026-08-05) — +1 repro (199 → 200)

Operator ruling 2026-08-05: **Option B (zig0-style)**, per `.superpowers/sdd/I3-5-errorcodes-report.md`.
All error codes are now dense per-program **per-name** registry codes (name_id → small int,
1-based, first-use order) instead of per-set ordinals / raw name_id. Fixes the cross-set `e1 == e2`
miscompare for real-Zig-legal subset→superset coercions (both I3-5 probes now print `1`).

- **Registry:** `error_code_registry: U32ToU32Map` (name_id → code) on `CompilerContext`
  (main.zig, next to `enum_value_table`); `hash_mod.u32ToU32MapGetOrAddDense` (look up; miss ⇒
  `count+1`, store). Sema/lower/emitter all route through it.
- **Producers repointed** (ordinal / raw name_id → registry code):
  - sema `semanticAnalyzerResolveExpr` error_literal-under-expected-set (membership check kept).
  - sema `var x = error.Bad` set-scan inference (kept).
  - sema switch-case companion (P3-5) stores the registry code via the error_literal path.
  - lower `error_literal` fallback → `getOrAdd(name_id)` (bare-`!` anon path; same code as named).
  - lower `E.Bad` field-access (type-site + value-site) → `enum_const` with registry code.
  - lower switch-case error_literal fallbacks → `getOrAdd(name_id)`.
  - c89_emit `emitErrorSetType` member `#define`s revalued to registry codes.
- **Prologue macros:** program-global `#define ERROR_<name> <code>` emitted once into
  `zig_special_types.h` (multi-module shared header — every module .h includes it) and inline in
  the single-stream path; skipped when the registry is empty (keeps mud/gol byte-identical).
  Assignment order = sema/lower traversal order (deterministic), finalized by registering all
  error-set members in type order before emission.

| Repro | RED (pre-P3-6) | GREEN (post-P3-6) | Notes |
|-------|----------------|-------------------|-------|
| `errset_cross_set_compare` (NEW) | prints `00` | prints `11` | anon→named + named→named subset→superset `err == error.Bad`; classifies **OK** |

**Post-P3-6 accounting: OK=193 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 200 repros**
(193 + 3 + 4 = 200; corpus total grows 199 → 200 by 1 new OK repro). Raw classifier FAIL stays
**7**; the 3 real FAILs and 4 green-guards unchanged. 4 MD5 gates: **mud + gol byte-identical**
(mud `4644ad13…`, gol `d0d3051d…`); **lisp + json RE-BASELINED** per F-5 AMENDMENT B precedent
("runtime behavior is the gate, not byte-identity"): lisp `dd56cd23…`, json `900cb401…` — both
compile, link, and run correctly (lisp `(+ 1 2)` → `3`, `(foo-bar-baz)` → `Eval error:
UnboundSymbol`; json parses `test.json` identically). No other repro flipped. `@enumToInt(err)`
values change to registry codes (accepted; re-verified at runtime — `error_literal_return` still
prints `1`, all ~30 error repros unchanged).
