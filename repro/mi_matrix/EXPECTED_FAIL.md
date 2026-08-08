# mi_matrix corpus — expected-fail manifest (v27 2026-08-07)

## Totals (230 repros)

- **CURRENT (2026-08-07 F4 gate sweep — char_literal switch + opt_slice null fixes CLOSEOUT): OK=223 /
  FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** over **230 repros** (223 + 3 + 4 = 230; raw
  classifier FAIL = 7 — the 4 green-guards are a sub-bucket of the raw count). Measured with
  `sf/build/out_release/zig1` at HEAD (compiler source = F1 `e0a4d6d6` char_literal switch +
  F2 `5c515a7d` opt_slice null, commits 7dc119a6..7a732cb3; battery commits are repro-only).
  Corpus = 231 dirs (230 manifest repros + `opt_slice_null_return`, OK-by-gate/type-incorrect,
  tracked separately). The 15 battery repros ALL classify **OK** under the gcc-exit gate and are
  now **fully OK** — the F1/F2 fixes landed: the **12 Battery A char_literal switch-case repros
  no longer runtime-gap-tracked** (F1 emits real `case 'a':` labels at lower.zig:3202 expr /
  :3941 stmt; all 12 now print their expected post-fix output — `120`, `1120`, `19`, `1`, `109`,
  etc., verified by run), and the **3 Battery B opt_slice null-payload repros are no longer
  latent** (F2 Option B drops the dead `int zT_N; zT_N = NULL;` payload temp — 0 `-Wint-conversion`
  warnings, 0 `= NULL;` sites, still print `1`, verified by run). The 3 FAILs unchanged: 2
  std-lib-deferred (`field_store_drop` + `test_stub_0`, both `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
  `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
  No other repro flipped. Note: `opt_slice_null_return` remains OK-by-gate (type-incorrect,
  tracked separately, see the F5 section). 4 MD5 gates: gol byte-identical; mud/lisp/json
  RE-BASELINED by F2 (mud `6c0a83f1…`, gol `0d8f0092…`, lisp `fad41183…`, json
  `c403f079…` — full hashes in QUICK_REF). [F2 2026-08-08: `extern_runtime_symbol_xmod` added
  as a 232nd dir — OK-by-gate/latent, std-lib-deferred, tracked separately like
  `opt_slice_null_return`; manifest count and all totals UNCHANGED. See the F2 section below.]
  [F4 2026-08-08: `plat_stubs_missing_xmod` documented as OK-by-gate/latent,
  std-lib-deferred (the D4 platform-stub gap — 5 console/platform-detect stubs,
  `plat_is_windows` + `plat_console_*`, all rogue_mud-only); tracked separately
  like `opt_slice_null_return` / `extern_runtime_symbol_xmod`; manifest count
  and all totals UNCHANGED. See the F4 section below.]
- Prior: OK=208 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 215 (2026-08-07 F5 gate sweep — rogue_mud emission-defects plan closeout; Verified with `/tmp/zf5/zig1` — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors). `switch_mixed_case_argtype`
  **FAIL→OK** (added 2026-08-07 by the rogue_mud I-task): the sema mid-switch abort in
  `resolveSwitchExpr` — the MIX else-branch at semantic_analyzer.zig:1167 `return
  type_mod.TYPE_VOID;` aborted the whole switch when two prong bodies had non-coercible types
  (assignment→i32 vs empty-block→void), skipping all later prongs — so the call prong was never
  sema'd and `call_arg_types` was never populated, making the lowerer fallback type arg slots as
  raw lowered types (`unsigned int` for `&arena`, `char*` for the string literal). Now the
  MIX else-branch `continue`s (keeps resolving remaining prongs) while keeping the
  `resolvedTypeTableSet(..., TYPE_VOID)` (Option A, operator ruling; I4-validated). dump rc=0,
  gcc-clean, link rc=0, run rc=0; emitted arg temps correctly typed `Sand*` / `Slice_u8`. The 3
  remaining FAILs: 2 std-lib-deferred (`field_store_drop` + `test_stub_0`, both
  `error[3048]`) + `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4
  green-guards unchanged: `eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`. No other repro flipped. Note: `opt_slice_null_return`
  is OK-by-gate (type-incorrect, tracked separately). Known adjacent bug (out of scope, tracked
  as follow-up): char-literal switch `case` labels dropped at lower.zig:3858-3860/:3121-3123 (refs superseded — actual sites lower.zig:3183 expr / :3920 stmt), so
  this repro's switch still takes `default` at runtime (see the F4 section below).
- Prior: OK=207 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 214 (2026-08-07 F3: cross-module pub const resolves)
- Prior: OK=206 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 213 (2026-08-07 F2: undefined struct-array field init emits valid C)
- Prior: OK=205 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 212 (2026-08-07 F1: duplicate-typed struct fields emit correctly)
- Prior: OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 210 (2026-08-07 F1: labeled statement support in parser, sema, lowerer)
- Prior: OK=202 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 210 (2026-08-07 I-task: rogue_mud build attempt — labeled_stmt_unhandled added as FAIL)
- Prior: OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 209 (2026-08-06 Task F7 gate sweep, 4-item plan closeout)
- Prior: OK=200 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 208 (2026-08-06 F2 u64-safe int_literal marker)
- Prior: OK=199 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 207 (2026-08-06 F1 @intCast range-check)
- Prior: OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 206 (2026-08-06 F9 gate sweep)
- Prior: OK=197 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 205 (2026-08-06 F7: comptime_u64_fold_overflow)
- Prior: OK=196 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 204 (2026-08-06 P0 fix wave 1)
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

---

## Task P0 — 3 defensive repros for comptime arithmetic folding gaps (2026-08-06) — +3 repros (200 → 203)

Three defensive repros proving the three comptime-arithmetic-folding pipeline gaps
(plan `.superpowers/plans/2026-08-06-comptime-arithmetic-folding-plan.md`, AMENDMENT P0-A/P0-B):
Gap 1 = `phase_ComptimeEvaluation` (main.zig:339-352) visits only `builtin_call` nodes; Gap 2 =
lowerer binary/unary handlers (`lower.zig:1218-1306`, `:1426-1439`) emit `BIN_*`/`UN_*` LIR
unconditionally while `builtin_call` (`:2456`) checks `comptime_values`; Gap 3 = type_resolver
array-size handler (type_resolver.zig:869-911) misses `mul`/`div`/`mod_op`. Classified with
`/tmp/z1/zig1` per the QUICK_REF corpus classifier.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_binop_not_folded` | emission gap | **OK (gap RESOLVED by F1+F2+F4)** — dump rc=0, 1 `.c`, gcc-clean, links, runs printing `40 20 300 3 0 -30 10 30 20 120 7 -31`; `__module_init`-scoped `grep -c '[\*\/\%]'` = **0** (all 12 consts emit `int_const`: 40/20/300/3/0/-30/10/30/20/120/7/-31 — see NOTES.md) | Gap 1: bare binary/unary nodes never reached `comptimeEvalEvaluate` — FIXED by F1 (bitwise/shift comptime ops) + F2 (var_decl binop/unary inits folded in phase_ComptimeEvaluation) + F4 (lowerer guard consumes the fold) |
| `comptime_lower_ignores_fold` | emission gap | **OK (gap RESOLVED by F4+F5)** — identical measured state to repro 1 (same source; isolates Gap 2); `__module_init`-scoped `grep -c '[\*\/\%]'` = **0** | Gap 2: lowerer binary/unary handlers never consulted `comptime_values` — FIXED by F4 (comptime_values guards on 10 binary op handlers, INT_LIT→I32 remap) + F5 (negate/bit_not guards) |
| `comptime_array_size_gap` | semantic gap | **OK (runtime gap RESOLVED by F6)** — dump rc=0, 1 `.c`; the arrays now resolve `u8[4000]`/`u8[40]`/`u8[2]` (emitted `typedef unsigned char …[4000];`/`[40];`/`[2];`), gcc-clean (rc=0) — no longer a silent type-drop (pre-fix the consts degraded to uninitialized `int` globals; counted OK+runtime-gap per ruling P0-E) | Gap 3: type_resolver array-size handler missed `mul`/`div`/`mod_op` → `arr_len`=0 → `TYPE_UNDEFINED` — FIXED by F6 (mul/div/mod arms, type_resolver.zig:888-896) |

**Post-P0 accounting: OK=195 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 203 repros**
(195 + 4 + 4 = 203; corpus total grows 200 → 203 by 3 new repros). OK 193→195 (+2 = repros 1+2,
emission-gap annotations); FAIL 3→4 (+1 = `comptime_array_size_gap`). Raw classifier FAIL **7 → 8**
(green-guards remain a sub-bucket of the raw count). **UPDATED by "Fix wave 1" (operator rulings
P0-D/P0-E) below: `comptime_array_size_gap` reclassified OK+runtime-gap (FAIL 4→3) and
`fn_varargs_unsupported` added as FAIL (3→4) → final OK=196 / FAIL=4 / green-guards=4 @204 (raw
FAIL=8).** No other repro flipped.

**Source-note (deviation from the plan's verbatim draft source, see
`.superpowers/sdd/task-P0-report.md`):** the plan's draft main.zig for repros 1+2 does not compile
on the current compiler — (1) the parser requires `;` after `@cInclude(...)`; (2) varargs `...`
in `extern fn` params is not parseable (`error[2000]`); (3) `const A`/`const B` referenced ONLY
from other const initializers never receive C storage-global decls (`zG_..._A` undeclared in
`__module_init` → gcc error). Corrections applied: `;` after `@cInclude`, fixed-arity `printf`,
literal operands inlined. The tested gap is unchanged (12 bare binary/unary module-scope const
ops that must fold to `int_const`).

**Discrepancy note (repro 3, evidence over prediction — RESOLVED by ruling P0-E):** the
brief/ruling predicted `error: ISO C forbids zero-size array` for `comptime_array_size_gap`; the
measured pre-fix state is instead a **silent semantic miscompile** (arrays dropped, consts →
uninitialized `int` globals, gcc-clean). It was initially counted **FAIL** per AMENDMENT P0-B
(real gap, `int`-drop is wrong output), NOT because gcc rejects it — flagged for operator
re-adjudication under the classifier convention (gcc rc==0 ⇒ OK, per the
`comptime_neg_int`/`load_global_array_copy` runtime-gap precedent). **Operator ruling P0-E
(2026-08-06): classify it OK with runtime-gap annotation.** See "Fix wave 1" below.

---

## Fix wave 1 — operator rulings P0-D/P0-E (2026-08-06) — +1 repro (203 → 204)

- **P0-E (reclassify):** `comptime_array_size_gap` **FAIL → OK with runtime-gap annotation**. Under
  the QUICK_REF gcc-exit classifier the emission is gcc-clean (rc=0), so it is **OK**, not FAIL.
  The gap is a **silent semantic miscompile**: array types resolve `TYPE_UNDEFINED`
  (type_resolver.zig:869-911 misses `mul`/`div`/`mod_op` → `arr_len`=0), so
  `CELLS`/`HALF`/`REM` degrade to uninitialized `int` globals (no `u8[N]`, no `[0]`, gcc-clean).
  Counted OK following the `comptime_neg_int`/`load_global_array_copy` runtime-gap precedent; the
  miscompile is tracked as a runtime gap until F3 fixes it (re-verified 2026-08-06: dump rc=0, 1
  `.c`, gcc rc=0, emitted `int zG_..._CELLS;` / `int zG_..._HALF;` / `int zG_..._REM;`).
- **P0-D (new tracking repro):** the plan's original `extern fn printf(fmt: [*]const u8, ...) i32;`
  does not compile — parser.zig has NO varargs (`...`) support → `error[2000]: expected identifier
  but found token`. Recorded as a standalone tracking repro:

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `fn_varargs_unsupported` | parse gap | **FAIL** — dump rc=2, `error[2000]: expected identifier but found token` at the `...`, 0 `.c` emitted (frontend parse gap) | parser.zig has no varargs support; out of comptime-arithmetic scope — tracked as a known gap |

**Post-P0-fix-wave-1 accounting: OK=196 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 204
repros** (196 + 4 + 4 = 204; corpus total grows 200 → 204 by 3 comptime-arithmetic repros + 1
varargs tracking repro). OK 193→196 (repros 1+2 with emission-gap annotations + repro 3
reclassified OK+runtime-gap per P0-E); FAIL 3→4 (+1 = `fn_varargs_unsupported`, P0-D). Raw
classifier FAIL stays **8** (green-guards remain a sub-bucket of the raw count). The 4 real FAILs:
2 std-lib-deferred (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type) + `fn_varargs_unsupported`
(parser varargs gap, `error[2000]`). The 4 green-guards unchanged: `eu_assign_incompat_payload`,
`field_access_optional`, `var_declared_void`, `euvoid_val_catch`. No other repro flipped.

## Task F7 — `comptime_u64_fold_overflow` (u64 const fold >2^32 masking) (2026-08-06) — +1 repro (204 → 205)

Operator ruling I1-A (serious bug): a u64-annotated const whose folded value exceeds 2^32
(`const X: u64 = 3000000000 * 2;` = 6000000000) gets typed I32 by the F4/F5 guard (bare binop
resolves TYPE_INT_LIT → remapped I32) and the `int_const` emitter masks the value to 32 bits →
wrong value (1705032704 / 0). Reproduced + FIXED in `main.zig` (commit `fix(F7): …`):

- **Root cause (2 defects, both in `main.zig` phase_SemanticAnalysis):**
  1. The declared type is stored on the var_decl node (`resolved_types[var_decl]`, set at
     main.zig:397), but is then **clobbered** to the init type (INT_LIT) by the unconditional
     `resolvedTypeTableSet(decls[di], init_type)` at main.zig:428-430 → the storage global
     (main.zig:639 reads `resolved_types[var_decl]`) is emitted `int` → truncates at the store.
  2. The F4/F5 fold guard types the temp from `resolved_types[binop]` (INT_LIT → I32); the
     declared u64 type is never threaded onto the init node for module-scope decls (fn-scope
     var_decls already get this at sema:1705-1708).
- **Fix (Option B, "B-lite"):** (a) gate the `resolved_types[var_decl] = init_type` write on
  `existing == null` so a known declared type is never clobbered (storage globals now type
  correctly); (b) mirror the fn-scope behavior — after resolving the module-scope init, set
  `resolved_types[child_1] = declared type` when the decl is annotated. The F4/F5 guard then
  reads the declared type (u64) with **no lower.zig change**. Verified: `1:1705032704
  3000000000 1:0` (was `0:1705032704 3000000000 0:0`).

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_u64_fold_overflow` | runtime-gap | **OK with runtime-gap annotation (pre-fix) → OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `0:1705032704 3000000000 0:0` (X=6000000000 and Z=4294967296 masked to 32 bits; Y=3000000000 control correct); post-fix prints `1:1705032704 3000000000 1:0`. Note: on -m32 `%lu` is 32-bit and `%llu` reads adjacent varargs slots pre-fix, so the repro prints each u64 as two i32 halves (`hi = @intCast(u64,X)>>32`, `lo = @intCast(u64,X) & @intCast(u64,4294967295)`) — see NOTES.md | F4/F5 guard types folded temps/storage globals from the binop's INT_LIT instead of the declared u64 |

**Post-F7 accounting: OK=197 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 205 repros**
(197 + 4 + 4 = 205; corpus grows 204 → 205 by `comptime_u64_fold_overflow`, counted OK).
Raw classifier FAIL stays **8** (4 green-guards + `field_store_drop`, `test_stub_0`
(std-lib-deferred), `self_embed_optional_cycle`, `fn_varargs_unsupported`). No other repro
flipped; 4 MD5 gates byte-identical; test_analyzer_bin PASS; build_test.sh 5/4 (baseline-identical).

## Task F8 — `comptime_const_chain` (ident_expr const-chain folding) (2026-08-06) — +1 repro (205 → 206)

Operator ruling I1-B ("include now"): `comptimeEvalEvaluate` must resolve `ident_expr` operands by
following const chains, so `const B: i32 = A + 5;` (where `const A: i32 = 30;`) folds to 35 and
`const C: i32 = B * 2;` folds to 70. Implemented in `comptime_eval.zig` as a depth-guarded
`ident_expr` branch (mirrors the array-size const-chain path `evalConstU32Full`,
type_resolver.zig:579-598: `symbolRegistryQualifiedLookup` across all module tables → const check
`(flags & 0x01) == 0` → recurse into `decl.child_1`), with a depth-16 cap so const cycles
(`const A = B + 1; const B = A + 1;`) cannot infinitely recurse.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_const_chain` | **FAIL** (gcc error, NOT merely a fold gap) | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `3570`; emitted `__module_init` stores `zT_0 = 35;` / `zT_1 = 70;` (int_const, no runtime `+`/`*`) | Pre-F8 the lowerer emits `load_global` for `A` in `A + 5`, but `A` (a non-storage const, literal init) gets **no C storage-global decl** → `zG_..._A` undeclared → **gcc FAIL**. F8 folds the ident away so the load is eliminated. Also guards: const-chain through two hops (`B * 2` from `A + 5`) |

**Post-F8 accounting: OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 206 repros**
(198 + 4 + 4 = 206; corpus grows 205 → 206 by `comptime_const_chain`, counted OK; pre-F8 it
classified **FAIL**, so this is a genuine FAIL→OK flip). Raw classifier FAIL stays **8** (4
green-guards + `field_store_drop`, `test_stub_0` (std-lib-deferred), `self_embed_optional_cycle`,
`fn_varargs_unsupported`). No other repro flipped. **MD5 gate: gol RE-BASELINED** — the emitted C
for `examples/z98/game_of_life` changes because `@intCast(i32, WIDTH)` / `@intCast(i32, HEIGHT)`
(WIDTH/HEIGHT are `const usize`) now fold at comptime (previously a runtime `(int)` load+cast);
runtime output is byte-identical (verified by run diff), so per the F-5 AMENDMENT B precedent
("runtime behavior is the gate, not byte-identity") the gol baseline is updated from
`d0d3051d…` to `e2f4c625…`. mud/lisp/json gates unchanged and byte-identical.

---

## F9 — gate sweep + comptime gap annotations cleared (2026-08-06)

Final task of the comptime arithmetic folding plan. All 5 comptime-arithmetic repros are now fully
OK with their emission/runtime-gap annotations **cleared** — the gaps were resolved by F1-F8.
The full gate battery was re-run at HEAD with a fresh /tmp bootstrap (`/tmp/f9b/zig1`, zig0 rc=0,
gcc rc=0, 0 errors); evidence in `.superpowers/sdd/task-F9-report.md`.

**Fix commits (comptime arithmetic folding, all 2026-08-06):**

| Commit | Task | Change |
|--------|------|--------|
| `7dc119a6` | F1 | comptime_eval.zig: add `bit_and`/`bit_or`/`bit_xor`/`shl`/`shr` to `comptimeEvalBinOp` (with shift-amount >=64 → null guard) |
| `dacf8cf6` | F2 | comptime_eval.zig: add `bit_not` and route the 12 binary/unary ops to comptime binop evaluation (`comptimeEvalEvaluate` binop arm) |
| `94853c65` | F3 | main.zig `phase_ComptimeEvaluation`: fold `const var_decl` binop/unary **inits** (not just `builtin_call`) into `comptime_values` |
| `ec71f9ad` | F4 | lower.zig: `comptime_values` guards on the 10 binary op handlers (add/sub/mul/div/mod/bit_and/bit_or/bit_xor/shl/shr) with INT_LIT→I32 remap — emit `int_const` when folded |
| `5ed90251` | F5 | lower.zig: `comptime_values` guards on `negate` + `bit_not` unary handlers (same INT_LIT→I32 remap) |
| `6dd614e7` | F6 | type_resolver.zig array-size handler: add `mul`/`div`/`mod_op` arms to `evalConstU32Full` size eval (closes the `comptime_array_size_gap` silent type-drop) |
| `827e0221` | F7 | main.zig `phase_SemanticAnalysis`: (a) gate the `resolved_types[var_decl] = init_type` write on `existing == null` so declared types aren't clobbered; (b) thread the declared type onto the init node for annotated module-scope consts — folded u64 consts >2^32 keep their declared width (fixes `comptime_u64_fold_overflow`) |
| `bf5d3636` | F8 | comptime_eval.zig: `ident_expr` const-chain branch in `comptimeEvalEvaluateDepth` (depth-16 guarded), mirroring the array-size `evalConstU32Full` chain — folds `const B: i32 = A + 5` from `const A` (fixes `comptime_const_chain` gcc FAIL) |

**Gate-sweep results (measured, /tmp/f9b/zig1):**

- **Repros 1+2** (`comptime_binop_not_folded`, `comptime_lower_ignores_fold`): dump rc=0, gcc rc=0,
  run rc=0, prints `40 20 300 3 0 -30 10 30 20 120 7 -31`; `__module_init`-scoped
  `grep -c '[\*\/\%]'` = **0** (all 12 consts emit `int_const` — emission gap closed).
- **Repro 3** (`comptime_array_size_gap`): dump rc=0, gcc rc=0; emitted `typedef unsigned char
  …[4000];` / `…[40];` / `…[2];` — arrays resolve `u8[4000]`/`u8[40]`/`u8[2]` (runtime gap closed).
- **Repro u64** (`comptime_u64_fold_overflow`): dump rc=0, gcc rc=0, run prints
  `1:1705032704 3000000000 1:0` (X=6000000000, Z=4294967296 correct via hi:lo halves).
- **Repro** `comptime_const_chain`: dump rc=0, gcc rc=0, run prints `3570`; `__module_init` stores
  `zT_0 = 35;` / `zT_1 = 70;` (int_const, no runtime `+`/`*`).
- **Varargs** (`fn_varargs_unsupported`): stays **FAIL** — dump rc=2, `error[2000]: expected
  identifier but found token` at `...`, 0 `.c` emitted (out of comptime scope).
- **Full corpus**: **206 repros, OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0**
  (198 + 4 + 4 = 206; raw classifier FAIL = 8 — the 4 green-guards are a sub-bucket).
  FAIL count unchanged vs the F8 baseline; no repro flipped; the 4 real FAILs are the 2
  std-lib-deferred import gaps (`field_store_drop`, `test_stub_0` — `error[3048]`),
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type), and `fn_varargs_unsupported`
  (varargs parse gap).
