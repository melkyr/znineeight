# Z98 Compiler Quick Reference

## ⭐ SUBAGENT CHEAT-SHEET — READ THIS SECTION BEFORE ANY BUILD/COMPILE/RUN ⭐

**Every subagent doing build/compile/run/gate work MUST read this section first.** These are the
exact, verified commands. Do not improvise flags or rediscover linking — copy these.

### Build zig1 (the compiler under test)
```bash
cd /workspace/znineeight
bash sf/scripts/build_release.sh
```
- **GATE ON THIS LINE ONLY:** `=== [release] Done: sf/build/out_release/zig1 ===`.
- The script now exits **0** cleanly. (The old `zig1-dump` step — which built `sf/src/main_dump.zig`
  and FAILED on a pre-existing `main_dump.zig`/`source_manager.zig` break, making the script exit
  nonzero and look broken — is commented out with marker `main-dump failing`. Do NOT re-enable it;
  do NOT try to "fix" that dump build. It is out of scope and expected-broken.)
- Resulting binary: **`sf/build/out_release/zig1`**. Oracle reference compiler: **`sf/build/zig0`**
  (git-ignored; already built).
- `-Wall` gcc **warnings** may scroll past during the build — they are harmless. Only a nonzero exit
  or a missing `[release] Done` line means a real failure.

### Compile + RUN a program (repro or example) with zig1  — VERIFIED RECIPE
```bash
sf/build/out_release/zig1 --dump-c89 <FILE.zig> > /tmp/x.c 2>/tmp/x.err ; echo "dump rc=$?"
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x ; echo "gcc rc=$?"
/tmp/x ; echo "run rc=$?"
```
- You **must** link `sf/src/include/zig_runtime.c` AND `sf/src/include/zig_pal.c`, and pass
  `-I sf/src/include`. Missing any of these is the #1 cause of wasted turns.
- For **mud_server** also add `sf/src/include/net_runtime.c` to the gcc line.
- For a **no-`main` repro** (compile-only, no link/run) use `gcc -m32 -std=c89 -c ... -o /dev/null`.
- A compiler ICE shows as `dump rc=134` (SIGABRT) with a `PANIC:` line — note the panic text may land
  on **stdout** (`/tmp/x.c`), not stderr.

### Corpus gate (207 repros in `repro/mi_matrix/*/`)  — classify by gcc EXIT CODE  [updated: 2026-08-06]
For each `repro/mi_matrix/*/main.zig`: run `zig1 --dump-c89 --output-dir DIR`, then compile
every emitted per-module `.c` file:
```bash
for f in DIR/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c "$f" -o /dev/null || exit 1; done
```
- **Classify by gcc EXIT CODE, never by empty-stderr** (warnings are nonzero-length but rc=0; a
  stderr-emptiness classifier gives false counts like 68/63).
- `dump` rc≥128 = CRASH; stderr matching `error\[(48|3042|9001|3043)\]|AddressSanitizer` = ICE; gcc rc==0 = OK; else FAIL.
  (Note: `error[3048]` is deliberately NOT in the ICE regex — the F-S10 file diagnostics must
  classify as ordinary FAIL, not ICE.)
- **A repro that fails the frontend (dump emits 0 `.c` files with a `error[NNNN]` diagnostic) is a
  FAILURE — a real compiler gap — NOT "OK".** Do NOT count an empty output dir as OK. The per-file
  gcc loop above is only the emission check; a frontend error must be checked separately:
  ```bash
  if [ -z "$(ls DIR/*.c 2>/dev/null)" ]; then result=FAIL; fi   # 0 .c emitted = frontend gap
  ```
- **Green-guards are a distinct bucket**: a valid program CORRECTLY rejected by the frontend with the
  documented `error[3000]` diagnostic and 0 `.c` emitted is a green-guard (correct rejection matching
  the zig0 oracle), counted SEPARATELY from FAIL; a green-guard moving to OK/FAIL is a regression.
  (See EXPECTED_FAIL.md "Green-guards" section.)