- **4 MD5 gates byte-identical** to the current baselines: mud `4644ad1349c55af80fa1a18fe0e17989`,
  gol `e2f4c62515b4ab5e5c5b1202f7c2e12e`, lisp `dd56cd23984d2533eebd244ffe593791`,
  json `900cb401779aab11bcf22ce35100323c`.
- **test_analyzer_bin PASS** (43/43 tests ok, run rc=0).

This is the final accounting for the plan: **206 repros, OK=198 / FAIL=4 / green-guards=4** —
the comptime arithmetic folding feature is complete and gated.

---

## Task F1 — `@intCast` range-check (Option B + scope b) (2026-08-06) — +1 repro (206 → 207)

Per I1 (`/workspace/znineeight/.superpowers/sdd/I-intcast-range-report.md`) + operator ruling
(binding): the lowerer's explicit `@intCast` handler always set `is_checked=0`, so zig1 lowered
`@intCast(i32, i64_expr)` to a raw C `(int)` cast — silently wrapping on overflow (lisp `(fact 13)`
printed garbage `1932053504` instead of panicking). Fix site = **Option B** (c89_emit wraps via the
existing `int_cast.is_checked` field + source-aware per-pair `__bootstrap_<DST>_from_<SRC>` naming);
scope = **(b) full oracle rule** (check iff narrowing OR same-width reinterpret).

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `intcast_range_check` | runtime-gap: dump rc=0, gcc clean, prints `-2147483648` (wrapped), rc=0 — **NO panic**; emitted `zT_6 = (int)i;` | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean; emitted `zT_6 = __bootstrap_i32_from_i64(i);`; run PANICS with `panic: integer cast overflow in @intCast`, nonzero exit (rc=134) — the intended fix, matching the zig0 oracle | guards: the in-range path must still pass (i32-from-i64 of a small value prints correctly); comptime-folded `@intCast` literals skip the runtime cast; pure widening stays a raw cast |

**Implementation:** lower.zig computes src type via `getTempType` and sets `is_checked=1` when
`src_bits > dst_bits` OR (`src_bits == dst_bits` AND signedness differs); c89_emit's `.int_cast`
checked arm builds `__bootstrap_<DST>_from_<SRC>` from `c.target` + `getTempTypeByIndex`; the 19
oracle helpers were added to `sf/src/include/zig_runtime.c` (definitions) + `sf/src/include/
zig_runtime.h` (C89 `static` definitions, per-TU self-sufficient — the oracle's own header pattern
is `ZIG_INLINE ZIG_UNUSED`), message standardized to `"integer cast overflow in @intCast"`.
`std_checked_cast_*` (upper-bound-only, false-panics on negatives) is NOT used.

**Post-F1 accounting: OK=199 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 207 repros**
(199 + 4 + 4 = 207; corpus grows 206 → 207 by `intcast_range_check`, counted OK — no FAIL
increase). Raw classifier FAIL stays **8**. No other repro flipped.

**MD5 gate — ALL 4 RE-BASELINED (scope b):** mud, gol, lisp, json each contain explicit runtime
`@intCast` sites that are now checked. New values: mud `0064a08149b07aa591033210ffce68f5`,
gol `51d6d078bdecad022318bded23182f72`, lisp `e54be381967cab4a3f0886e106166771`,
json `6528f26f396092976b46938482a4f0d4`. Runtime-verified identical except lisp `(fact 13)` now
PANICS (the intended fix); per the F-5 AMENDMENT B precedent ("runtime behavior is the gate, not
byte-identity"). Per-gate helper counts: mud `i32_from_usize` x4 + `usize_from_i32` x1; gol
`i32_from_usize` x2 + `usize_from_i32` x2; lisp `i32_from_i64`, `i32_from_u32`, `i32_from_usize`,
`u32_from_i32`, `u8_from_i32`, `usize_from_i32`, `c_char_from_u8`; json `usize_from_i32` x1.
(json's legacy-runtime link — `src/runtime/zig_runtime.c` — lacks the new helpers, so the header
`static` definitions are what make the multi-module json gate link; mud/gol/lisp additionally link
the extern defs in `sf/src/include/zig_runtime.c`.)

## Task F2 — `ice_literal_overflow` (u64-safe int_literal marker) (2026-08-06) — +1 repro (207 → 208)

The `int_literal` lowering marker (`ILR:i … v<value>`) called
`itoa_mod.itoa(@intCast(u32, val), …)` with `val` the u64 literal value. Since
F1's `@intCast` range-check, that cast lowers to the checked
`__bootstrap_u32_from_u64`, so any program that runtime-lowers a literal >= 2^32
aborted the compiler itself (`PANIC: integer overflow in @intCast`), dump rc=134.
The lowering pipeline is correct — only the marker was broken. Fixed by adding
`pal.markerWriteInt64` (itoa64, `[24]u8` buffer) and using it for the value marker.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `ice_literal_overflow` | **ICE** (dump rc=134, SIGABRT) | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `1:705032704 1:0` (correct hi/lo halves of X=5000000000 and Y=4294967296) | guards: any literal >= 2^32 that reaches runtime lowering must not crash the compiler; the `--markers` ILR trace renders the full u64 value (`ILR:i39v5000000000`) |

**Note on repro form:** the brief's exact const-only source (`pub const X: u64 =
5000000000;` + `print_u64(X)`) does NOT reproduce the ICE on the current tree —
F8's ident_expr const-chain fold resolves `X` at comptime, so the literal never
reaches the `int_literal` runtime-lowering marker. The repro keeps the brief's
consts (the program still contains literals >= 2^32) AND adds a runtime-lowered
literal (`var sink: u64 = 5000000000;`) that exercises the marker path. Pre-fix
the repro dumps rc=134; post-fix rc=0. See `ice_literal_overflow/NOTES.md`.

**Post-F2 accounting: OK=200 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over
208 repros** (200 + 4 + 4 = 208; corpus grows 207 → 208 by `ice_literal_overflow`,
counted OK — the pre-fix ICE becomes a clean post-fix OK, so no FAIL increase).
Raw classifier FAIL stays **8**. The 4 real FAILs unchanged:
`field_store_drop` + `test_stub_0` (std-lib-deferred, `error[3048]`),
`self_embed_optional_cycle` (F-8 residual), `fn_varargs_unsupported` (varargs
parse gap). **4 MD5 gates byte-identical** (markers → stderr only; emitted C
unchanged): mud `0064a08149b07aa591033210ffce68f5`, gol
`51d6d078bdecad022318bded23182f72`, lisp `e54be381967cab4a3f0886e106166771`,
json `6528f26f396092976b46938482a4f0d4`. test_analyzer_bin PASS.

---

## Task F5 — varargs end-to-end (`@cVaStart`/`@cVaArg`/`@cVaEnd` + `...` emission + extern prototypes) (2026-08-06) — +1 repro (208 → 209)

4-item compiler-gaps plan Task F5 (`.superpowers/sdd/task-F5-brief.md`). Full
varargs support: Z98 variadic fn bodies read their `...` args via `va_list` +
`@cVaStart`/`@cVaArg`/`@cVaEnd`; `...` is emitted in C fn prototypes; variadic
externs get C prototypes (Option B); `stdarg.h` is emitted gated on actual
`va_*` usage.

| Repro | RED (pre-fix) | Classification (measured, /tmp/zigf5b/zig1) | Guards |
|-------|---------------|---------------------------|--------|
| `fn_varargs_unsupported` | parse gap → F3 OK but no prototype emission | **OK post-F5** — dump rc=0; emitted header carries the Option B extern prototype `int printf(unsigned char*, ...);` (name-passthrough); no `stdarg.h` (no `va_*` use); gcc-clean, links + runs rc=0 | variadic extern must get a C prototype; no `@cInclude`'d header may conflict with it |
| `fn_varargs_body` (NEW) | n/a (new repro) | **OK** — dump rc=0; emitted `#include <stdarg.h>`, `int zF_..._sum(unsigned int count, ...) {`, `va_start(zL_vl, zL_count);`, `zT_11 = va_arg(zL_vl, int);`, `va_end(zL_vl);`, `int printf(unsigned char*, ...);`; gcc-clean; runs printing `sum=60` (the KEY proof `sum(3, 10, 20, 30)` = 60 via `@cVaArg`), rc=0 | a Z98 variadic body must read args; no `@cInclude("<stdio.h>")` with a variadic printf (type conflict `unsigned char*` vs `const char*`) |

**Implementation summary:**
- lower.zig: `@cVaStart`/`@cVaArg`/`@cVaEnd` name_ids in `lowererInit`;
  builtin dispatch inserted after `@ptrToInt`, before the `ec.len>=2` cast
  block; `lowerFn` reads `FnPayload.flags_packed` (bit0) → `func_ptr.is_variadic`
  (the `child_0==0` anytype-marker branch is **kept as a defensive OR**, NOT
  removed — see deviations below).
- c89_emit.zig: 3 emitting `.va_start`/`.va_arg`/`.va_end` arms; `stdarg.h`
  gated on any `va_*` LirInst in the TU at 3 sites (emitModuleHeader,
  emitModuleHeaderFile, emitModuleFile); `emitFunctionForwardDecl`
  name-passthrough for externs; the two extern-prototype guards
  (`:1962`/`:2108`-era) now `is_extern==0 OR is_variadic!=0`.

**Deviations from the brief's literal text (both REQUIRED to keep the 4 MD5
gates byte-identical — see Task F5 report):**
1. **`lower.zig:4680` child_0==0 branch is kept as a defensive no-op-instead-of
   removal.** The brief premised "no gate has a variadic fn"; in fact **mud and
   gol both define `print(fmt, *const c_char, args: anytype)`** (anytype →
   `child_0==0` param) whose C signature relies on the marker branch emitting
   `...` (`void zF_..._print(char*, ...);` is in both baselines). Making it a
   pure no-op deletes `...` from those signatures → mud/gol MD5 drift + gcc
   break. Kept as an OR with the flags_packed read (true `...` still works).