- **Baseline (2026-08-04, after F-1..F-9, measured with /tmp/zb/zig1): `OK=184 FAIL=8 ICE=0 CRASH=0` over 192 repros.**
- **Post-Plan-1 baseline (2026-08-04, 5 new repros): `OK=188 FAIL=9 ICE=0 CRASH=0` over 197 repros.**
- **Post-Plan-2 baseline (2026-08-04, emission-defect fixes): raw `OK=189 FAIL=8 ICE=0 CRASH=0` over 197 repros; 2 green-guards (`var_declared_void`, `euvoid_val_catch`) counted separately → effective `OK=189 / FAIL=6 / green-guards=2`.**
- **Post-P3-1 baseline (2026-08-05, reclassify 2 correct rejections): raw `OK=189 FAIL=8 ICE=0 CRASH=0` over 197 repros stays 8; 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`) counted separately → effective `OK=189 / FAIL=4 / green-guards=4` (189+4+4=197).**
  - 184 fully OK (frontend + emission + gcc all clean).
  - **8 raw FAIL** (non-ICE) = 5 frontend gaps + 2 emission defects + 1 residual, of which 2 emission
    defects are now FIXED (P2-2/P2-4), `var_declared_void` reclassified green-guard (P2-3), and
    `eu_assign_incompat_payload`/`field_access_optional` reclassified green-guards (P3-1) →
    post-P3-1 breakdown: **4 FAIL = 3 frontend gaps + 1 residual**; the 3 former emission defects all
    resolved; 4 green-guards counted separately.
  - **0 ICE** — the F-1..F-8 fixes eliminated the `error[3043]` ("internal: unsupported field-store
    base") ICEs (all 6 pre-fix ICEs moved to OK; `OK 184 + FAIL 8 + ICE 0 = 192`).
  - Must stay `189/8/0/0` (raw) / effective `189/4/4` or improve. A repro moving into OK is a fix; a repro moving into FAIL/ICE is a regression; a green-guard moving to OK/FAIL is a regression.
- **Emission defects — ALL FIXED (Plan 2, 2026-08-04)** [updated: 2026-08-04]:
  - `array_tagged_union_read`: comptime-fold intcast target typing, lower.zig.
  - `var_declared_void`: sema `error[3000]` rejection + `euvoid_val_catch` — both green-guards
    (correct rejections, counted separately).
  - `ptroint_arena_offset`: ptr±literal resolution + scoped `written_type` override.
  - NOTE: `module_as_value`, `opteu_err_if_expr`, `opteu_err_switch` were FAIL in the F-1..F-8
    baseline (undeclared `zT_0` temp / incompatible int→`Opt_` assign) but are now OK — **fixed F-9
    2026-08-04** (Option B optional-of-EU unwrap + module `TEMP_NONE`) and restored to OK. See
    EXPECTED_FAIL.md.
- **The 3 frontend-gap repros** (`dump_rc=2|3`, 0 `.c` emitted):
  - error[3048] cannot-read/cannot-resolve file: `field_store_drop` (`const pal = @import("pal")` →
    `error[3048]: could not resolve imported file 'pal'` — pre-existing import-resolver gap; a user
    program cannot import compiler-internal modules. Will pass when zig1 gains a real std lib),
    `test_stub_0` (imports nonexistent `"std"` — FAIL via `error[3048]` today; will pass when zig1
    gains a real std lib — planned).
  - error[2000] parse: `catch_block_value_producing` — **FIXED (P3-4 + P3-7, 2026-08-05): FAIL→OK**.
    Value-block catch (P3-4, commit a50e2910) + inline error-set types in type positions (P3-7);
    see EXPECTED_FAIL.md P3-4/P3-7 section.
  - The 2 former error[3000] frontend-gap repros — `eu_assign_incompat_payload`,
    `field_access_optional` — are **correct rejections (green-guards, P3-1)**, not gaps; counted
    separately from FAIL (see the green-guard classifier note above / EXPECTED_FAIL.md "Green-guards"
    section).
  - **std-lib-deferred (P3-2, 2026-08-05):** `field_store_drop` and `test_stub_0` are classified FAIL
    but tracked as **std-lib-deferred, not compiler defects** — both fail `error[3048]` (a user
    program cannot import compiler-internal modules / nonexistent std). **Will pass when zig1 gains a
    real std lib.** Deferral changes no counts: effective `OK=189 / FAIL=4 / green-guards=4`
    (189+4+4=197; raw FAIL stays 8) — the 4 FAILs = these 2 std-lib-deferred + `catch_block_value_producing`
    + `self_embed_optional_cycle`.
- **P3-3 closeout (2026-08-05, docs-only):** `anon_errset_comparison` reclassified **OK (semantically
  verified)** — the bare-`!` `err == error.Bad` comparison is CORRECT. An anonymous error literal
  stores the raw **name_id** as its C error code, and name_id is a unique-per-name, program-stable
  interner code (string_interner.zig:88-122 dedups by content; one interner per program): same name
  ⟹ same code, distinct names can never collide. Measured RED==GREEN==1 on zig1 and the zig0 oracle.
  Counts unchanged (already OK since Plan 1 P1-1; effective `OK=189 / FAIL=4 / green-guards=4`
  stays). **2 adjacent defects tracked as follow-ups, NOT fixed:** P3-5 (switch-on-error:
  `lower.zig:2919-2934` drops `error_literal` case nodes → empty switch always takes `default`) and
  I3-5/P3-6 (error-code representation unification: anon name_id vs named ordinal miscompare in
  oracle-accepted cross-set programs). See EXPECTED_FAIL.md P3-3 section + `.superpowers/sdd/P3-anonerr-report.md`.
- **P3-7 closeout (2026-08-05, inline error-set types in type positions):** `catch_block_value_producing`
  is now OK — `helper.zig` `pub fn try_compute() error{Bad}!i32` (an INLINE `error{...}` in a type
  position) works end-to-end. Parser (parser.zig `kw_error` branch) now handles the postfix `!`
  after `error_set_decl`; `resolveTypeExprFull` gained an `error_set_decl` case (registers the
  members via `typeRegistryGetOrCreateErrorSet`); the anonymous error-set type is emitted
  (c89_emit whitelists). Post-P3-7 effective **`OK=190 / FAIL=3 / green-guards=4` over 197**
  (190+3+4=197; raw FAIL 8→7). Remaining 3 FAIL: 2 std-lib-deferred (`field_store_drop`,
  `test_stub_0`) + `self_embed_optional_cycle`. 4 MD5 gates byte-identical.
- **P3-5 closeout (2026-08-05, switch-on-error exhaustiveness):** `lower.zig` switch-case
  collection (expr site + stmt twin) now handles `error_literal` case nodes (mirrors the
  `enum_literal` branch: `enum_value_table` ordinal when present, else raw name_id); companion
  sema fix resolves error_literal case nodes against the switch cond error set so named sets get
  ordinals. New repros `switch_on_error_named` + `switch_on_error_anon` print `1` (was `0`,
  default-branch). Post-P3-5 effective **`OK=192 / FAIL=3 / green-guards=4` over 199**
  (192+3+4=199; corpus grew 197→199 by 2 new OK repros; raw FAIL stays 7). Remaining 3 FAIL:
  2 std-lib-deferred (`field_store_drop`, `test_stub_0`) + `self_embed_optional_cycle`.
  4 MD5 gates byte-identical.
- **P3-6 closeout (2026-08-05, error-code representation unification):** all error codes are now
  dense program-global **per-name** registry codes (`error_code_registry: U32ToU32Map` name_id →
  code on CompilerContext; `getOrAddDense` first-use order) instead of per-set ordinals / raw
  name_id. Prologue emits `#define ERROR_<name> <code>` (zig_special_types.h for multi-module,
  inline for single-stream; skipped when empty). Fixes cross-set `e1 == e2` for real-Zig-legal
  subset→superset coercions (both I3-5 probes → `1`). New repro `errset_cross_set_compare`
  prints `11` (RED `00`). Post-P3-6 effective **`OK=193 / FAIL=3 / green-guards=4` over 200**
  (193+3+4=200; corpus grew 199→200 by 1 new OK repro; raw FAIL stays 7). 4 MD5 gates:
  **mud + gol byte-identical** (`4644ad13…`, `d0d3051d…`); **lisp + json RE-BASELINED** to
  `dd56cd23…` / `900cb401…` (per-name codes replace named-set ordinals; F-5 AMENDMENT B precedent
  — "runtime behavior is the gate, not byte-identity"; both compile, link, run correctly).
  `@enumToInt(err)` prints registry codes (accepted; all ~30 error repros runtime re-verified
  unchanged).
- **Runtime-gap repros now FIXED (F-1..F-8, verified by run):** `comptime_neg_int` prints `-5`
  (was garbage), `module_pub_var_int` prints `43`, `module_pub_var_struct` prints `7`,
  `module_const_fn_call` prints `42`. All classify OK by the compile-only corpus gate AND run
  correctly now; no longer runtime-gap tracked.