2. **`stdarg.h` gating is on actual `va_*` LIR insts, not on `is_variadic`.**
   The brief's premise "no gate has a variadic fn" is also wrong for mud/gol
   (their anytype-print has `is_variadic=1` but never uses `va_*`); gating on
   `is_variadic` would inject `#include <stdarg.h>` into mud/gol → MD5 drift.
   Gating on `va_*` insts keeps mud/gol/lisp/json byte-identical AND still
   emits `stdarg.h` for real varargs bodies.

> **F5b RESOLUTION (Task F5b, AMENDMENT 5, 2026-08-06, commit `ef529f42`):**
> deviation 1 is now MOOT. F5b migrated mud/gol `print(fmt, args: anytype)` to a
> true trailing `...` (`print(fmt, ...)`) and **deactivated** the `child_0==0`
> anytype-marker branch (its `else { is_variadic = 1 }` was removed from
> `lowerFn`) — `is_variadic` now comes solely from the F3 flag-bit path
> (`FnPayload.flags_packed` bit0, set by parser flag 0x01 via
> type_resolver.zig:1126-1127). mud/gol re-baselined to `50beb1bf…` /
> `0d8f0092…` (runtime byte-identical, AMENDMENT B precedent); lisp/json
> unchanged. Deviation 2 (stdarg.h gating on actual `va_*` insts) remains in
> force. A variadic fn with ZERO fixed params (`fn f(...)`) is now rejected
> `error[3012]` (final-review fix, 2026-08-06).

**Post-F5 accounting: OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over
209 repros** (202 + 4 + 3 = 209; corpus grows 208 → 209 by `fn_varargs_body`;
`fn_varargs_unsupported` FAIL→OK). Raw classifier FAIL stays **7** (4
green-guards sub-bucket). The 3 real FAILs: `field_store_drop` + `test_stub_0`
(std-lib-deferred, `error[3048]`) + `self_embed_optional_cycle` (F-8 residual).
**4 MD5 gates byte-identical**: mud `e306b1874e51e06a23b708bcd79fec6d`, gol
`51d6d078bdecad022318bded23182f72`, lisp `55044a1f64011bc644cddbcf73b5de93`,
json `b5f56ebd51d2f0fcd379a1e083594462`. test_analyzer_bin PASS.

---

## Task F7 — gate sweep + docs + final review prep (2026-08-06) — 4-item plan CLOSEOUT

Final task of the 4-item compiler-gaps plan (brief `.superpowers/sdd/task-F7-brief.md`). Full
corpus + MD5 gate sweep at HEAD with a fresh /tmp bootstrap (`/tmp/f7build/zig1`, zig0 rc=0, gcc
rc=0, 0 errors); evidence in `.superpowers/sdd/task-F7-report.md`. **Docs-only — no sf/src
changes.**

**Final accounting (measured): 209 repros, OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
(202 + 4 + 3 = 209; raw classifier FAIL = 7). Identical to the v20 totals — **no repro flipped**
during the final sweep. The plan's Step-1 prediction ("210 repros, OK=200/FAIL=3/gg=4") was
**STALE**: it double-counted `fn_varargs_unsupported`, which was already in the 208 baseline
(209 = 208 baseline + `fn_varargs_body`). The corrected accounting is recorded in the Totals
section at the top of this file.

**4-item fixes — all complete (fix refs):**

| # | Item | Fix | Key commit(s) | Gate evidence |
|---|------|-----|---------------|---------------|
| 1 | `@intCast` narrowing + reinterpret range-check | c89_emit emits `__bootstrap_<DST>_from_<SRC>` (checked) — see Task F1 section | `14f31511` | `intcast_range_check` OK; run PANICS (`integer cast overflow in @intCast`) rc=134, matching oracle |
| 2 | ICE on literals ≥ 2^32 | u64-safe `int_literal` marker via `pal.markerWriteInt64` — see Task F2 section | `5d280a6d` | `ice_literal_overflow` OK; prints `1:705032704 1:0` rc=0 |
| 3 | Full varargs (`@cVaStart`/`@cVaArg`/`@cVaEnd` + `va_list` + `...` emission + extern variadic prototypes) — see Task F5 section | `4448d187` (parser bit0 flag), `b8deb732` (va_list TYPE_VA_LIST=21 + LIR), `c420a277` (emission), `ef529f42` (F5b) | `fn_varargs_unsupported` FAIL→OK (runs `printf`); `fn_varargs_body` OK — **`sum=60`** rc=0 |
| 4 | Lisp closures capture current env | `eval.zig:124` `env_to_value(env.*,…)` → `curr_env.*` — see `examples/z98/lisp_interpreter_curr/NOTES.md` | `0cb7891c` | `((make-adder 5) 3)`→8, `((add 10) 1)`→11, `((make-func 42))`→42 (were `UnboundSymbol`) |

**MD5 gates (byte-identical to the current baselines — no re-baseline needed):**
mud `50beb1bf5edc4cbb638f84aa027ffade`, gol `0d8f0092c22c04375482a198691a3957`,
lisp `605b597e8b7cff60de0ce84a0593e743`, json `b5f56ebd51d2f0fcd379a1e083594462`.

**Runtime spot-checks (this sweep):** `fn_varargs_body` → `sum=60` rc=0; `intcast_range_check` →
rc=134 `panic: integer cast overflow in @intCast` (the intended fix); `ice_literal_overflow` →
`1:705032704 1:0` rc=0; lisp closures `8`/`11`/`42`; `((twice square) 3)` → SEGFAULT (rc=139);
`(fact 13)` → rc=134 (F1 range-check, intended).

**Known lisp limitations (documented in lisp NOTES.md — NOT compiler defects, operator-accepted):**
`((twice square) 3)` / `((compose square square) 3)` SEGFAULT (env-capture cycle in lisp source,
exposed by the F6 fix — was `UnboundSymbol`); `(countdown 3000)` OOM (~3000 threshold); post-OOM
REPL dead (no `sand_reset` on the error path); `(fact 13)` PANICS (correct — F1 range check).

No other repro flipped; `fn_varargs_unsupported` stays OK; 4 MD5 gates byte-identical;
`test_analyzer_bin` PASS (from prior F-tasks). This is the **final accounting for the plan**.

---

## I-task: rogue_mud build attempt — labeled_stmt frontend gap (2026-08-07) — +1 repro (209 → 210)

Investigation task: attempt to build `examples/z98/rogue_mud/` with the current zig1
(`/tmp/zigaps/zig1`, fresh HEAD bootstrap 2026-08-07, zig0 rc=0, gcc rc=0, 0 errors). The
pre-analysis predicted SUCCESS (all patterns well-tested + the catch-block-expression fix P3-4/P3-7);
the actual dump FAILS at type resolution.

| Repro | RED (measured) | Classification | Guards |
|-------|----------------|----------------|--------|
| `labeled_stmt_unhandled` | dump rc=2, `error[3020]: internal error: unhandled node kind in type resolution`, 0 `.c` emitted | **FAIL** (real frontend gap; rc=2 + `error[3020]` is outside the ICE regex — not an ICE, not a green-guard) → **OK post-F1 (2026-08-07)** — dump rc=0, 1 `.c`, gcc-clean, links, runs rc=0 and TERMINATES (the labeled `break :game_loop` now matches the loop via `current_label` propagation; pre-fix it was a no-op and `while(true)` HUNG) | `semanticAnalyzerResolveStmtIter` (semantic_analyzer.zig:1599-1778) has no `labeled_stmt` (AstKind 82) case → generic `else` (:1773) forwards to `resolveExpr` → unhandled-else (:1424-1429) emits error[3020]. Correct behavior: unwrap the label and push the wrapped child onto the stmt work stack — now implemented (parser.zig + semantic_analyzer.zig + lower.zig; see Task F1 section below) |

**Dump diagnostics (rogue_mud):** 2× `error[3020]`, one per labeled statement in the program —
`main.zig:92` `game_loop: while (true)`, `lib/scenario.zig:59` `bsp_loop: while (stack.len > 0)`.
Both are the SAME distinct failure (kind 82). The reported locations (`main.zig:32:2`,
`scenario.zig:159:8`) are BOGUS — the 3020 diagnostic passes `node_idx` as both span ends
(semantic_analyzer.zig:1428), so the reported file:line never matches the labeled statement.
Note: other latent rogue_mud gaps may hide behind this blocker (unverifiable without a fix); the
labeled_stmt gap is the only DISTINCT failure actually observed.

**Oracle verification:** `./sf/build/zig0 -o out.c repro` accepts the labeled loop (rc=0, emits C)
— labeled statements are valid Z98, so this is a genuine compiler gap, not a correct rejection.
zig1 dump for the repro: rc=2, `error[3020]`, 0 `.c` (markers `ST:N<node> ST:K82`).

**Post-repro accounting: OK=202 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 210 repros**
(202 + 4 + 4 = 210; corpus grows 209 → 210 by `labeled_stmt_unhandled`, counted FAIL). Raw
classifier FAIL **7 → 8** (green-guards remain a sub-bucket of the raw count). The 4 real FAILs:
2 std-lib-deferred (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type) + `labeled_stmt_unhandled`
(error[3020], sema labeled_stmt gap). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
No existing repro flipped. Investigation complete — no compiler fixes made.

---

## Task F1 — labeled statement support in parser, sema, lowerer (2026-08-07) — FAIL→OK

The `labeled_stmt_unhandled` repro (added 2026-08-07 by the rogue_mud I-task) is now **OK**:
`game_loop: while (true) { break :game_loop; }` dumps, compiles, links, and **runs rc=0 and
TERMINATES** (pre-fix the labeled `break :game_loop` matched no loop and was a no-op, so the
`while(true)` HUNG at runtime). 5 edits in 3 files (plan `labeled statement support implementation
plan` `37e1892a`, AMENDMENT 1 `50723411`):

1. **Parser (parser.zig:1285 + :1299):** `parserParseLabeledStmt` + `parserParseLabeledBlockExpr`
   now store `label_tok.value.string_id` in the `labeled_stmt` node payload (was hardcoded `0`),
   so `break :label` / `continue :label` can match it.
2. **Sema stmt dispatcher (semantic_analyzer.zig:1767):** `labeled_stmt` case added to
   `semanticAnalyzerResolveStmtIter` before `defer_stmt` — transparent unwrap: pushes
   `node.child_0` onto the stmt work queue (mirrors the defer_stmt unwrapper); one case covers
   while/for/block/if/switch inner kinds.
3. **Sema expr redirect (semantic_analyzer.zig:1341):** `labeled_stmt` added to the
   var_decl/defer/errdefer branch → delegates back to `semanticAnalyzerResolveStmtIter`
   (defensive; prevents the `error[3020]` unhandled-else crash if a labeled_stmt ever reaches
   resolveExpr).
4. **Lowerer unwrap (lower.zig:3516):** `labeled_stmt` case in `lowerStmt` recurses into
   `node.child_0`, saving/setting/restoring `self.current_label = node.payload` around the
   recurse.
5. **Edit 4b — label propagation (AMENDMENT 1, required):** `LirLowerer` gains `current_label:
   u32` (init 0); all 3 loop-push sites (while :3627, for-range :3726, for-slice :3780) now use
   `.label_id = self.current_label` instead of hardcoded `0`. The original 4-edit version was
   verified unsatisfiable (labeled break matched no `LoopInfo` → runtime no-op → hang); the
   operator ruling amended the plan to add edit 4b, which the F1 implementer prototyped + verified,
   then reverted pending ruling. Re-applied here.

**Gate evidence (measured, /tmp/zlbl/zig1):**

- Repro `labeled_stmt_unhandled`: dump rc=0, 1 `.c` emitted, gcc rc=0, link rc=0, **run rc=0 and
  TERMINATES** (the hang was the bug).
- Nested-labels probe `outer: while (true) { inner: while (true) { i += 1; if (i < 3) { continue
  :inner; } break :outer; } }` + `if (i != 3) @panic("FAIL")`: dump rc=0, gcc rc=0, link rc=0,
  run rc=0 (assertion passes — `continue :inner` re-loops, `break :outer` exits the outer loop).
- 4 MD5 gates **byte-identical**: mud `50beb1bf5edc4cbb638f84aa027ffade`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462`.
- test_analyzer_bin **PASS** (`Analyzer tests passed`); build_test.sh 5/4 (baseline-identical).
- Corpus: 210 repros, **OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** (203+3+4=210; raw
  classifier FAIL **8 → 7**). Only flip: `labeled_stmt_unhandled` FAIL→OK. The 3 remaining FAILs:
  2 std-lib-deferred (`field_store_drop`, `test_stub_0`, `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). 4 green-guards unchanged.

**Documented scope limit (accepted, not fixed):** `break :label` out of a labeled NON-LOOP block
(`lbl: { break :lbl; }`) remains unsupported — the break/continue handlers (`lower.zig:4005-4044`)
search only `loop_stack`, and a labeled block never pushes a `LoopInfo`. Loop labels
(`label: while` / `label: for`) are fully supported; out of this repro's scope (loop case only).

**Accounting: OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 210 repros** — see the
Totals section at the top.

---

## Task F1 — duplicate-typed struct fields emit correctly (dup field topo-sort) (2026-08-07) — +2 repros (210 → 212)

The `dup_optptr_field_emit` + `dup_val_field_emit` repros (added 2026-08-07 by the rogue_mud
I-task, per `.superpowers/sdd/I-rogue-dupfld-report.md`) are now **OK**. Both previously failed
gcc with `unknown type name 'zT_...'`: the `tstTopologicalSort` Kahn algorithm dropped the struct
from the `sorted` array, so its forward-decl and body were never emitted while the lowerer still
referenced the type by name.

- **Root cause:** `tstEdgesCount` (`sf/src/c89_emit.zig:799-839`) counted **one edge per field
  occurrence**, so a struct with two same-typed edge-forming fields (`a: Point, b: Point`;
  `left: ?*Node, right: ?*Node`) got `indegree = 2`. The Kahn dequeue loop (`:960-968`)
  decremented **once per dependent type** (`tstIsDep` boolean, `:961`), leaving indegree 1 → the
  struct was never dequeued → dropped from `sorted` → no fwd-decl/body → gcc `unknown type name`.
- **Fix (Option B, operator ruling):** `tstEdgesCount` now counts each distinct dependent type
  **once** — deduped same-typed field edges in the struct/tagged_union/union branches, including
  dedupe of `tag_type` vs fields in the tagged_union branch. New helper `tstSeenInRange`
  (c89_emit.zig:799-805) scans the field range for an already-counted type id. Mirrored in
  `tstEdgesFill` (dead code, 0 callers — zero runtime effect) for consistency. Indegree now equals
  "number of distinct dep types" == the count of `tstIsDep`-true decrements, so count and dequeue
  can never drift; Kahn drains fully, which also eliminates the uninitialized-`sorted`-tail hazard
  (`sandAlloc` does not zero) for this pattern.
- **Files:** `sf/src/c89_emit.zig` (commit `fix: duplicate-typed struct fields emit correctly
  (dup field topo-sort)`).

**Gate evidence (measured, /tmp/zf1/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `dup_val_field_emit`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0;
  `zig_special_types.h` now carries the `zT_9808F547_Line` fwd-decl + body (`zT_EAA8EF31_Point a;`
  / `b;`).
- `dup_optptr_field_emit`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0;
  `zT_3468032D_Node` fwd-decl + body now emitted.
- 4 MD5 gates **byte-identical**: mud `50beb1bf5edc4cbb638f84aa027ffade`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` (no gate program has duplicate edge-forming field types).
- Full corpus sweep (216 dirs, /tmp/zf1/zig1): **OK=206 / FAIL=10 (raw) / ICE=0 / CRASH=0**. Of the
  raw FAIL=10: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 3 I-task repros for the other gaps
  (`undef_arr_struct_literal`, `xmod_pub_const_global`, `switch_mixed_case_argtype` — stay FAIL
  until F2/F3/F4).
- **F1 accounting: 210 → 212 repros, OK=205 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (205 + 3 + 4 = 212; raw classifier FAIL stays **7**). Only flip:
  `dup_optptr_field_emit` + `dup_val_field_emit` FAIL→OK. The 3 remaining FAILs: 2
  std-lib-deferred (`field_store_drop`, `test_stub_0`, `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). 4 green-guards unchanged. No
  existing repro flipped. See the Totals section at the top.

---

## Task F2 — undefined struct-array field init emits valid C (undef_arr_struct_literal) (2026-08-07) — +1 (212 → 213)