- **Comptime arithmetic folding feature (plan `.superpowers/plans/2026-08-06-comptime-arithmetic-folding-plan.md`):** all 12 bare binary/unary const ops
  (`+ - * / % & | ^ << >> ~` and `negate`) now fold to comptime `int_const` at module scope.
  Tasks F1-F8 (commits `7dc119a6`..`bf5d3636`, 2026-08-06): F1/F2 add the bitwise/shift/bit_not
  ops to `comptimeEvalBinOp`; F3 folds `const var_decl` binop/unary **inits** in
  `phase_ComptimeEvaluation` (main.zig:347-360); F4/F5 add `comptime_values` guards to the 10
  binary + 2 unary lowerer handlers (INT_LIT→I32 remap) so folded values emit `int_const`; F6 adds
  `mul`/`div`/`mod_op` to the type_resolver array-size handler (type_resolver.zig:888-896); F7
  types folded u64 consts >2^32 at their declared width (storage-global type no longer clobbered,
  declared type threaded onto the init node); F8 adds a depth-16-guarded `ident_expr` const-chain
  branch to `comptimeEvalEvaluateDepth` (comptime_eval.zig:199-218) so `const B = A + 5` folds from
  `const A`. Guarded by 5 repros (`comptime_binop_not_folded`, `comptime_lower_ignores_fold`,
  `comptime_array_size_gap`, `comptime_u64_fold_overflow`, `comptime_const_chain` — all now OK,
  emission/runtime-gap annotations cleared) + `fn_varargs_unsupported` (FAIL, varargs parse gap,
   out of scope). **Final accounting (F9 gate sweep, 2026-08-06): effective
   `OK=198 / FAIL=4 / green-guards=4` over 206 repros (198+4+4=206; raw classifier FAIL stays 8);
   4 MD5 gates byte-identical; test_analyzer_bin PASS.** [updated: 2026-08-06]
   **Post-F1 (2026-08-06, @intCast range-check): effective `OK=199 / FAIL=4 / green-guards=4`
   over 207 repros (199+4+4=207; raw classifier FAIL stays 8); corpus grows 206→207 by
   `intcast_range_check` (OK, runtime-panic gate); all 4 MD5 gates RE-BASELINED (scope b) — see the
   MD5 re-baseline note; test_analyzer_bin PASS.** [updated: 2026-08-06]

**Known issues exposed by F-1..F-8 (documented 2026-08-04):**
- **Cross-module global field access gap (F-7 review I-1):** FIXED 2026-08-04 (Plan 1 P1-2) — the module
  field-access path (lower.zig:1869-1875) gained a `SymbolKind.global` branch emitting `load_global`,
  and module headers now carry `extern` decls for storage globals (c89_emit.zig:2063-2081). Guard
  repro `xmod_global_field_access` prints `2` (was 1).