The `undef_arr_struct_literal` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-undefarr-report.md`) is now **OK**. It previously failed gcc with
`incompatible types when assigning to type 'zT_..._Client' from type 'int'`: the emitted C
expanded the `undefined` initializer of the `[5]Client` field into a zero-fill loop
`clients[_j] = 0;` — ill-typed for struct elements.

- **Root cause:** `emitFieldAssign` (`sf/src/c89_emit.zig:276-287`) hardcodes
  `base.fld[_j] = 0;` for ALL array-valued fields, never checking the element type or the `src`
  temp — only valid for scalar elements. The zig0 oracle emits NOTHING for `undefined` array
  fields (struct and primitive elements, verified).
- **Fix (Option A, operator ruling):** in the LOWERER (upstream, matches the oracle exactly),
  `sf/src/lower.zig` now skips the `assign_field` for a struct-literal field entirely when the
  field value is `undefined_literal` AND the field's declared type is `array_type`. A pre-scan at
  `lower.zig:2988-3027` sets `is_undef_arr_field` (struct + tagged-union kinds); the tagged-union
  payload branch (`:3063-3068`) and the struct branch (`:3072-3081`) both skip the
  `emitInst(assign_field)`. Skipping the field value's `lowerExpr` also drops the dead
  `undefined_const` temp (`zT_4 = 0;`). Emitter untouched.
- **Gate consequence (operator-approved re-baseline, F-5 AMENDMENT B precedent):** **mud
  RE-BASELINED** — `examples/z98/mud_server/main.zig:159` `.buffer = undefined` (`[256]u8`
  primitive array) drops its dead zero-fill (was `/tmp/mud_gate.c:800-802`). Runtime verified
  IDENTICAL: new mud prints "MUD server listening on port 4000" and exits rc=124 (timeout),
  matching the pristine build. New mud MD5 `906fa59c8676bb1054d3fcc13704fce5` (was
  `50beb1bf...`). gol/lisp/json byte-identical (no struct-literal `undefined` array fields).
- **Files:** `sf/src/lower.zig` (commit `fix: undefined struct-array field init emits valid C
  (undef_arr_struct_literal)`).

**Gate evidence (measured, /tmp/zf2/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `undef_arr_struct_literal`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0. Emitted C is
  just `zT_1.listen_socket = zT_3;` — no `clients[_j] = 0` zero-fill, no dead `undefined_const`
  temp.
- 4 MD5 gates: mud `906fa59c8676bb1054d3fcc13704fce5` (RE-BASELINED, runtime-verified
  identical — "MUD server listening on port 4000", rc=124), gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` — the latter three byte-identical.
- Full corpus sweep (216 dirs, /tmp/zf2/zig1): **OK=207 / FAIL=9 (raw) / ICE=0 / CRASH=0**. Of
  the raw FAIL=9: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 2 I-task repros for the other gaps
  (`xmod_pub_const_global`, `switch_mixed_case_argtype` — stay FAIL until F3/F4).
- **F2 accounting: 212 → 213 repros, OK=206 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (206 + 3 + 4 = 213; raw classifier FAIL stays **7**). Only flip:
  `undef_arr_struct_literal` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.

---

## Task F3 — cross-module pub const resolves (xmod_pub_const_global) (2026-08-07) — +1 (213 → 214)

The `xmod_pub_const_global` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-xmodconst-report.md`) is now **OK**. It previously failed gcc with
`'zG_..._COLOR_WHITE' undeclared`: the cross-module `pub const` literal-init
(`pub const COLOR_WHITE: u8 = 7`) registers as `SymbolKind.global` but gets NO F-7 storage slot
(main.zig:616-660 skips literal-init consts, bit0=mutable only), so there is no definition in the
owner `.c` and no extern in the module header, and the consumer's `load_global` read referenced an
undeclared `zG_` name.

- **Root cause:** lower.zig:2005-2011 (the cross-module `SymbolKind.global` module-field-access
  branch) unconditionally lowered every module-qualified global reference to `load_global`,
  never consulting the const bit or the decl init.
- **Fix (Option C, operator ruling):** `sf/src/lower.zig` — the cross-module
  `SymbolKind.global` branch now, when `(ts.flags & 0x01) == 0` (const) and the target's
  `decl_node.child_1` init is an int/float/char literal, emits the corresponding
  `int_const`/`float_const` typed at the DECLARED type (`gbl_tid` from
  `resolvedTypeTableGet(resolved_types, ts.decl_node)`, i.e. `u8` not `TYPE_U32` — avoids the F-7
  u64-width regression class), mirroring the same-module literal fold at lower.zig:1681-1710. The
  `load_global` fallback is retained for non-literal consts (already storage-classified via
  main.zig:627). No bare `zG_` definition emitted (zero-init trap avoided).
- **Gate consequence:** none — **4 MD5 gates byte-identical** (mud `906fa59c…`, gol `0d8f0092…`,
  lisp `605b597e…`, json `b5f56ebd…`; no gate program has a cross-module scalar `pub const`).
- **Files:** `sf/src/lower.zig` (commit `fix: cross-module pub const resolves (xmod_pub_const_global)`).

**Gate evidence (measured, /tmp/zf3/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `xmod_pub_const_global`: dump rc=0, 2 `.c`, per-file gcc-clean, link rc=0, run rc=0. Emitted C
  folds both refs: `zT_3 = 7;` (`fg`), `zT_5 = 7;` (`cell.fg`), `zT_4 = 0;` (`bg`), typed
  `unsigned char`; colors.c stays `/* EOF */`.
- 4 MD5 gates: mud `906fa59c8676bb1054d3fcc13704fce5`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` — all four byte-identical, no re-baseline.
- Full corpus sweep (216 dirs, /tmp/zf3/zig1): **OK=208 / FAIL=8 (raw) / ICE=0 / CRASH=0**. Of
  the raw FAIL=8: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 1 I-task repro (`switch_mixed_case_argtype` —
  stays FAIL until F4).
- **F3 accounting: 213 → 214 repros, OK=207 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (207 + 3 + 4 = 214; raw classifier FAIL stays **7**). Only flip:
  `xmod_pub_const_global` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.

---

## Task F4 — switch mixed-case call-arg typing (switch_mixed_case_argtype) (2026-08-07) — +1 (214 → 215)

The `switch_mixed_case_argtype` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-switcharg-report.md`) is now **OK**. It previously failed gcc with
`error: incompatible type for argument 1/3 of 'zF_..._saveDungeon'`: the `&arena` arg temp was
`unsigned int` and the string-literal temp `char*` instead of `Sand*` / `Slice_u8`.

- **Root cause (I4, confirmed):** NOT `call_arg_types` corruption — a **sema mid-switch abort**.
  The MIX else-branch at `semantic_analyzer.zig:1167` did `return type_mod.TYPE_VOID;` when two
  prong bodies had non-coercible types (assignment `dx = 0` → i32 vs empty block `{}` → void),
  aborting `semanticAnalyzerResolveSwitchExpr` and skipping all prongs *after* the conflict. The
  call prong (`'v','V'`) was therefore never sema'd, so the fixed-param loop at
  `semantic_analyzer.zig:775` never populated `call_arg_types`, and the lowerer fallback
  (`lower.zig:2388`) typed the arg slots as raw lowered types (`unsigned int` for `&arena`,
  `char*` for the string literal).
- **Fix (Option A, operator ruling):** `semantic_analyzer.zig:1167` — replaced `return
  type_mod.TYPE_VOID;` with `continue;` (skip this prong's contribution to the switch's `unified`
  type but keep resolving the remaining prongs, so the call prong IS sema'd and `call_arg_types`
  is populated normally). Kept the `resolvedTypeTableSet(..., TYPE_VOID)` on the same line
  (stmt-switch resolved type is unused). Lowerer untouched (the 4 call-arg paths were NOT the bug).
- **Gate evidence (measured, /tmp/zf4/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**
  - `switch_mixed_case_argtype`: dump rc=0, 2 `.c` emitted, per-file gcc-clean, link rc=0, run
    rc=0. Emitted arg temps now correctly typed: `zT_3E40CD83_Sand* zT_24;`,
    `zT_8F083A69_Slice_zT_0B42B2F8_u zT_26;`, string literal built into a `Slice`.
  - 4 MD5 gates **byte-identical**: mud `906fa59c8676bb1054d3fcc13704fce5`, gol
    `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
    `b5f56ebd51d2f0fcd379a1e083594462` (I4 measured the same; gol/lisp MIX aborts are
    pre-existing and emit no coercion-needing skipped call).
  - Full corpus sweep (216 dirs, /tmp/zf4/zig1): **OK=209 / FAIL=7 (raw) / ICE=0 / CRASH=0**. Of
    the raw FAIL=7: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
    `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
    `test_stub_0`, `self_embed_optional_cycle`). Only flip: `switch_mixed_case_argtype` FAIL→OK.
  - test_analyzer_bin **PASS** (`Analyzer tests passed`, run rc=0).
- **F4 accounting: 214 → 215 repros, OK=208 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (208 + 3 + 4 = 215; raw classifier FAIL stays **7**). Only flip:
  `switch_mixed_case_argtype` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.
- **Files:** `sf/src/semantic_analyzer.zig` (commit `fix: switch mixed-case call-arg typing
  (switch_mixed_case_argtype)`).
- **Known adjacent bug (out of scope, documented follow-up):** char-literal switch `case` labels
  are still dropped at `lower.zig:3858-3860` (stmt switch) / `:3121-3123` (expr switch; refs superseded — actual sites lower.zig:3183 expr / :3920 stmt), so this
  repro's emitted `switch (c)` has no `case` labels and its body is **unreachable at runtime**
  (always takes `default`). The F4 runtime gate passes only because the repro prints nothing and
  `c != -1` is false. This affects `rogue_mud`'s input switch too (`examples/z98/rogue_mud/
  main.zig:236-256`); a follow-up `switch_char_case_labels` repro + F-task is recommended. NOT
  fixed here.

## Task F5 — gate sweep + tech docs, rogue_mud emission-defects plan closeout (2026-08-07)

Docs-only + verification task (no compiler code changed — the 4 F-fixes F1 a5ac4598, F2
ba89a6e0, F3 317f3a82, F4 b1b3f7e9 are all on the branch). Compiler under test: `/tmp/zf5/zig1`
(fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors).

- **Full corpus sweep (216 dirs, QUICK_REF classifier): `OK=209 / FAIL=3 / ICE=0 / CRASH=0 /
  GREEN=4 / TOTAL=216`.** Reconciliation vs the 215-repro manifest total: 216 dirs = 215 manifest
  repros + `opt_slice_null_return` (OK-by-gate, type-incorrect, tracked separately — its OK is
  the 209th, so effective OK=208). Raw classifier FAIL = 7 = 4 green-guards (sub-bucket) + 3 real
  FAILs (`field_store_drop`, `self_embed_optional_cycle`, `test_stub_0`). The 5 gap repros all
  OK: `dup_optptr_field_emit`, `dup_val_field_emit`, `undef_arr_struct_literal`,
  `xmod_pub_const_global`, `switch_mixed_case_argtype` — each runtime-verified (dump rc=0, gcc
  rc=0, run rc=0). No repro flipped vs F4; no regressions.
- **4 MD5 gates verified byte-identical** (no re-baseline this task; the mud re-baseline was
  recorded in F2): mud `906fa59c8676bb1054d3fcc13704fce5`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462`.
- **5 gap rows cleared → OK** in this manifest; the 3 remaining FAILs stay enumerated (2
  std-lib-deferred `error[3048]` + `self_embed_optional_cycle` gcc incomplete-type).
- **`opt_slice_null_return` latent guard** — OK-by-gate (gcc rc=0), but type-incorrect (emits an
  `undefined_const` for a slice return); tracked separately, NOT a gate failure.
- **Out-of-scope follow-up (unchanged from F4):** char_literal switch `case` labels dropped at
  `lower.zig:3858-3860` (stmt switch) / `:3121-3123` (expr switch; refs superseded — actual sites lower.zig:3183 expr / :3920 stmt) — `rogue_mud`'s input switch
  (`examples/z98/rogue_mud/main.zig:236-256`) would be runtime-dead. A `switch_char_case_labels`
  repro + F-task is recommended.
- **Tech docs updated (AGENTS §1.1.1, `[updated: 2026-08-07]`):**
  - `08_c89_emission.md` — F1: `tstEdgesCount`/`tstEdgesFill` dedupe same-typed field edges
    (distinct dep type counted once) via new `tstSeenInRange` (c89_emit.zig:799); fixed stale
    line refs (`tstTopologicalSort` :959, `tstEdgesCount` :807, `tstEdgesFill` :857, `tstIsDep`
    :922, sub-pass 2a/2b :1256/:1297, fwd-decls :1233-1255, Q1 refs).
  - `07_lir_lowering.md` — F2: lowerer skips `assign_field` for `undefined` array-typed fields
    (oracle parity); F3: cross-module `pub const` literal fold at the ref site.
  - `05_semantic_analysis.md` — F4: switch MIX branch `continue` (resolves remaining prongs
    instead of aborting; `call_arg_types` populated for later prongs); fixed stale :1018-1129
    function range → :1046-1179 and the abort-behavior doc.
  - `02_symbol_registration.md` — F3: `pub const` literal-init has no storage slot (bit0=mutable);
    cross-module refs fold literals at the ref site.
  - `03_type_resolution.md` — NOT updated (F1/F3 touch c89_emit/lower, not the type-resolution
    path; verified by `git show --stat`).
- **Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `sf/docs/tech_docs/`
  (08, 07, 05, 02, INDEX.md), `examples/z98/rogue_mud/NOTES.md`. Commit
  `docs: gate sweep + tech docs for rogue_mud emission defects plan`.

---

## char_literal switch-case repro battery (Battery A, 2026-08-07) — 12 repros, ALL OK (F1-fixed, runtime-gap cleared)

Repros from the repro battery plan (`95b3c828` spec, `f0077d50` plan; commits `0dc4f594`,
`1e592430`, `c2864086`). They probe the **char_literal switch `case`-label drop**: both
switch-case-collection loops in `lower.zig` handle `int_literal`/`enum_literal`/`error_literal`
case nodes then `else { continue; }`, so a `char_literal` (kind 13) case node is silently dropped
from the case table — the emitted C `switch (c)` has NO `case` labels, only `default:`, and every
input takes the `else` body.

- **Defect sites (both, FIXED by F1 `e0a4d6d6`):**
  - `sf/src/lower.zig:3170-3184` — **expr-switch** case collection, `else { continue; }` at
    `:3183`. **F1** adds an `AstKind.char_literal` branch reading `store.int_values` (like
    `int_literal` does) — actual expr-site fix at lower.zig:3202.
  - `sf/src/lower.zig:3907-3921` — **stmt-switch** case collection, `else { continue; }` at
    `:3920`. **F1** adds the same `char_literal` branch — actual stmt-site fix at lower.zig:3941.
- **Fix (F1, commit `e0a4d6d6`, 2026-08-07):** both switch-case-collection loops gained an
  `AstKind.char_literal` branch (mirroring `int_literal`: value from `store.int_values`), so char
  cases emit real `case 'a':` labels. All 12 repros flip to their expected post-fix output
  (verified by run below).

**Classification under the corpus gate (POST-FIX):** every repro dumps rc=0, is gcc-clean
(per-file `gcc -c` rc=0), links, and runs rc=0 — gcc-exit classifier reports **OK**. **F1 makes
them fully OK at runtime too** — the char cases are no longer dead; each repro prints its expected
post-fix output. **No longer runtime-gap-tracked** (pre-fix they compiled clean but miscompiled at
runtime; the F1 fix resolved the runtime gap).

**Measured POST-FIX (sf/build/out_release/zig1, F4 gate sweep 2026-08-07):** all 12 dump rc=0,
gcc rc=0, run rc=0, output matches the expected post-fix column:

| Repro | defect site | pre-fix run output | **post-fix run output** |
|-------|-------------|--------------------|--------------------------|
| `switch_char_single` | stmt `:3920` (→ fixed :3941) | `000` | **`120`** |
| `switch_char_multi` | stmt `:3920` (→ fixed :3941) | `0000` | **`1120`** |
| `switch_char_nodefault` | stmt `:3920` (→ fixed :3941) | `99` | **`19`** |
| `switch_char_mixed_kinds` | stmt `:3920` (→ fixed :3941) | `020` | **`120`** (INT case 98 + char case both fire now) |
| `switch_char_expr` | expr `:3183` (→ fixed :3202) | `000` | **`120`** |
| `switch_char_while` | stmt `:3920` (→ fixed :3941) | `0` | **`1`** |
| `switch_char_labeled` | stmt `:3920` (→ fixed :3941) | `0` | **`1`** |
| `switch_char_nested` | stmt `:3920` (→ fixed :3941) | `999` | **`109`** |
| `switch_char_xmod` | stmt `:3920` (→ fixed :3941) (cross-module) | `000` | **`120`** |
| `switch_char_xmod_expr` | expr `:3183` (→ fixed :3202) (cross-module) | `000` | **`120`** |
| `switch_char_xmod_while` | stmt `:3920` (→ fixed :3941) (cross-module, in loop) | `0` | **`1`** |
| `switch_char_xmod_nodefault` | stmt `:3920` (→ fixed :3941) (cross-module, no else) | `99` | **`19`** |

Each dir's `NOTES.md` documents the defect, oracle (zig0) verification, measured pre-fix output,
and expected post-fix output (F3 7a732cb3 updated the classifications to "FIXED post-F1").
`switch_char_mixed_kinds` is the key discriminator — its INT case prong (`98`) fired while the char
prong (`'a'`) was dropped, proving the bug was char-specific, not a general switch miscompile; now
both prongs fire.

**Accounting:** 12 repros, all **fully OK** (F1-fixed). FAIL=3 and green-guards=4 **UNCHANGED**.

---

## opt_slice null-payload repro battery (Battery B, 2026-08-07) — 3 repros, ALL OK / FIXED by F2 (Option B)

Repros from the same repro battery plan (commit `965a830b`). They probe the **opt_slice
null-payload temp typing**: `catch return null` (and `return null`) in a function returning an
OPTIONAL SLICE (`?[]T`) emitted the null payload as a scalar `int` temp assigned `NULL`
(`int zT_3; zT_3 = NULL; zT_4.has_value = 0;`) even though the optional struct's payload field is
really a slice `typedef struct { zT_..._Slice... value; int has_value; } Opt;`. For an optional
POINTER (`?*T`) the payload IS a pointer and `int`/`NULL` is acceptable; for an optional slice the
temp type was wrong.

- **Defect (pre-fix):** the null-construction path picked a scalar `int` temp for the payload
  regardless of the payload's real type (the optional's payload type was not threaded onto the null
  temp). Latent, not a gate failure: the emitted C compiled (gcc rc=0, `-Wint-conversion` warning
  only) and the payload is never READ when `has_value=0`.
- **Fix (F2, commit `5c515a7d`, 2026-08-07, Option B):** the `null_literal` branch in
  `lowerExprImpl` (lower.zig:1183-1214) now consults the coercion table: when the coercion routes
  to `wrap_optional_null` / `wrap_optional` / `wrap_error_success` AND the target chain contains an
  optional layer, it emits `set_optional_null` directly on a temp typed as that optional layer —
  the dead `int zT_N; zT_N = NULL;` store (typed `null_type` → `int`, gcc `-Wint-conversion`) is
  gone. No payload temp is emitted at all; `materializeInto` short-circuits on `src_ty == expected`
  (lower.zig:911) or wraps the `?T` temp into outer EU layers (lower.zig:945). Emitted C is now
  `Opt_... zT; zT.has_value = 0;`. Warning count on the payload temp: 2/2/3 → **0/0/0**; `grep
  '= NULL;'` on emitted C: **0 hits**. All 3 still print `1` (verified by run, F4 sweep).