- **`field_store_drop` blocked on pal-import (F-5 AMENDMENT C):**
  `repro/mi_matrix/field_store_drop/main.zig` does `const pal = @import("pal")` — fails
  `error[3048]: could not resolve imported file 'pal'` on pristine AND fixed builds. Pre-existing
  import-resolver gap (a user program can't import compiler-internal modules). Not an F-5 defect;
  documented as known issue. Will pass when zig1 gains a real std lib.
- **Array `load_global` copy-loop (F-7 review I-2):** lisp's 1MB buffers emit dead copy temps +
  stack arrays; correct but wasteful — follow-up optimization.
- **MD5 re-baseline note (F-5 AMENDMENT B):** mud+lisp re-baselined because F-5/F-7 emit
  stores/globals that were previously dropped — runtime behavior is the gate, not byte-identity.

- **Historical note:** the earlier `176/8/0/0` figure (plan + F-S5 + prior QUICK_REF) counted the 12
  frontend gaps as OK via the empty-DIR-is-OK convention (IM6 C2 Option-1 per-file loop never runs on
  an empty dir). That convention is DISCONTINUED (2026-08-01, operator): a valid-Z98 repro that fails
  to emit is a failure, not a pass. The 8 emission defects are identical under both conventions;
  the correction only re-buckets the 12 frontend gaps from OK to FAIL (6 of them ICE).
- **F-S7..F-S10 are transparent to the (glob-based) build recipes.** Multi-module filenames are
  now `DIR/<basename>_<FNV1a8>.c/.h` (unique per path), but every NOTES.md/QUICK_REF recipe uses
  globs (`*.c`, `*.h`, `gcc -c *.c`), so no recipe changes were needed. `zig1 --dump-c89
  <missing-or-empty.zig>` now exits **1** with `error: could not read input file` on stderr
  (was silent exit 0 + boilerplate).

**Analyzer detection paths activated (2026-08-03):** null, lifetime, and doublefree
detection now route through `visitStatement` for full control-flow-aware analysis.
Single wrapper function `detectorVisit` (`sf/src/analyzer.zig:759`); per-pass
statement handler stored in `AnalyzerContext.on_stmt_cb` (`sf/src/analyzer.zig:383`).

### Byte-identical gate (mud / gol / lisp / json) — z98-only, self-consistency check

Gate entries (`examples/z98/` paths, NOT `examples/zig0/`):
```bash
sf/build/out_release/zig1 --dump-c89 <ENTRY> > /tmp/new.c
diff /tmp/ref.c /tmp/new.c   # compare against reference (ref.c captured at prior gate baseline)
```

| Entry Path | Reference md5 | [updated: 2026-08-06] |
|---|---|---|
| `examples/z98/mud_server/main.zig` | `50beb1bf5edc4cbb638f84aa027ffade` |
| `examples/z98/game_of_life/main.zig` | `0d8f0092c22c04375482a198691a3957` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `55044a1f64011bc644cddbcf73b5de93` |
| `examples/z98/json_parser/main.zig` | `b5f56ebd51d2f0fcd379a1e083594462` |

- **Re-baselined 2026-08-03 (TCO feature, AMENDMENT 9/11 ruling B).** The old baselines (mud
  `5fb57e70…`, gol `f855c9f9…`, lisp `0ad02040…`, json `11a5db1d…`) are STALE — replaced. Two
  accepted changes cause the new values: (1) **every** emitted function now carries a `z_bb_0:` label
  (AMENDMENT 8 — the `.loop_header` arm emits `z_bb_0:\n`; matches `.jump`'s `goto z_bb_0;`), and (2)
  lisp/json cross-function tails collapse the try-CFG to `zT = f(args); return zT;`. Both are
  semantically correct and gcc-clean; warnings are tolerated, 0 errors required.

- **Re-baselined 2026-08-04 (F-5/F-7, AMENDMENT F-5-B).** mud + lisp re-baselined again because F-5/F-7
  now emit `load_global`/`store_global` stores and module-global init that were previously dropped —
  runtime behavior is the gate, not byte-identity. gol + json unchanged. [updated: 2026-08-04]

- **Re-baselined 2026-08-05 (P3-6, error-code unification).** lisp + json re-baselined again because
  P3-6 replaced named-set per-set ordinals with a program-global per-name error-code registry
  (`#define ERROR_<name> <code>` in `zig_special_types.h` + revalued member defines) — runtime
  behavior is the gate, not byte-identity (F-5 AMENDMENT B precedent). mud + gol byte-identical
  (they emit no error-name codes). New values: lisp `dd56cd23…`, json `900cb401…`. [updated: 2026-08-05]

- **Re-baselined 2026-08-06 (F8, ident_expr const-chain folding).** gol re-baselined because F8's
  `ident_expr` comptime fold now resolves `@intCast(i32, WIDTH)`/`@intCast(i32, HEIGHT)`
  (WIDTH/HEIGHT are `const usize` globals in game_of_life) at comptime — previously emitted as a
  runtime `(int)` load+cast of the storage global, now emitted as a folded `int_const`. Runtime
  output is byte-identical (verified by run diff of pristine vs F8 gol binaries); per the F-5
  AMENDMENT B precedent the gate is runtime behavior, not byte-identity. mud/lisp/json unchanged
  and byte-identical. New gol value: `e2f4c625…`. [updated: 2026-08-06]

- **Re-baselined 2026-08-06 (F1, @intCast range-check — scope b).** ALL 4 re-baselined: mud/gol/
  lisp/json each contain explicit runtime `@intCast` sites that now emit the range-checked
  `__bootstrap_<DST>_from_<SRC>` helper (narrowing + same-width reinterpret) instead of a raw
  `(int)` cast. Runtime-verified identical for mud (rc=124, "MUD server listening on port 4000"),
  gol (glider, 100 generations, rc=0), json (parses test.json, rc=0); lisp is identical except
  `(fact 13)` now PANICS with `integer cast overflow in @intCast` (rc=134) — the intended fix
  (previously silently wrapped to garbage `1932053504`). Per the F-5 AMENDMENT B precedent the gate
  is runtime behavior, not byte-identity. New values: mud `0064a081…`, gol `51d6d078…`, lisp
  `e54be381…`, json `6528f26f…`. Note: the 19 `__bootstrap_*_from_*` helpers are `static` in
  `sf/src/include/zig_runtime.h` (per-TU, oracle pattern) + extern in `sf/src/include/zig_runtime.c`
  — the json multi-module link uses the legacy `src/runtime/zig_runtime.c` object and relies on the
  header `static` copies for `__bootstrap_usize_from_i32`. [updated: 2026-08-06]

- **Re-baselined 2026-08-06 (F5b, mud/gol anytype-print → true `...`).** mud + gol re-baselined
  because `std_debug.zig` `print(fmt, args: anytype)` became `print(fmt, ...)` (true C variadic
  via the F3 flag-bit path; the lower.zig marker-param `child_0==0 → is_variadic` branch is now
  deactivated). Emitted C differs ONLY in the print body's temp numbering (`zT_2`→`zT_1` — the
  anytype marker param is gone, so params_count drops 2→1; the signature `char* fmt, ...` is
  unchanged and now comes from the flag bit). Runtime-verified byte-identical vs pristine: mud
  (rc=124, "MUD server listening on port 4000"), gol (glider, 100 generations, rc=0). lisp + json
  byte-identical (no print migration). Per the F-5 AMENDMENT B precedent the gate is runtime
  behavior, not byte-identity. Pre-F5b values: mud `e306b187…`, gol `51d6d078…`. New values: mud
  `50beb1bf…`, gol `0d8f0092…`; lisp `55044a1f…`, json `b5f56ebd…` unchanged. [updated: 2026-08-06]

- **`examples/zig0/*` entries are oracle-only** — compiled with `zig0` for behavioral comparison, never hashed or gated with zig1 (operator ruling 2026-07-31).
- Self-consistency gate: compare current zig1 `--dump-c89` against a pre-captured reference .c file. If the reference .c is outdated (intentional baseline change), re-capture via `cp /tmp/new.c /tmp/ref.c`. Never compare against parent-zig1 output directly — parent builds may fail silently.
- Do **NOT** compare `zig1 --dump-c89` output against `zig0`'s C output. `zig0` emits a legacy bootstrap format that is byte-level incompatible with zig1.

### TCO gate recipes (examples/z98/tco_*) — [updated: 2026-08-03]

Self-recursion TCO: emitted C must contain a `z_bb_0:` label in the recursive fn + rebind assigns +
`goto z_bb_0;` back-edge (NO retained self `call`). Deep recursion (100k) must run with O(1) stack.

```bash
# tco_factorial (self-recursion, i32)
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_factorial/main.zig > /tmp/tf.c ; echo "dump rc=$?"
grep -n "goto z_bb_0;" /tmp/tf.c            # expect: fact() has rebind assigns + back-edge
grep -c "zF_.*_fact(" /tmp/tf.c             # fwd-decl + def + main call sites only; NO self-call in fact body
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/tf.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/tf ; echo "gcc rc=$?"
/tmp/tf ; echo "run rc=$?"                  # expect: "fact(10) = 3628800" then "deep ok", rc=0

# tco_return_try (self-recursion through E!i32 try)
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_return_try/main.zig > /tmp/tr.c ; echo "dump rc=$?"
grep -n "goto z_bb_0;" /tmp/tr.c             # expect: count() back-edge (try-CFG eliminated)
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/tr.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/tr ; echo "gcc rc=$?"
/tmp/tr ; echo "run rc=$?"                  # expect: "count(10) = 10" then "count(100000) = 100000", rc=0

# tco_defer (self-recursion with defer — defer fires ONCE at terminal return, not per-iteration)
# [updated: 2026-08-03]
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_defer/main.zig > /tmp/td.c ; echo "dump rc=$?"
grep -n "goto z_bb_0;" /tmp/td.c               # expect: back-edge present
# Verify defer body NOT in the self-TCO rebind/jump block (nop'd by lower.zig:3641-3645)
# Verify defer body PRESENT in terminal-return path before the final `return` (emitted at lowerFn:4457)
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/td.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/td ; echo "gcc rc=$?"
/tmp/td ; echo "run rc=$?"                     # expect: defer fires exactly once at end, rc=0
```

Gate: dump rc=0, gcc rc=0, run rc=0, `goto z_bb_0;` present, no self-call retained in the emitted
recursive fn. A compiler ICE shows as `dump rc=134` with a `PANIC:` line (may land on stdout).
`gcc -Wunused-label` warnings for `z_bb_0:` are expected and harmless.

**Consumer-guard note:** `hasOtherConsumers` (`lower.zig:4265`) scans all blocks before
`zeroCallCFG` to ensure no secondary consumers of the call result exist. Defensive — not
triggerable by current Z98 patterns. [updated: 2026-08-03]

### z_bb_0: labels in every function — [updated: 2026-08-03]

Since the TCO feature (F-S2/F-S3), **every** emitted function body contains a `z_bb_0:` label
(AMENDMENT 8). It is the entry-block label emitted by the `.loop_header` LirInst arm
(`c89_emit.zig:2775`), and it is the target of self-TCO `goto z_bb_0;` back-edges. It is EXPECTED:
- For self-recursive fns it is the live TCO jump target.
- For all other fns it is an unused label → `gcc -Wunused-label` warning (tolerated; the md5-gate
  baselines already include the label).

Do NOT treat `z_bb_0:` or the unused-label warning as a regression.

### Multi-Module Build

```bash
mkdir -p DIR
zig1 --dump-c89 --output-dir DIR <entry>
# produces: DIR/*.c + DIR/*.h + DIR/zig_special_types.h

cd DIR
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
```
- `-I /workspace/znineeight/sf/src/include` is REQUIRED — zig1 does not copy `zig_compat.h`/`zig_runtime.h` into DIR (zig0 does; zig1 does not). Use the absolute repo path: the recipe `cd`s into DIR, so relative `sf/...` paths would break.
- Run `gcc -c` INSIDE DIR — `gcc -c DIR/*.c` from outside writes the `.o` files to the caller's CWD, so the `*.o` link glob fails (`cannot find DIR/*.o`).
- For **mud_server** add `/workspace/znineeight/sf/src/include/net_runtime.c` to the link step.
- For **json_parser** use the legacy `src/runtime/zig_runtime.c` object (compiled with `-c`) per its NOTES.md.

### Editing source
Use `edit` (exact strings) or `fastedit` (line ranges, see AGENTS.md §X.7 — re-read the region
immediately before each edit; edit bottom-to-top). No `sed`/python/bulk transforms.

---


### Canonical Examples vs Oracle Examples

- **Canonical examples** under `examples/z98/` — use `@cInclude` + `extern fn` (valid Z98 syntax).
- **Oracle examples** under `examples/zig0/` — use zig0-compatible syntax. Only for oracle comparison against `zig0` output, not as working-example reference.
- The gcc compile recipe includes `-I sf/src/include` which auto-declares bootstrap functions (`__bootstrap_print` etc.) from `zig_runtime.h`.


## Bootstrap Build (zig0 → zig1)


```bash
cd /workspace/znineeight
rm -rf out_release && mkdir -p out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
```

Debug build:
```bash
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
```

## LISP refactor testing building zig1 pipeline

How the LISP / sema-refactor work actually builds and tests `zig1` (differential vs `zig0`).
`zig1` is fully determined by **`sf/src/main.zig` (+ its imports)** and **`sf/build/zig0`** — the
output directory and gcc *warning* flags do NOT change the resulting compiler.

**1. Build zig1 from the current source (isolated output dir):**
```bash
OUT=/tmp/z1
rm -rf "$OUT" && mkdir -p "$OUT"          # always clean: stale .c/.h cause false Slice_* type errors
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig   # emits 35 per-module .c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
```
Debug build (for GDB): append `-g -O0 -Wno-implicit-function-declaration` to the gcc line.

- zig0 emits **35 per-module `.c` files** into `$OUT` (gcc globs `"$OUT"/*.c`; there is no single `zig1.c` object).
- The bootstrap `-Iinclude` above is **stale** (no root `include/` dir exists) — omit it. `-Wno-pointer-sign`
  only mutes warnings. Gate on the `error:` count, never warnings.
- Always build from the **repo** `sf/src/main.zig`, never a `/tmp` `git worktree` (those hold older source = a different/older zig1).

**2. Compile + run an example with that zig1:**
```bash
"$OUT/zig1" --dump-c89 examples/zig0/lisp_interpreter_curr/main.zig > /tmp/lisp.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Isf/src/include \
    /tmp/lisp.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/lisp 2>&1 | grep -c 'error:'
# add sf/src/include/net_runtime.c for mud_server; use `gcc -c` (no link) for no-main repros
```

**3. Differential / gate (what "passing" means):**
- `zig0` is the reference oracle: `./sf/build/zig0 -o DIR/out.c repro.zig` (emits per-module `repro.c` in `DIR`).
- Refactor gate: `man/gol/mud/lisp --dump-c89` **byte-identical** to baselines + `lisp` `error:` count == `12` + self-host gcc `0` errors.
- Current baselines (HEAD `c3d61919`): `man c379bd194d73d06a9dbac02431a82b2d`, `gol 8aa260ce9d467995f657e46552712fb1`,
  `mud 35051e34cd0ba883a08ff60569ae262f`, `lisp 74a721caef6f121fe6d744870dbb7c37`; `zig1` ≈ `621772` bytes.
- Markers: `"$OUT/zig1" --markers --dump-c89 <entry> 2>mk` then `grep -ac '^PREFIX' mk`
  (watch prefix collisions: `FS:C`/`FS:CK`, `IFST:K`/`IFST:K2` → use the `:N` variant).

## Compile Examples with zig1

```bash
./out_release/zig1 --dump-c89 examples/zig0/mandelbrot/mandelbrot.zig > out.c
./out_release/zig1 --dump-c89 examples/zig0/game_of_life/main_lin.zig > out.c
./out_release/zig1 --dump-c89 examples/zig0/mud_server/main.zig > out.c
```

With markers (diagnostic output to stderr):
```bash
./out_release/zig1 --markers --dump-c89 examples/zig0/mud_server/main.zig > out.c 2>diag.txt
```

## Compile Z98 Examples (@cInclude)

```bash
./out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig > out.c
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include out.c \
    sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o app
```

## GCC Compile + Link

```bash
gcc -m32 -std=c89 -Wno-pointer-sign \
  -Iout_release -Isf/src/include \
  out.c \
  sf/src/include/zig_runtime.c \
  sf/src/include/zig_pal.c \
  -o app
```

## Build mud_server (full cycle)

```bash
cd /workspace/znineeight
rm -rf out_release && mkdir -p out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
./out_release/zig1 --dump-c89 examples/zig0/mud_server/main.zig > /tmp/mud.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  /tmp/mud.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c \
  sf/src/include/net_runtime.c -o /tmp/mud
```

Check error count:
```bash
gcc ... 2>&1 | grep -c "error:"
```

## Build and Run Tests

```bash
cd /workspace/znineeight && ./sf/scripts/build_test.sh
```

Note: `build_test.sh` links `sf/src/include/zig_pal.c` into each test binary (required since
`pal.zig` gained the `pal_file_*` file-I/O externs; without it every test binary fails to link).


## Debug with GDB on zig1

### Build with debug symbols
```bash
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
```

### Find function in generated C
```bash
grep -n "function_name_part" out_release/semantic_analyzer.c | head -5
```

### Find line for breakpoint
```bash
grep -n "keyword" out_release/semantic_analyzer.c | head -20
```

### GDB with batch script
```bash
cat > /tmp/gdb.txt <<'EOF'
set pagination off
break out_release/semantic_analyzer.c:LINENO
run examples/zig0/mud_server/main.zig > /dev/null 2> /dev/null
print varname
print another_var
continue
quit
EOF
gdb -batch -x /tmp/gdb.txt --args ./out_release/zig1 --dump-c89
```

### Filter output to variable values
```bash
gdb -batch ... 2>&1 | grep "^\$"
```

### Common breakpoints in resolveSwitchExpr (line numbers may shift after edits)
| Purpose | Approx C Line | Look for |
|---------|---------------|----------|
| Function entry | search for `static unsigned int zF_...manticAnalyzerResolveSwitchExpr` | Declaration line + 14 = unified init |
| Loop start | search for `__loop_0_start` in function body | `if (!(i < prongs.len))` |
| `unified = bt` (i==0) | ~2225 | `un_box[0] = bt;` or `unified = bt;` |
| `bt == unified` check | ~2227 | `bt == un_box[0]` or `bt == unified` |
| TYPE_VOID return | ~2267 | `return zC_..._TYPE_VOID;` |
| Loop exit | ~2275 | `__loop_0_end:` label |

### Verify zig0 C89 variable corruption theory
Replace suspect scalar variable with `[1]u32` box array. If behavior unchanged → corruption theory disproven. Example:
```zig
// Before: var unified: u32 = 0;
// After:  var un_box: [1]u32 = [1]u32{0};   // use un_box[0] everywhere
```

### itoa-based diagnostic markers — use palMarkerWriteInt
```zig
// BEFORE (15+ local vars, zig0 C89 budget risk):
var m: []const u8 = "LABEL:n"; pal_mod.markerWrite(m);
var nb: [10]u8 = undefined; var nl = itoa_mod.itoa(val, nb[0..]);
var ns: usize = @intCast(usize, 9) - @intCast(usize, nl);
pal_mod.markerWrite(nb[ns..@intCast(usize, 9)]);
var e: []const u8 = "\n"; pal_mod.markerWrite(e);

// AFTER (2 local vars, safe everywhere):
// IMPORTANT: zig0 C89 cannot pass string literal directly as []const u8 argument.
// Always use named var before markerWriteInt call.
var m: []const u8 = "LABEL:n"; pal_mod.markerWriteInt(m, val);
```
palMarkerWriteInt defined at pal.zig:99-106. Uses internal 12-byte buf + itoa_mod.itoa.
Output: `LABEL:n<value>\n`.

### Marker extraction — use `grep -a`, NOT `strings`

**CRITICAL:** `strings` strips null bytes and can silently drop entries.
Always use `grep -a` (binary-as-text) on the raw stderr file.

```bash
# Capture markers to file
./out_release/zig1 --markers --dump-c89 examples/zig0/mud_server/main.zig > out.c 2>/tmp/markers.bin

# Extract specific markers
grep -a "^PREFIX:" /tmp/markers.bin

# Count entries (reliable)
grep -a -c "^PREFIX:" /tmp/markers.bin

# Sort unique numeric values
grep -a "^PREFIX:" /tmp/markers.bin | sed 's/PREFIX: *//' | sort -n

# Multi-prefix extraction preserving order
grep -a "^IFST:\|^PBD:\|^EBLK:" /tmp/markers.bin
```

### Common marker labels in sema.zig (all use markerWriteInt)

| Marker | Meaning | Example |
|--------|---------|---------|
| STX:N | resolveExpr entry (node_idx) | STX:N   453 |
| STX:K | resolveExpr entry (kind) | STX:K    24 |
| STX:R | resolveExpr entry (result type) | STX:R    10 |
| A4:N/K/R | STB stored (non-VOID result) | A4:N   453 |
| STB:N/R | STB confirmation | STB:N   453 |
| BLK:N | resolveStmtDepth block handler entry | BLK:N   727 |
| BLK:C | Block child count | BLK:C    11 |
| BCK:B | Block child — block node_idx | BCK:B   727 |
| BCK:I | Block child — index | BCK:I     0 |
| BCK:N | Block child — child node_idx | BCK:N   345 |
| BCK:K | Block child — child kind | BCK:K    30 |
| EBLK:N | resolveExpr block handler entry | EBLK:N  753 |
| IFST:N | if_stmt handler — if_stmt node | IFST:N  427 |
| IFST:C | if_stmt handler — child_1 node | IFST:C  426 |
| IFST:K | if_stmt handler — child_1 kind | IFST:K   79 |
| IFST:2 | if_stmt handler — child_2 node | IFST:2    0 |
| IFST:K2 | if_stmt handler — child_2 kind | IFST:K2   0 |
| WST:N | while_stmt handler — node_idx | WST:N   726 |
| WST:K | while_stmt handler — body kind | WST:K    76 |
| WST:D | while_stmt handler — depth | WST:D     3 |
| PBD:N | resolveSwitchExpr prong body node | PBD:N   753 |
| PBD:K | resolveSwitchExpr prong body kind | PBD:K    76 |

## DISPROVEN zig0 C89 Bugs

Theories that were investigated and ruled out. Do NOT re-investigate.

| Theory | Disproof | Date |
|--------|----------|------|
| **C89 variable budget / stack slot reuse** — local variables corrupted at depth 3+ | Markers with wrong slice offset (`buf[0..vlen]`) produced garbled output, not codegen corruption. After fixing `palMarkerWriteInt`, all markers reliable at ALL depths. Verified with `[1]u32` box array test. | 2026-06-12 |
| **Struct-by-value return corruption** — `Slice_u32` returned by value gets corrupted at caller | 1024-element stress test: 510+ consecutive `getSlice()` calls alternating short(2)/long(63), nested outer-survives-inner, same-start-different-count. EXIT=0. zig0 C89 struct return IS correct. | 2026-06-12 |
| **Parser block truncation** — `parserParseBlock` drops children | Block 829 (.Go prong body) correctly has 8 children (payload start=273, count=8). `extra_children[273..281]` data is correct. Parser creates correct AST. | 2026-06-12 |
| **`astStoreGetExtraChildren` computation** — start/count wrong | GDB verified: payload=17891336, start=273, count=8, `start+count-start=8` in function. Returns `__make_slice_u32(items+273, 8)` correctly. | 2026-06-12 |
| **`astStoreAddExtraChildren` corruption** — appends wrong data | GDB verified: `extra_children[273..281]` = [758,771,784,797,810,818,822,828] — correct AST node indices. | 2026-06-12 |
| **TokenKind value mismatch between zig0 and C header** | C header enum values match Z98 enum order exactly (kw_var=54, kw_const=53, kw_return=68, kw_if=63). Verified via GDB + C define grep. | 2026-06-12 |
| **`strings` vs `grep -a`** — `strings` silently drops marker entries | Confirmed: `strings` strips null bytes. Use `grep -a "^PREFIX:" /tmp/markers.bin` instead. | 2026-06-12 |

## zig0 C89 Compilation Errors — Import/Missing Module Checklist

**DO NOT blame zig0 C89 limitations first.** When zig0 emits `use of undeclared identifier`, `unable to infer type`, or similar compile errors, follow this checklist IN ORDER before considering zig0 bugs:

1. **Missing `@import`** — `grep "const X = @import" <file>` vs `grep "X\." <file>`. If used but not imported, add the import.
2. **Wrong module alias** — files use different aliases for the same module: `lower.zig` → `const pal`, `semantic_analyzer.zig` → `const pal_mod`, `type_registry.zig` → `const pal_mod`. Check: `grep "const pal\|@import.*pal" <file>`.
3. **Stub file (never imported before)** — the file may have pre-existing bugs that were hidden because `main.zig` never imported it. Check: `grep "@import.*<filename>" sf/src/main.zig`.
4. **THEN consider zig0 limitations** — only after (1)-(3) are exhausted.

**Examples of false zig0-blaming (2026-06-27):**
- `pal_mod.markerWriteInt()` in `lower.zig` → "undeclared identifier" → blamed on C89 variable budget. Actual: `lower.zig` imports `const pal`, not `pal_mod`.
- `ast_mod.astStoreGetExtraChildren()` in `comptime_eval.zig` → "undeclared identifier" → blamed on type inference. Actual: `ast_mod` never imported in file (stub, never compiled before).

See AGENTS.md §9.1.1 for full rules. Memory [97cffe29](mnemoria).

## Non-Issues: Warnings That Are NOT Bugs or Blockers

Symptoms that look like failures but are EXPECTED. Do NOT treat them as
regressions, do NOT open blockers for them, and do NOT spend investigation
time chasing them.

| Symptom | Why it is NOT a bug | What to actually check |
|---------|---------------------|------------------------|
| **game_of_life: literal ANSI / terminal-clear escape codes appear in the output** | `system("clear")` writes terminal escape sequences to stdout. When output is piped or captured (not a live TTY), those sequences show up as literal bytes. **Both zig0 AND zig1 behave this way** — it is terminal behavior, not codegen. | Whether the patterns (glider, blinker, block, beehive, LWSS) and the `Generation: N` lines render correctly. The presence of escape codes is irrelevant. |
| **gcc *warnings* (as opposed to errors)** | Build commands intentionally suppress noise via `-Wno-long-long`, `-Wno-pointer-sign`, `-Wno-implicit-function-declaration`. Any remaining gcc *warnings* do not affect correctness of the produced binary. | Only the `error:` count matters. Gate builds on `gcc ... 2>&1 \| grep -c "error:"` equal to `0`. |

**Differential rule:** `zig0` is the reference oracle. A `zig1`-compiled
example is "correct" when its runtime output matches `zig0`'s output, modulo
the terminal-clear artifact described above.

## Memory Recall (DEPRECATED — use mnemoria instead)

> **DEPRECATED.** The old logfmt memory system has been migrated to `mnemoria`.
> See [Memory Recall via Mnemoria](#memory-recall-via-mnemoria) below.
> Logfmt files are preserved at `.opencode/memory/*.logfmt` for reference but
> are no longer the primary query mechanism.

Memory files local: `/workspace/znineeight/.opencode/memory/YYYY-MM-DD.logfmt`

### Read specific date:
```
Read filePath="/workspace/znineeight/.opencode/memory/2026-06-10.logfmt"
```

### Search across all dates:
```bash
grep -r "keyword" /workspace/znineeight/.opencode/memory/
```

### File format (logfmt):
```
ts=2026-06-10T01:14:11.343Z type=plan scope=project content="the memory text"
```

Types: decision, learning, preference, blocker, context, pattern
Scope: project (most common), build, api, database, etc.

### Read recent date files for current session context:
```bash
ls /workspace/znineeight/.opencode/memory/*.logfmt | sort -r | head -5
```

## Memory Recall via Mnemoria

Memories have been migrated from logfmt files to the `mnemoria` CLI tool.
Store at `.opencode/memory/` (managed by mnemoria; do NOT edit manually).

### Query Commands

```bash
# Stats
mnemoria --path .opencode/memory stats

# Search by keyword (semantic)
mnemoria --path .opencode/memory search "keyword"

# Ask a question (RAG-based)
mnemoria --path .opencode/memory ask "What issues were found?"

# Recent timeline
mnemoria --path .opencode/memory timeline --limit 10

# Filter by agent (legacy memories stored under two agents):
mnemoria --path .opencode/memory search --agent legacy-zni "keyword"
mnemoria --path .opencode/memory search --agent legacy-deleted "keyword"

# View timeline for specific agent
mnemoria --path .opencode/memory timeline --agent legacy-zni --limit 5
```

### Legacy Agent Names

| agent_name | Content | Count |
|---|---|---|
| `legacy-zni` | Active memories from pre-migration logfmt system | 1,498 entries |
| `legacy-deleted` | Previously deleted/forgotten memories, retained for reference | 431 entries |

### Type Mapping (logfmt types → mnemonia entry_type)

| logfmt type | mnemonia entry_type |
|---|---|
| learning | discovery |
| decision | decision |
| plan | intent |
| blocker | problem |
| pattern | pattern |
| context | discovery |
| preference | discovery |

### Adding New Memories

```bash
mnemoria --path .opencode/memory add \
  --agent my-agent-name \
  --type discovery \
  --summary "Brief description" \
  "Detailed content here"
```

> **Full reference:** `docs/sf/AGENTS.md` Section 9 covers all conventions, agent naming, and usage patterns in detail.

> **Memory store location (IMPORTANT — do not create a stray store):** the real,
> populated memory database lives at **`.opencode/memory`** (~2,100+ entries).
> ALWAYS pass `--path .opencode/memory` (or `-p .opencode/memory`). Running
> `mnemoria` from the repo root without `--path` reads/creates a DIFFERENT, near-empty
> store at `./mnemoria/` (a stray build-mode artifact with only a handful of entries) —
> that is NOT the project memory. If a search returns very few results, you are on the
> wrong store: re-run with `--path .opencode/memory`, raise `--limit` (default 10 is
> low; try `--limit 40`+), and vary phrasings before concluding a memory is absent.

## Writing Plans & Plan-Mode Write Permissions

The **superpowers `writing-plans` skill** produces bite-sized, TDD, task-by-task
implementation plans. Load it via the `skill` tool when you have a spec/requirements
for a multi-step task, before touching code.

- **Where plans are saved:** `.opencode/plans/YYYY-MM-DD-<feature-name>.md`
  (this overrides the skill's default `docs/superpowers/plans/`). This directory is
  **git-ignored / untracked** — writing a plan there alters nothing in the tracked
  project; it is a scratch/handoff artifact.
- **Plan mode is READ-ONLY for CODE/PROJECT/SYSTEM state only.** Per the durable
  operator decision (mnemoria, 2026-06-26 "m1213", tags `plan-mode,memory-tool,compress,allowed`),
  the following ARE permitted while in plan mode, on the operator's request:
  - Writing/updating **plan `.md` files** under `.opencode/plans/` (untracked, benign).
  - Storing memories via **`mnemoria add`** (a benign collaboration side-channel).
  - Running **`compress`** (context-management meta-op).
- **Still forbidden in plan mode:** source/code edits (`edit`/`fastedit`/`write` on
  tracked project files), shell file-manipulation, `git commit`, `git checkout`,
  config changes — i.e. any real project/code/system mutation.
- **Do not re-litigate this.** If unsure whether a specific plan-mode write is allowed,
  search mnemoria (`--path .opencode/memory search "plan mode memory-tool allowed"`)
  and follow the operator's standing authorization rather than looping.

## Code Review via Superpowers Skill

Trigger the requesting-code-review skill when auditing completed changes.

**Manual review (in-session, plan mode):** `skill: requesting-code-review`
1. Obtain diff: `git diff` or `git diff BASE..HEAD`
2. Audit against template at `~/.cache/opencode/packages/superpowers@.../superpowers/skills/requesting-code-review/code-reviewer.md`
3. Checklist: plan alignment, code quality, architecture, edge cases, tests
4. Categorize: Critical / Important / Minor
5. Give clear verdict: Ready to commit / With fixes / Do not merge

**Subagent review (build mode):** Dispatch general-purpose subagent with `BASE_SHA`/`HEAD_SHA`, fill template from `code-reviewer.md`. Reviewer inspects `git diff BASE..HEAD`, returns Strengths + Issues + Assessment.

**Key principles:** Review early/often. Fix Critical before proceeding, Important before merge. Categorize by actual severity — not everything is Critical. Acknowledge strengths before listing issues.

### Review Hardening (MANDATORY)

- Deviations from contract = `BLOCKED` (never `DONE`); controller must STOP before any commit containing a deviation.
- Reviewer prompts: no "do not flag", no pre-judged severities, no shielding of findings.
- Every fix-task gate battery MUST include RUNTIME execution; compile-only gates forbidden.
- All Important/Critical review findings → fix subagent + re-review, or explicit operator ruling. No self-adjudication.
- Verification claims require evidence (file:line, output). Unevidenced = false.

**Full policy:** `docs/sf/AGENTS.md` §2.5 (post-incident, 2026-07-17).

## zig0 Runtime h/c Architecture

The zig0 bootstrap compiler has a two-tier runtime that supports **both**
the compilation of zig1 itself (zig0 → C89 → gcc link) and the programs
compiled *by* zig1 (zig1 → C89 → gcc link). Understanding this split is
critical when adding new runtime functions or debugging linker errors.

### File Layout

| Path | Role | Used by |
|------|------|---------|
| `src/include/zig_compat.h` | C89 type definitions (`i64`, `u64`, `ZIG_INLINE`, `ZIG_UNUSED`) | All C89 output |
| `src/include/zig_runtime.h` | **Inline** bootstrap helpers (`__bootstrap_X_from_Y` casts, panic, print) | All generated `.c` files |
| `src/runtime/zig_runtime.c` | **Non-inline** runtime (arena alloc, sleep, platform console) | Linked at build |
| `$OUT/zig_runtime.h` | **Copy** of `src/include/zig_runtime.h`, emitted by zig0 via `--header-priority-include` | gcc `#include` resolution |
| `$OUT/zig_runtime.c` | **Generated** runtime .c by zig0 (includes the header) | Linked into zig1 binary |

### How zig0 Copies Headers

zig0 `--header-priority-include` copies key headers from `src/include/`
into the output directory alongside the generated `.c` files. This is why
the gcc link command (`gcc $OUT/*.c`) works without `-I` — each `.c` can
`#include "zig_runtime.h"` relative to its own directory.

To make a new header available, place it in `src/include/` — zig0 copies
all `.h` files from that directory.

### `__bootstrap_X_from_Y` Cast Helpers (Inlines)

Zig0's `@intCast(u32, i64_expr)`, `@intCast(u8, usize_expr)`, etc.
emit calls to `__bootstrap_DSTTYPE_from_SRCTYPE(source)`. These are
**inline** functions defined in `src/include/zig_runtime.h` (lines 99–180).
They use `ZIG_INLINE ZIG_UNUSED` → `static` in C89, so each generated
`.c` file gets its own copy — **no linker symbol needed**.

**Pattern** (all helpers follow this):
```c
ZIG_INLINE ZIG_UNUSED u32 __bootstrap_u32_from_i64(i64 x) {
    if (x < 0 || x > (i64)4294967295U) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (u32)x;
}
```

**Win9x safety:** These functions are **pure arithmetic + panic call**.
They use no C standard library (no `stdio.h`, `string.h`, `stdlib.h`,
`malloc`, etc.). The types (`i64`, `u64`, `u32`, etc.) are defined
per-compiler in `zig_compat.h`:
- **MSC (win9x):** `typedef unsigned __int64 u64`
- **Watcom:** `typedef unsigned long long u64`
- **gcc:** `typedef unsigned long long u64`

The `ZIG_INLINE` macro expands to `static __inline` (MSC), `static __inline__`
(gcc), or `static` (other). The `ZIG_UNUSED` macro suppresses
`-Wunused-function`.

### `src/runtime/zig_runtime.c` (Non-Inline Symbols)

For functions that **cannot** be inline (arena alloc, sleep, platform I/O),
implementations live in `src/runtime/zig_runtime.c` as regular linkable symbols.
This file is compiled separately and linked into the final binary. Note that
**not** all bootstrap helpers need a non-inline version — the inline helpers
in the header are sufficient for most casts.

Some helpers exist in BOTH places (inline header + .c definition) as a
safety fallback — see `__bootstrap_u16_from_usize` (line 286 of the .c).

### Adding a New Runtime Definition

**For a new `@intCast` target pair (inline)**:
1. Add to `src/include/zig_runtime.h` following the pattern:
```c
ZIG_INLINE ZIG_UNUSED DST_T __bootstrap_DST_from_SRC(SRC_T x) {
    if (<range check>) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (DST_T)x;
}
```
2. Rebuild zig1 — zig0 copies the updated header to `$OUT`.

**For a non-inline function (linkable symbol)**:
1. Declare in `src/include/zig_runtime.h` (as `extern` or `ZIG_INLINE`).
2. Define in `src/runtime/zig_runtime.c` as a regular C function.
3. Ensure the zig1 build or zig0 runtime emission includes the `.c`.

**Common link error:** `undefined reference to '__bootstrap_U64_from_I64'`
→ This exact helper is **missing** from `src/include/zig_runtime.h`.
Add it per the inline pattern above. (Added 2026-06-29 for enum(u8) support.)

### Tech Docs (as-built pipeline reference)
Location: sf/docs/tech_docs/
INDEX.md — master cross-reference (error→phase, function→file, marker→meaning)
00_shared_infra.md — Allocator, Interner, Diagnostics, PAL, Source Manager, utility modules
00_lexer_parser.md — Lexer, Parser, AST
01_import_resolution.md — Module graph & import resolution
02_symbol_registration.md — Symbol table registration
03_type_resolution.md — Type resolution & registry
04_comptime_eval.md — Compile-time evaluation
05_semantic_analysis.md — Semantic analysis (resolveExpr, resolveStmtDepth)
06_static_analyzers.md — Flow-sensitive static analyzers
07_lir_lowering.md — LIR lowering & control-flow flattening
08_c89_emission.md — C89 code emission & name mangling
09_pipeline_orchestration.md — Pipeline orchestration (main.zig, main_dump.zig)
10_c_runtime.md — C runtime layer (zig_runtime.c/h, zig_pal.c/h)
11_build_system.md — Build scripts & output isolation