**Measured POST-FIX (sf/build/out_release/zig1, F4 gate sweep 2026-08-07):** all 3 repros dump
rc=0, gcc-clean (**0 `-Wint-conversion`**, 0 `= NULL;`), link, run rc=0 printing `1`:

| Repro | path | post-fix emitted-C symptom |
|-------|------|--------------------|
| `opt_slice_null` (B1) | same-module `?[]Point` | `Opt_... zT; zT.has_value = 0;` (no `int zT_3;` payload temp, no `= NULL;`) |
| `opt_slice_null_xmod` (B2) | cross-module `?[]Path` (lib.zig) | same post-fix shape in `lib_*.c` |
| `opt_slice_null_multi` (B3) | 3 null sites (2× `catch return null` + final `return null`) | `Opt_... zT; zT.has_value = 0;` at each site (no `int zT_6; = NULL;`) |

`opt_slice_null_return` (from the rogue_mud F5 I-task, 2026-08-07) is a DIFFERENT latent issue
(it emits an `undefined_const` for a slice return, not the null-payload `int` temp — unaffected by
F2's null_literal change) and remains **OK-by-gate, tracked separately** (see the F5 section).
Each dir's `NOTES.md` documents the pre-fix gap and the post-fix analysis.

**Accounting:** 3 repros, all **OK / FIXED by F2**. FAIL=3 and green-guards=4 **UNCHANGED**.

---

## F1/F2 fix records — char_literal switch + opt_slice null (2026-08-07)

The 15 battery repros above (12 Battery A + 3 Battery B) gate the two post-plan fixes; both are
now landed and the battery annotations are cleared:

| Fix | Commit | What changed | Battery impact |
|-----|--------|--------------|----------------|
| F1 — char_literal switch `case` labels | `e0a4d6d6` | Both switch-case-collection loops (`lower.zig` expr-switch site ~:3202, stmt-switch site ~:3941) gained an `AstKind.char_literal` branch (value from `store.int_values`, mirroring `int_literal`) — char cases now emit real `case 'a':` labels instead of being dropped (`else { continue; }`). | 12 Battery A repros **runtime-gap cleared** — all print expected post-fix output (`120`, `1120`, `19`, `1`, `109`, …). Fully OK. |
| F2 — opt_slice null-payload temp | `5c515a7d` | `null_literal` branch (lower.zig:1183-1214, Option B) consults the coercion table; null_src coercions with an optional layer emit `set_optional_null` directly on an `Opt_`-typed temp — the dead `int zT_N; zT_N = NULL;` payload temp (gcc `-Wint-conversion`) is gone. | 3 Battery B repros **latent cleared** — 0 `-Wint-conversion` warnings (was 2/2/3), 0 `= NULL;` sites, all still print `1`. Fully OK. |

**Gate sweep (F4, 2026-08-07, `sf/build/out_release/zig1` at HEAD):** full corpus 231 dirs
classify **OK=224 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (224 OK dirs = 223 effective
manifest OK + `opt_slice_null_return` tracked separately; raw classifier FAIL = 7 = 4 green-guards
sub-bucket + 3 real FAILs). FAIL=3 and green-guards=4 UNCHANGED. 4 MD5 gates: gol byte-identical;
mud/lisp/json re-baselined by F2 (full hashes in QUICK_REF). test_analyzer_bin PASS.

---

## F2 — D2 deferred to std-lib + `extern_runtime_symbol_xmod` repro (2026-08-08, docs + repro only)

Per the I2 report (`.superpowers/sdd/I-orphan-module-report.md`) and the operator ruling,
the D2 "json_parser orphan module" investigation found **NO compiler defect**: `arena.zig`
is never `@import`ed (orphan file), all modules emit, and the link failure is
`undefined reference to arena_alloc_default` — an extern (declared
`sf/src/include/zig_runtime.h:21-22`) defined ONLY in the legacy
`src/runtime/zig_runtime.c:31/:154-156`, **absent from `sf/src/include/zig_runtime.c`**.
Class **(b) runtime-library gap**; a documented runtime API
(`docs/reference/runtime_api.md:38-48`). **Deferred to the std-zig1 library — NOT fixed
here** (no `sf/src/*.zig` changes, no runtime-file changes).

**json_parser + json_parser_workaround — officially documented as std-lib-deferred** (their
NOTES.md gained a "Deferred to std-lib" section): both call `arena_alloc_default`; the
standard sf-runtime recipe fails on 5 undefined refs; linking the legacy
`src/runtime/zig_runtime.c` object makes json_parser link+run. `json_parser_workaround`
remains ADDITIONALLY blocked by the I3 6× zT_xx forward-decl COMPILE gap (unaffected by
any runtime fix). These are **example-level link gaps, not corpus repros** — they do not
change the corpus counts.

**New repro `extern_runtime_symbol_xmod` (class-(b) extern-link spec for the std-lib plan):**

| Repro | RED (measured) | Classification (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `extern_runtime_symbol_xmod` | standard-recipe link rc=1: `undefined reference to 'arena_alloc_default'` (lib_*.c) | **OK-by-gate / LATENT, std-lib-deferred** — dump rc=0, all modules emit (lib + main), per-file gcc -c rc=0, standard sf-runtime link rc=1 on the ONE missing extern; legacy-runtime link (`gcc -c src/runtime/zig_runtime.c -o /tmp/rt.o`) rc=0, run rc=0 (prints `0`; arena NULL pre-`arena_create`, value incidental) | `mod_silent_drop_xmod` does NOT cover the extern pattern (all its modules link clean); this repro guards the extern-link gap and is the std-lib plan's spec (flips to PASS when the std-lib runtime provides the symbol) |

**zig0 oracle verification:** dump rc=0, emits lib.c/main.c (same module set). Honest
nuance vs the brief's "SAME link failure": zig0 re-emits the extern as `extern unsigned
char* arena_alloc_default(unsigned int n);` (from the `[*]u8` return), which CONFLICTS
with `zig_runtime.h:21` `void*` → the oracle's standard-recipe output fails at **compile**
(conflicting types), whereas zig1 (header-decl-only, no re-emitted extern) fails at
**link**. Both confirm the same runtime gap. zig0 also emits
`__bootstrap_i32_from_bool(...)` for `@intCast(i32, bool)` — a checked-cast helper in NO
runtime (legacy zig0 emission; zig1 post-F1 emits a raw `(int)` cast for the widening).

**Source corrections vs the brief's verbatim blocks (both documented in the repro
NOTES.md):** (1) the in-body `extern fn __bootstrap_print_int` was moved to module scope —
BOTH zig1 (`error[3020]`) and the zig0 oracle (syntax error) reject in-function `extern fn`
decls (pre-existing Z98 subset limitation, not a zig1 defect; corpus pattern is top-level);
(2) the `@ptrToInt(p) == @intCast(usize, 0)` line **works post-F1** as predicted
(`@ptrToInt` → `usize` for single-arg calls, commit `51bfdb3c`) — no error.

**Accounting:** **UNCHANGED — OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230
manifest repros** (raw classifier FAIL stays 7). `extern_runtime_symbol_xmod` is tracked
separately as OK-by-gate/latent (mirrors the `opt_slice_null_return` precedent), NOT added
to FAIL; the two examples are example-level link gaps, not corpus repros. No repro
flipped; no compiler changes; 4 MD5 gates untouched (compiler unchanged). test_analyzer_bin
PASS. Full evidence: `.superpowers/sdd/task-F2-rogue-report.md`.

## F4 — D4 plat-stub gap deferred to std-lib (2026-08-08, docs only)

Per the I4 report (`.superpowers/sdd/I-platstub-gap-report.md`) and the operator ruling,
the D4 "platform-stub gap" investigation found **NO compiler defect**: 12 `plat_*` symbols
exist in `sf/src/include/net_runtime.c` (all socket-family), but the **5
console/platform-detect stubs** requested by `rogue_mud`
(`examples/z98/rogue_mud/ui.zig:11-15`) are **MISSING from ALL runtime files**
(`zig_runtime.c` / `zig_pal.c` / `net_runtime.c`): `plat_is_windows`,
`plat_console_gotoxy`, `plat_console_setcolor`, `plat_console_putchar`,
`plat_console_clear`. Class **(b) runtime-library gap**; `sf/build/zig0` fails
IDENTICALLY (same undefined-reference link rc=1) → NOT a compiler bug. **Deferred to the
std-zig1 library — NOT fixed here** (no compiler changes, no runtime-file changes).

`plat_stubs_missing_xmod` is the existing guard repro (dump rc=0, all modules emit, gcc
`-c` rc=0, link rc=1 on the missing stubs):

| Repro | RED (measured) | Classification (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `plat_stubs_missing_xmod` | link rc=1: `undefined reference to plat_is_windows` / `plat_console_putchar` (console_*.c) | **OK-by-gate / LATENT, std-lib-deferred** — dump rc=0, all modules emit, per-file gcc -c rc=0, standard-recipe link rc=1 on the missing console/platform-detect stubs (all 5 rogue_mud-only) | guards the rogue_mud link gap; flips to PASS when the std-lib runtime adds the 5 stubs (a console/platform-detect layer, e.g. `console_runtime.c` mirroring `net_runtime.c`) |

**Accounting:** **UNCHANGED — OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230
manifest repros** (raw classifier FAIL stays 7). `plat_stubs_missing_xmod` is tracked
separately as OK-by-gate/latent (mirrors the `opt_slice_null_return` /
`extern_runtime_symbol_xmod` precedents), NOT added to FAIL. `rogue_mud` (20 modules) is
BROKEN at link ONLY on these 5 stubs (both single- and multi-module recipes: all modules
emit, gcc compile rc=0). No repro flipped; no compiler changes; 4 MD5 gates untouched.
Full evidence: `.superpowers/sdd/task-F4-rogue-report.md`.

