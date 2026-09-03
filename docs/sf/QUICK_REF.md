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
- For **mud_server** add `sf/src/include/net_runtime.c` ONLY when building the pre-F6
  `examples/zig0/mud_server` bootstrap example — the migrated `examples/z98/mud_server`
  (std_net) links WITHOUT it (F6).
- For a **no-`main` repro** (compile-only, no link/run) use `gcc -m32 -std=c89 -c ... -o /dev/null`.
- **[updated: 2026-08-14 — F-MIGRATE] examples/repros now use bare `@import("std")`**, resolved
  via the search path: (1) importer's dir, (2) `-I`/`--lib-dir` dirs in CLI order, (3) the default
  install path `<exe_dir>/lib`, (4) CWD. To run a migrated example/repro you must first install the
  canonical std lib next to the compiler under test:
  `mkdir -p <exe_dir>/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig <exe_dir>/lib/`
  (for `/tmp/fx_subfolder/zig1` that is `/tmp/fx_subfolder/lib/`). The local `std*.zig` copies are
  gone from the migrated examples/repros; `std_import_bare_xmod/local/` remains a fixture (the Task R
  `--lib-dir` GREEN test), and the 4 `r_fallback_*` repros (fnret / constalias / constalias_prepass /
  control) intentionally ship local `std.zig`/`std_io.zig` copies with explicit `.zig` imports as
  collision-repro fixtures (out of scope to migrate).
- A compiler ICE shows as `dump rc=134` (SIGABRT) with a `PANIC:` line — note the panic text may land
  on **stdout** (`/tmp/x.c`), not stderr.

### Spill level switch (`-s<N>`) — RAM/I-O tradeoff  [added: 2026-09-02 — spill-backend-config F-S]

`-s<N>` picks how many of the five spills live in RAM instead of the `.zig1_*.tmp` disk files.
Default `-s0` = all on disk. Deactivation order (oldest-spill-first): **S-AST → S-LIR → S-HASH →
S-RES → S-SIDE** — `-s1` moves AST to RAM, `-s2` also LIR, ... `-s5` = all RAM (no spill files).
Higher `-s` = more RAM, less disk I/O; emission is **byte-identical in every mode** (same data,
different storage). Measured self-compile `pool=` (self-hosted binary, `--markers --track-memory`):
`-s0` ~14.9 M, `-s1` ~33.3 M (both fit the 64 MB `-mm` default); `-s2`..`-s5` ~71-73 M → **exceed
the default and must be paired with `-mm128`** (else `memory limit exceeded`, rc=3). Range 0..5;
bare `-s` / non-digit / out-of-range (`-s6`) error rc=1. Per-level smoke: `.zig1_ast.tmp` absent at
`-s1`, `.zig1_lir.tmp` absent at `-s2`, etc. — the spill-file ladder is the mode marker.

### Corpus gate (330 dirs in `repro/mi_matrix/*/`, all with `main.zig`)  — classify by gcc EXIT CODE  [updated: 2026-09-02 — spill backend config plan GATE; the full gate sweep is the corpus at `-s0`, 404 dirs = 330 mi_matrix + 53 top-level repro + 21 z98 (`slice_matrix` skipped)]
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
- **Post-voiddecl-family baseline (GATE gate sweep, 2026-08-20, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `df82d010`, canonical std reinstalled): `OK=275 FAIL=7 ICE=0 CRASH=0 GREEN=4` over 286 dirs** (275+7+4=286). Corpus grew 277→286 (+9 dirs: `parsergap_slice_expr_xmod`, `parsergap_zeroarr_slice_xmod`, `voiddecl_ifexpr_xmod` + `voiddecl_ifexpr_ctl_xmod` (R1 two-fixture), `voiddecl_switchexpr_xmod`, `voiddecl_u64cast_xmod`, `voiddecl_xmodtype_xmod`, `voiddecl_tagprobe_xmod`, `voiddecl_payload_xmod`) — 8 new dirs OK, `parsergap_slice_expr_xmod` now **FAIL** (clean-reject `error[2000]`, the F-REJECT ICE→FAIL flip). **VOID-decl family fully fixed** (Root 1 front_resolution F1 `27c71619` + Root 2 `.tag` F2 `660ff8e2`) — self-compile `error[3000]` **9→0**; **F-ICE 3-loci + Fix A + Fix B** (`fd56da3b`, AMENDMENT 5 ratified) — `error[3043]`→0 whole-tree; **F-REJECT** scalar-base clean reject (`838935ce`); **R/I/F-PAYLOAD** 2-locus `.payload` (`19d919bd`, AMENDMENT 6) — `voiddecl_payload_xmod` RED→OK. FAIL=7 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` + `parsergap_specifier_xmod` + `parsergap_strict_comma_xmod` + `strictzig_brace_if_xmod` (M1 hard-RED, FAIL **by design**) + `parsergap_slice_expr_xmod` (clean-reject). Green-guards unchanged (4). 21-example matrix **21/21** dump/gcc/link OK (game_of_life + mud_server + rogue_mud timeout-gated rc=124 with correct output — counted PASS; json_parser parses test.json rc=0 from its dir). 4 MD5 gates: gol `9cf758d9…` [→ `4afb203f…`], lisp `88dcb7f9…` [→ `5f886646…`] (repo-root CWD), mud `a1d0dd55…` byte-identical; **json RE-BASELINED `fc357296…` → `9720478c…`** (AMENDMENT 3 ruling 2026-08-19 — F1 front-resolution types json_parser's `var g_arena`, 5 temp decls `unsigned int`→`Arena*`; runtime-identical). test_analyzer_bin PASS ("5 passed, 4 failed"). Self-compile re-check: **error[3000]==0 AND error[3043]==0** hold; rc=134 at the recorded next blocker **PANIC `c89_emit.zig:5002`** `width_bits = @intCast(u8, size*8)` u8 overflow on a 40-byte tagged-union temp — **recorded, NOT fixed** (frontier).
- **Post-widthbits-overflow baseline (GATE gate sweep, 2026-08-20, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `d5a966f7`, canonical std reinstalled): `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4` over 287 dirs** (276+7+4=287; 286 + the `widthbits_union_intconst_xmod` R1 fixture flipped OK). Corpus grew 286→287 (+1 dir: the R1 fixture `widthbits_union_intconst_xmod`, commit `582bfc4e`, RED→OK). **FAIL=7 set unchanged** from v42 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) + `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod` (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged (4). **Widthbits fix (F1 `d5a966f7`, Option B u32):** `width_bits`/`wb` u8→u32 across the 3-site class (`c89_emit.zig:5002` PANIC locus + `:3190` emitSatBinary + `comptime_eval.zig:139` second live site) + the full enumerated surface, with the STOP-approved `>=` shift-guard hardening (`comptime_eval.zig:141`/`:185` `wb >= @intCast(u32, 64)`) — self-compile PANIC gone. 21-example matrix **21/21** dump/gcc OK. 4 MD5 gates byte-identical: gol `9cf758d9…` [→ `4afb203f…`], lisp `88dcb7f9…` [→ `5f886646…`] (repo-root CWD), json `9720478c…`, mud `a1d0dd55…`. test_analyzer_bin PASS ("5 passed, 4 failed"). **MAJOR MILESTONE — self-compile FULLY GREEN:** `timeout 120 zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` → **rc=0, 40 `.c`, zero `error[` non-9999, zero PANIC** — the widthbits fix was the **last self-compile blocker; next frontier blocker: NONE** (the `--markers` .c failing strict single-file `gcc -c` is a pre-existing emission quirk, NOT a blocker).
- **Post-residual-closeout baseline (GATE gate sweep, 2026-08-22, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `b9256f2e`, canonical std reinstalled): `OK=292 FAIL=7 ICE=0 CRASH=0 GREEN=4` over 303 dirs** (292+7+4=303; 287 + the 16 emission-fixture dirs from the residual plan's R tasks — all 16 classify **OK**, incl. `emission_mangler_collision_xmod` / `emission_type_storage_extern_xmod` / the sibling-payload + void-temp + variation fixtures, all RED→OK). **FAIL=7 set unchanged** from v43 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) + `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod` (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged (4). **Residual plan CLOSED (AMENDMENT 12 — terminal gate re-scoped):** the 4 scoped fixes landed — **F-C3-tighten** (`6534a65b`, `json_parser_workaround` stdout byte-identical to base, md5 `dc22fa47…`, RV 21/21), **F-A2EXT** (`b019c671`, self-compile `zG_` 9→0), **F-E2DOWN** (`9e00bec7`, `TokenValue has no member 'none'` 62→0), **F-SWITCH** (`b9256f2e`, switch-on-plain-enum case values correct — `emission_mangler_collision_xmod` prints **4**, `emission_type_storage_extern_xmod` prints **3**). Scoped gates HOLD: `zG_` 0, `TokenValue.none` 0, json regression fixed. **Self-compile NOT buildable (deferred):** `timeout 120 zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` → **194 remaining gcc errors** (`incompatible types when assigning` ×86, `zT_<n> undeclared` ×68, `request for member` ×22, `has no member` ×8, `pal` ×5, misc ×5) = deferred NEW residual classes (out of scope, recorded for a future plan). 21-example matrix **21/21** dump/gcc/link rc=0 (mud_server + rogue_mud + game_of_life timeout-gated rc=124 with correct output — counted PASS; json_parser parses test.json rc=0 from its dir). **4 MD5 gates: gol `9cf758d9…` → `4afb203f…` RE-BASELINED + lisp `88dcb7f9…` → `5f886646…` (repo-root CWD) RE-BASELINED** (both predate the F-attempt emission changes; runtime-identical — gol glider grid rc=0, lisp `(+ 1 2)`→3 etc. rc=0 — per the operator's runtime-priority rule); **json `9720478c…` + mud `a1d0dd55…` UNCHANGED** (byte-identical). test_analyzer_bin PASS ("5 passed, 4 failed").
- **Post-194-closeout baseline (GATE gate sweep, 2026-08-24, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `5c739971`, canonical std reinstalled): 194-error plan CLOSED.** Corpus 303 → 310 dirs (+7 emission-fixture dirs from the 194-plan's R tasks: `emission_assign_xmod`, `emission_zT_undeclared_xmod`, `emission_request_member_xmod`, `emission_no_member_xmod`, `emission_pal_xmod`, `emission_misc_xmod`, `emission_orelse_xmod`). **Fixes landed:** F-MIGRATE `1a06716b` + `df9c3017` (bare `pal`→`pal_mod` + undeclared-identifier diagnostic, `pal` ×5→0), F-A `6b44d7a3` (LirInst tag-emission, assign ×48), F-B `6d4892bf` + `56a80136` (hoisted-local disambiguation, name-keyed conflation ×108), F-ORELSE `f8e3d914` (orelse value-flow, ×6), F-C `cb378f17` (no-member + misc, 8+5); AMENDMENTs 4 `f5ab3bc3` / 5 `05ea274d` (docs commits). **Self-compile residual (194-plan FINAL):** `timeout 120 zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` → **12 remaining gcc errors = R2 `zT_<n>` undeclared ×11 + R1 `Opt_10` assign ×1** (11+1=12), deferred to the R2/R1 implementation plan — FORWARD: docs/superpowers/plans/2026-08-23-self-compile-closeout-r2r1-plan.md. 21-example matrix **21/21** dump/gcc/link rc=0. **4 MD5 gates:** **json RE-BASELINED `9720478c…` → `d31e43b1…`** (operator-approved during F-ORELSE — runtime-identical, the orelse fix repairs the semantically-broken null path); gol `4afb203f…` + lisp `5f886646…` (repo-root CWD) + mud `a1d0dd55…` unchanged.
- **Post-out-of-scope-residual-closeout baseline (GATE-FINAL, 2026-08-25, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `ec306847`, canonical std reinstalled): out-of-scope residual closeout PLAN COMPLETE (AMENDMENTs 1-6).** Corpus 323 dirs = **OK=313 / FAIL=0 / ICE=0 / CRASH=0 / GREEN=10** (313+0+0+0+10=323). The FAIL=9 residual set is fully closed (FAIL→OK or →green-guard), CRASH 1→0. Classification changes: plat_stubs_missing_xmod CRASH→OK (F-PLATSTUBS `7d1b512d`); emission_orelse_labeled_xmod + emission_catch_labeled_xmod FAIL→OK (F-LABELED `2cbf1fd3`); emission_opt_fptr_wrap_xmod added+OK (R `70af559c` + F-OPTFPTR `53b9f1b6`); parsergap_specifier_xmod FAIL→OK (F-SPECIFIER `a9ea91f0`, {x} prints `41`); field_store_drop FAIL→OK (fixture correction `3ef2e8c8`, canonical `pal.zig` import; temp-0 sentinel superseded); strictzig_brace_if_xmod + parsergap_selfblok_xmod (brace-less if/else) + parsergap_strict_comma_xmod (missing comma) + parsergap_slice_expr_xmod (scalar-base slice, no ICE) + self_embed_optional_cycle (error[24] circular-type — real Zig rejects `?X` value self-reference) FAIL→green-guard; emission_pal_xmod already green-guard. **Oracle rulings:** {x} = lowercase hex no prefix (langref); brace-less `if;else` correctly rejected (migrated sf/src sites via `22006588`); canonical self-reference pattern is `?*X` optional POINTER (pointer-sized, null=0; langref linked-list `prev: ?*Node, next: ?*Node`) — Z98's error[24] for `?X` is CORRECT. **json gate RE-BASELINED `d31e43b1…` → `089e4f046464ce3882aa2b2c4e585013`** (AMENDMENT 4, F-NULLWRAP `a6fe169b` — `has_value = result != 0`; runtime-identical normal path, repairs the NULL path; gol/lisp/mud byte-identical); `089e4f04…` is the authoritative json hash. **MAJOR MILESTONE — self-compile gcc-CLEAN AND LINK-green AND binary RUNS crash-free:** `bash scripts/self_compile/build_zig1_5.sh` → dump rc=0, 40 `.c`, in-script gcc -c clean (0 error lines), BOTH `zig1_5_clean` + `zig1_5_asan` link rc=0 (c_exit linked via `aa552f5d`), self-compiled binary runs on real input crash-free (rc=2 misparse = the recorded deferred **self-emission fidelity gap**, NOT a regression — needs its own R/I/F plan). 21-example matrix **21/21** dump/gcc/link rc=0. test_analyzer_bin PASS (rc=0). Open question (not a blocker): `?*X` optional-pointer self-reference support.
- **Post-COMBINED-3-6 baseline (GATE, 2026-09-03, HEAD `bbe47d0e`): @bitCast/cross-module-store/export/switch-range GREEN (COMBINED items-3-6 docs GATE, operator-approved fixed-point re-baseline).** Four fixes landed — F-BITCAST `3922a8d7` (@bitCast same-size integer reinterpretation), F-CROSSMOD-STORE `3ad5c12e` (cross-module pub var scalar store fix), F-EXPORT `9b2fef74` (export fn/var source-name symbols), F-SWITCHRANGE `bbe47d0e` (switch case-range per-value expansion + itoa64 hardening). Five R3/R4/R5/R6 fixtures GREEN (run-gate verified, byte-exact RUNRC=0): `builtin_bitcast_xmod` `-1`, `crossmod_pubvar_xmod` `7 7`, `export_fn_xmod` `81` (+ non-static source-name `square` symbol gate), `export_var_xmod` `3` (+ non-static `counter` symbol gate), `switch_case_range_xmod` `130 47`. 4-MD5 gates byte-identical UNCHANGED (gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` — NO gate re-baseline). Golden 9/9 PASS; matrix 21/21 PASS; corpus 424 dirs `-s0` **OK=405/FAIL=13/GCCFAIL=0/GREEN=6/ICE=0/CRASH=0** — the ONLY compile-asymmetry is 3 dirs (crossmod ICE→OK + export×2 FAIL→OK); the @bitCast + case-range flips (RED = compile-OK runtime-wrong) are visible ONLY via the run-gate. NEW reference md5 `821d77ff…` (rebuilt at HEAD `bbe47d0e`); NEW self-compile fixed point `0468a42b…` → `bf1e37ca…` (operator-approved re-baseline — 42 `.c`/0 err/0 PANIC, hop2==hop1 closed, moved because the compiler source grew across the four plans).
- **Post-F-PTRBUILTIN baseline (GATE, 2026-09-03, HEAD `35468510`): the pointer builtins `@intFromPtr`/`@ptrFromInt`/`@fieldParentPtr` now lower (F-PTRBUILTIN `c5381d94`+`35468510`).** `@intFromPtr` = alias branch-extension of the existing `@ptrToInt`; `@ptrFromInt` = ANNOTATED form reading the target pointer type from the expected-type stack (fixture amend `c5381d94` annotates the target var); `@fieldParentPtr` = struct byte-offset chain (resolve field by name → ptr_to_int(&o.field) − offset → int_to_ptr back to `*Outer`). The two R2 fixtures are GREEN with byte-exact stdout `42`/`1` (builtin_ptr_roundtrip_xmod / builtin_fieldparentptr_xmod, run-gate verified). 4-MD5 gates byte-identical: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` (unchanged hashes — NO gate re-baseline). Golden 9/9 PASS; matrix 21/21 PASS; corpus 424 dirs `-s0` OK=402/FAIL=15/GCCFAIL=0/GREEN=6/ICE=1/CRASH=0 — 2-dir delta ONLY (the 2 builtin dirs GCCFAIL→OK), 0 asymmetric elsewhere (FAIL 15 / GREEN 6 / ICE 1 sets row-identical to the F-INTRO sweep). NEW reference md5 `d0da7204…` (rebuilt at HEAD `35468510`); NEW self-compile fixed point `0468a42b…` (operator-approved re-baseline — 42 `.c`/0 err/0 PANIC, hop2==hop1 closed).
- **Post-F-INTRO baseline (GATE, 2026-09-03, HEAD `c8145a8b`): the introspection builtins `@offsetOf`/`@bitSizeOf`/`@bitOffsetOf` now fold at comptime (F-INTRO `c8145a8b`) — struct-only `@offsetOf`/`@bitOffsetOf` field byte offsets (non-packed exact), `@bitSizeOf` size×8 with bool→1.** The three R1 fixtures are GREEN with byte-exact stdout `0 4 8`/`1 8 32`/`0 32 64` (builtin_offsetof_xmod / builtin_bitsizeof_xmod / builtin_bitoffsetof_xmod, run-gate verified). 4-MD5 gates byte-identical: gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `53405b3b…` (unchanged hashes — NO gate re-baseline). Golden 9/9 PASS; matrix 21/21 PASS; corpus 424 dirs `-s0` OK=400/FAIL=15/GCCFAIL=2/GREEN=6/ICE=1/CRASH=0 — 3-dir delta ONLY (the 3 builtin dirs GCCFAIL→OK), 0 asymmetric elsewhere (FAIL 15 / GREEN 6 / ICE 1 sets row-identical to the LANGWINS G1 sweep). NEW reference md5 `ecdec6f4…` (rebuilt at HEAD `c8145a8b`); NEW self-compile fixed point `d9b3e041…` (operator-approved re-baseline — 42 `.c`/0 err/0 PANIC, hop2==hop1 closed).
- **Post-SWEXPR + store-drop baseline (GATE, 2026-09-03, HEAD `f014259b`): switch-expr payload-capture fix (`6d71b917`) + global array-element store-drop fix (`f014259b`, C4-helper/C3-semantics in c89_emit.zig) LANDED.** Record: mud 4-MD5 gate RE-BASELINED `4591fef0…` → `53405b3b…` (runtime-verified vs zig0 oracle — "north" replies `A sunny clearing…`; mud was a broken sample pre-fix: world never initialized). gol/lisp/json byte-identical (`302df36b…`/`3591bad9…`/`76056b97…`). Both I/F RED fixtures now GREEN (`switch_expr_payload_capture_xmod` helloA/helloB 28 B; `global_struct_array_store_xmod` `1 5 5 10`). Golden 9/9 PASS; matrix 21/21 PASS; corpus 405 dirs `-s0` OK=395/FAIL=5(=green-guards)/GREEN=5/ICE=0/CRASH=0, asymmetric 0; self-compile round-trip 42 `.c`/0 err/0 PANIC, NEW fixed point `3b45184e…`; json_parser_upgraded run rc=0 stdout byte-identical.
- **Post-self-host-closure baseline (GATE, 2026-09-02, measured on the plan's fixed-point chain — reference `/tmp/fx_subfolder/zig1` (zig0-built, md5 `29327e2c1d17cb3afc7b2c0dc6c639c8`) vs the 5 byte-identical self-host binaries under `/tmp/zig1_5*` (md5 `e2028dcf2324785016bbfaa1454880de`, size 2,930,952 B): zig1 self-host closure PLAN COMPLETE — determinism fixed point CLOSED (docs-only GATE).** Self-compile round-trips (`/tmp/zig1_5_gate_self`, `/tmp/zig1_5_gate_selfself`, + the two hop builds) each produced byte-identical binaries (md5 `e2028dcf`) → **fixed point closed, 5/5 self-host binaries byte-identical**; the plan-doc value `0c09fe1a` is STALE (binaries rebuilt during the bootstrap-chain restore) — actuals recorded. **Emission + runtime determinism:** all 4 compilers (zig0-built ref + 3 self hops) emit `sf/src/main.zig` byte-identically — 42 `.c` + 43 `.h` each, rc=0, 0 `error[`, 0 PANIC, 85-file md5 manifest fingerprint `c5ab5df5` (hidden `.zig1_ast.tmp`/`.zig1_lir.tmp` spill scratch is non-deterministic — compare `.c`/`.h` only); T-Z98-DET **21/21** `examples/z98` emission-identical zig1 vs zig1_5_clean (normalize-diff empty; only std install-path module-hash tokens differ) AND 21/21 runtime-identical (stdout byte-equal + rc equal). **Full battery (both new hops):** 4 MD5 gates byte-identical — gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `4591fef0…` (unchanged, no re-baseline); golden 9/9 PASS (stdout identical to reference golden); matrix 21/21 PASS (mud/rogue/gol timeout-gated rc=124 = PASS); corpus sweep 404 dirs at `-s0` = **reference OK=394 / FAIL=10 (= exactly the 10 green-guards) / ICE=0 / CRASH=0, hop identical, asymmetric = 0**; self-compile round-trips 42 `.c` / 0 `error[` / 0 PANIC, produced binary md5 == hop md5. **Perf tradeoff** (T-PERF, measured on the final hop `/tmp/zig1_5_self_self/zig1_5_clean`): self-compile pool per `-s` = `-s0` 14,857 K / `-s1` 33,289 K / `-s2` 70,921 K / `-s3` 70,921 K / `-s4` 71,945 K / `-s5` 72,969 K (RSS 16.9→59.8 MB; disk spill files 17.7 MB→0; wall ~3.6–4.2 s flat); `-s2`..`-s5` exceed the `-mm64` default → ICE `memory limit exceeded` rc=3 unless paired with `-mm128`; small examples barely move (~0.2–2 MB pool); higher `-s` = more RAM, less disk I/O. **`_upgraded` examples (TWO committed, ONE deferred):** `examples/z98/lisp_interpreter_upgraded` (commit `ab318b1e`; lisp_interpreter_curr base + 2 C1 naked-tag `==` hoists — eval.zig truthiness `.Nil` test + builtins.zig builtin_is_nil; 15 files source-only; stdout byte-identical vs original; all 4 compilers identical); `examples/z98/rogue_mud_upgraded` (commit `93d3ee79`; rogue_mud base + 4 C1 rewrites — combat.zig / pathfinding.zig / scenario.zig carveH+carveV / ui.zig; 29 files; stdout byte-identical vs original under q-quit + moves+look feed; all 4 compilers identical; the C2 drop-`else` rewrites deliberately NOT applied — emission-bug class); `examples/z98/json_parser_upgraded` **DEFERRED, NOT committed** — U-INV's const-from-switch-expression rewrite for json.zig key extraction crashes rc=139 SIGSEGV on all 4 compilers due to a REAL zig1 emission bug (switch-as-**expression** with **payload capture** mis-lowers: payload binding emitted after the dispatch `goto` before the case label → skipped → uninitialized read); statement-switch form emits correctly; untracked dir left in place for the future fix (follow-up I/F task to be created). **Migration-readiness:** the bootstrap cycle (zig0 → zig1) is at a deterministic fixed point — zig1 self-compiles to a byte-identical binary across hops, emission- and runtime-identical to the zig0-built reference; the cycle is **closable via the future cInclude-zig1-only migration** (dropping the zig0 front end once zig1 compiles its own `@cInclude` sites).
- **Post-spill-backend-config baseline (GATE, 2026-09-02, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `cc5c37c1`, canonical std reinstalled): spill backend config PLAN COMPLETE — FULL sweep + reconciliation (docs-only GATE).** The five F-series tasks landed (F-SIDE `a1bfa260` AST value pools disk-backed → F-FMT `eb8730c8` RES 5 B/node → F-SBackend `89c310a7` `SpillStore` Disk/Ram → F-MM `16d28337` `-mm<N>` default 64 MB ACTIVE → F-S `cc5c37c1` `-s<N>` decremental levels + help/README). **4 MD5 gates byte-identical at EVERY level `-s0`..`-s5` (no re-baseline, repo-root CWD): gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `4591fef0…`** — the `-s`/`-mm` changes are storage/config only, emission is byte-identical in every mode. Golden 9/9 fixtures 9/9 at every level. Matrix 21/21 (mud_server/rogue_mud server-timeout by design). Corpus sweep at `-s0` 404 dirs: **334 RUN_OK + 56 LINK_FAIL + 10 DUMP_FAIL (= exactly the 10 green-guards) + 2 RUN_TIMEOUT (mud_server/rogue_mud) + 2 RUN_FAIL (intcast_range_check rc=134, voiddecl_xmodtype_xmod rc=139)** — 0 asymmetric, 0 NEW (gol now RUN_OK rc=0, was timeout in the memory-refactor sweep = timing artifact). Self-compile `build_zig1_5.sh` → **42 `.c` (41 + `spill_store`), 0 `error[`, 0 PANIC**, hello byte-equal; reference emission vs self-emission byte-identical (0 diff pairs). Warning-clean both builds (1 pre-authorized fwrite carve-out each). **Pool trajectory** (self-compile `--track-memory`): allocator-crux GATE 25,742 K → plan start (I-SIDE) 15,324 K → `-s0` **14,857 K** (Disk, default) / `-s1` 33,290 K (both fit the `-mm64` default) / `-s2` 70,922 K / `-s3` 70,922 K / `-s4` 72,970 K / `-s5` **72,970 K** (all-Ram, no spill files). **`-mm64` default is ACTIVE and HOLDS `-s0`/`-s1` self-compile; `-s2`..`-s5` exceed it → `memory limit exceeded` ICE rc=3 unless paired with `-mm128`** (documented tradeoff); canary `-mm1` self-compile ICEs rc=3 (`pool limit=1024K pool=6513K`). Spill-file ladder verifies prefix deactivation: `-s1` drops `.zig1_ast.tmp`, `-s2` also `.zig1_lir.tmp`, `-s3` also `.zig1_hash.tmp`, `-s4` also `.zig1_res.tmp`, `-s5` none.
- **Post-memory-refactor baseline (GATE-FINAL, 2026-08-26, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `179257dc`, canonical std reinstalled): zig1 memory-refactor execution PLAN COMPLETE — FULL battery + reconciliation (docs-only GATE).** `--track-memory --markers` self-compile: **`track-memory: perm=1661K mod=2047K scr=2047K pool=25742K type_db=246K total=5755K`** — **`pool=25,742 K`**, ≤16,384 K (16 MiB) target **NOT reached**; **documented residual gap = 9,358 K (≈9.14 MiB)**. Trajectory: 50,501 K → S-LIR 42,513 K → S-HASH 44,678 K → S-TOKEN 55,038 K (transient) → S-AST 35,973 K → S-RES 25,738 K → GATE 25,742 K (Δ4 K input-growth noise). Closures: **M5** closed-unfeasible, **S-INTERNER** closed-unfeasible (interner text measured 294,744 B ≈ 0.29 MiB, not ~4 MB), **I-COMPACT** no-go (16-B AstNode = byte-identical disk-record shuffle; record delta 0 or +16,384 B/block, +2.2 MiB pool ADD if spans resident; 47 span-read + 45 child_2 site cost, ≤0 effect). 4 MD5 gates byte-identical (repo-root CWD): gol `302df36b…` / lisp `3591bad9…` / json `76056b97…` / mud `4591fef0…` — no re-baseline, the memory refactor is byte-neutral for the 4 gates. 21-example matrix **21/21** dump/gcc/link rc=0 (4 non-`main.zig` entries use their own names: func_ptr_return/mandelbrot/quicksort/sort_strings). **Corpus sweep 404 dirs (330 mi_matrix + 53 top-level repro + 21 z98, slice_matrix skipped): 0 ASYMMETRIC diffs** (zig1 == zig1_5 behavior everywhere) = **333 RUN_OK** (rc+output match ref; emitted C byte-identical modulo the path-derived std-module hash — ref resolves std from `/tmp/fx_subfolder/lib`, self from `/tmp/zig1_5/lib`, so `std_*.c` names differ but content matches except the self-referential `#include` line) + **56 LINK_FAIL** (extern-fn, identical undefined-reference for the reference — not a regression) + **10 DUMP_FAIL** (= the 10 green-guards, both compilers identical) + **2 RUN_FAIL** (known symmetric crashes: intcast_range_check rc=134, voiddecl_xmodtype_xmod rc=139) + **3 RUN_TIMEOUT** (game_of_life / mud_server / rogue_mud, both compilers; gol glider grid truncated-identical, mud boots) + **1 garbage OUT_DIFF** `emission_void_temp_enum_xmod` (uninitialized enum temp, non-deterministic — NOT a bug). W2-1 fixture `emission_global_alias_xmod` RUN_OK output EQ. **Self-compile:** `build_zig1_5.sh` → dump rc=0, **41 `.c`, 0 `error[`, 0 PANIC**; rebuilt `zig1_5_clean` runs hello **byte-equal** to reference. **Warning-clean both builds:** `gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I sf/src/include -fsyntax-only` on BOTH `/tmp/fx_subfolder/*.c` (reference) AND `/tmp/zig1_5/gen/*.c` (self-emitted) → **0 warnings / 0 errors** each, with the 1 pre-authorized `-Wbuiltin-declaration-mismatch` fwrite carve-out (`/tmp/fx_subfolder/pal.c:41`; self-emitted `/tmp/zig1_5/gen/pal_388A8A1B.c:700` — same fwrite class, not a defect).
- **Post-@as + TCO baseline (GATE-FINAL, 2026-08-26, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `dd83723f`, canonical std reinstalled): @as + TCO self-emission PLAN COMPLETE.** Residuals A+B (the `@as` cast builtin — A: missing fn-ptr typedefs, B: `typeRegistryIsAssignable` SEGV, ONE shared root cause) and C (the TCO self-recursion back-edge) ALL CLOSED. **F-AS `50be26f5`** (ONLY `semantic_analyzer.zig` + `lower.zig`, 8 insertions): `@as` name_id interned + `semanticAnalyzerIsTypeValueCast` recognizes it + the lowerer cast branch emits `int_cast (is_checked=0)` (mirrors the F-ASSOC `@intToEnum` precedent) — fixes the `@as(u32,1)`/`@as(u32,0)` flag read at `c89_emit.zig:736` (non-deterministic `_FP_`/`_FN_` cname per `getCTypeName` call → typedef body and var-decl disagree → gcc `unknown type name 'zT_…_FN_…'` in the 4 fn-ptr GCC_FAIL dirs) AND the `@as(u32,fi)` addend at `type_registry.zig:851-852` (no instruction emitted → uninitialized `xt_items` index → READ SEGV). **F-C `dd83723f`** (ONLY `sf/src/lower.zig`, +8): tagged-union `.tag` field_read case in `field_access` lowering (`load_field { field_id = TU_FIELD_TAG (=0) }`, mirrors the `.payload` sibling + store-side tag pattern) — the reserved-but-never-filled `.tag` slot dropped the TCO back-edge. Corpus 329 dirs = **OK=319 / FAIL=0 / ICE=0 / CRASH=0 / GREEN=10** (319+0+0+0+10=329, unchanged). 4 MD5 gates byte-identical (repo-root CWD): gol `eed963e0…` / lisp `c3c58477…` / json `089e4f04…` / mud `a1d0dd55…` (F-AS/F-C byte-neutral for the 4 gates — no re-baseline). 21-example matrix **21/21** dump/gcc/link rc=0. **Runtime sweep (self-compiled `/tmp/zig1_5/zig1_5_clean` vs reference, 403 programs = repro top-level 53 + mi_matrix 329 + z98 21): 333 RUN_OK** (rc+output == ref) **+ 2 non-deterministic-garbage dirs** (`voiddecl_payload_xmod`, `emission_void_temp_enum_xmod` — output unstable by design, NOT a bug) **+ 10 DUMP_FAIL** (the 10 green-guards, both compilers identical) **+ 56 LINK_FAIL** (extern-fn-dependent; reference fails identically — not a regression) **+ 2 RUN_TIMEOUT** (mud_server + rogue_mud, both compilers; mud_server boots) — **NO NEW FAIL/ICE/CRASH**. Expected-change fixtures ALL RUN_OK with output matching ref: the 6 A-fixtures (`emission_void_call_xmod` + control, `func_ptr_return_type` `15`, `inferred_errorset_fnptr`, `quicksort`, `func_ptr_return` `10+5=15`), `fn_ptr_struct_field` (was SEGV, now rc=0), `tco_return_try` rc=0 (`count(100000)=100000`, was 139), `tco_defer` 2 `D` byte-equal ref, `tco_factorial` unchanged. **Self-compile:** `build_zig1_5.sh` → **40 `.c`, 0 `error[`, 0 PANIC**; rebuilt `zig1_5_clean` runs the R-A/R-B/C fixtures green (`func_ptr_return_type` `15`, `fn_ptr_struct_field` rc=0, `tco_return_try` rc=0), all matching reference.
- **Post-assoc-chain + pending_scope baseline (GATE-FINAL, 2026-08-26, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `0b9c8ef6`, canonical std reinstalled): assoc-chain misparse + pending_scope nest-safety PLAN COMPLETE (AMENDMENT 4).** Residuals R-1 + I-1 BOTH CLOSED: **R-1** (self-compiled zig1_5 reversed left-assoc operator chains) = single-locus `@intToEnum` lowering gap — the cast block at lower.zig:3510-3542 had no `@inttoEnum` branch, so `precFromInt` (parser.zig:1896-1898, the only `@intToEnum` in sf/src) emitted `return zT_1;` (uninitialized temp) → garbage `next_min` in the precedence-climb → right-nesting. F-ASSOC `9574208d` (only `sf/src/lower.zig`, 9 insertions): new `inttoenum_name_id` + `int_cast (is_checked=0)` branch → `zT_1 = (zT_2B10107F_Prec)v;`. Self-compiled `/tmp/zig1_5/zig1_5_clean` now prints the R-ASSOC fixture `emission_assoc_chain_xmod` as **`3 5 0 6 24 55 321`** (was `9 2\0 0 6 2\0 5\0 3\0\0`), matching reference. **I-1** (`pending_scope` single-slot not nest-safe — capture inside a for-range END expr orphaned the loop capture to a `load_local` fallback) = AMENDMENT-4 option (c) reorder: the for-range capture-add (`maybeDisambiguateCapture` + `addLocalDecl` + `decl_local`) moved AFTER the end-expr lower (`lower.zig:4821-4823`), eliminating the pending-scope window entirely (no stack/selector/low-watermark; the patchy LIFO-stack design REJECTED). I-1 repro emits `total + t` direct capture use; the capture-less end-expr shape fixed too. Corpus 329 dirs = **OK=319 / FAIL=0 / ICE=0 / CRASH=0 / GREEN=10** (319+0+0+0+10=329; 328 + this plan's R fixture `emission_assoc_chain_xmod` 40485a1d, classifies OK). 4 MD5 gates byte-identical (repo-root CWD): gol `eed963e0…` / lisp `c3c58477…` / json `089e4f04…` / mud `a1d0dd55…` — the F-PENDSCOPE reorder is byte-neutral (gol/lisp/mud have no for-loops; json uses for-slice only). 21-example matrix **21/21** dump/gcc/link rc=0. Self-compile re-count (`--markers --dump-c89 --output-dir /tmp/gf_sc sf/src/main.zig`) → rc=0, **40 `.c`, 0 `error[`, 0 PANIC**. Self-compiled binary end-to-end: R-ASSOC fixture prints `3 5 0 6 24 55 321` AND std-importing `emission_lower_crash_xmod` rc=0 prints 3.
- **Post-labeled-break + self-compile-crash baseline (GATE-FINAL, 2026-08-26, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `a7a207f7`, canonical std reinstalled): labeled-block break + self-compiled lowering crash PLAN COMPLETE (AMENDMENTs 1-3).** Corpus 328 dirs = **OK=318 / FAIL=0 / ICE=0 / CRASH=0 / GREEN=10** (318+0+0+0+10=328; 323 + 4 prior-plan fixtures `emission_enum_switch_xmod` b9bc3f1d + `emission_enum_ext_xmod` f83912f6 + `emission_tu_switch_xmod` ba3f0f70 + `emission_labeled_ctrl_xmod` ac0b7e43 + this plan's B1 `emission_lower_crash_xmod` 22e0bc6f — all classify OK). **Phase A — labeled-block break CLOSED (A2 F-LABELBREAK `ee092e3b`):** `break :blk` on a labeled block resolves to a block-exit jump (was silently dropped; LoopInfo `is_loop:u8`, labeled_stmt block body pushes a breakable loop_stack entry, continue skips `is_loop==0`); fixture `emission_labeled_ctrl_xmod` prints `3\n6\n10\n1`; orelse/catch labeled fixtures still RUN (0/7) with an accepted AMENDMENT-1 dead orphan `z_bb_N` block (runtime-identical). **Phase B — self-compiled lowering crash CLOSED:** B3a F-EMITMAP `ea6882ac` (growable `fl_temps`/`fl_name_ids`, caps dropped, name-dedup removed — **F2 crash CLOSED**, self-compiled zig1_5 runs B1 fixture rc=0 prints 3) + B3b F-SCOPERES `a7a207f7` (architectural lexical scope chain replacing the LDS max-scope loop + `findLocalTemp` — **F1 CLOSED**). **gol/lisp MD5 RE-BASELINED (AMENDMENT 3, ruling A, AUTHORITATIVE):** gol `4afb203f…` → `eed963e0640a073ed4eebb292f136e05`, lisp `5f886646…` → `c3c5847798e4553b2e34950e085bb6c6` (dedup-removal changes bytes for re-declared names; runtime-identical verified gol glider + lisp REPL); json `089e4f04…` + mud `a1d0dd55…` UNCHANGED. 4 MD5 gates byte-identical at the new hashes (repo-root CWD). 21-example matrix **21/21** dump/gcc/link rc=0. **Self-compile gcc-CLEAN + binary RUNS std-importing programs rc=0** (build_zig1_5.sh → 40 `.c`, 0 gcc errors; B1 fixture rc=0 prints 3; `days_in_month` output byte-identical to reference). **Recorded residuals (NOT fixed):** (1) self-emission operator-associativity gap — self-compiled zig1_5 mis-parses same-precedence left-assoc chains (`a-b-c` → `a-(b-c)`, `a/b/c` → `a/(b/c)`), breaking `printInt` digit reversal (fibonacci prints `5\0` not `55`, rc=0); pre-existing — self-compile emission byte-identical between `ee092e3b` and `a7a207f7` (all 40 modules diff-clean), same deferred fidelity-gap class as the out-of-scope closeout residual; (2) I-1 `pending_scope` single-slot non-nest-safety (for-range END capture orphaning — runtime correct, no gate/corpus trigger). Forward-pointer: historical gol rows referencing `4afb203f…` / lisp rows referencing `5f886646…` now point to the AMENDMENT-3 re-baselined values.
- **Out-of-scope residual closeout — Phase 5 progress (2026-08-24, mid-plan; final reconciliation lands at GATE-FINAL):** corpus 323 dirs now `OK=313 FAIL=0 ICE=0 CRASH=0 GREEN=10`. FAIL=9→0: plat_stubs CRASH→OK (F-PLATSTUBS `7d1b512d`), orelse/catch labeled-stmt →OK (F-LABELED `2cbf1fd3`), `emission_opt_fptr_wrap_xmod` added+OK (F-OPTFPTR `53b9f1b6`), `parsergap_specifier_xmod` {x}-hex →OK (F-SPECIFIER `a9ea91f0`), `strictzig_brace_if_xmod`/`parsergap_selfblok_xmod`/`parsergap_strict_comma_xmod`/`parsergap_slice_expr_xmod` → green-guards (reclassified). **`field_store_drop` →OK (operator-directed fixture correction `3ef2e8c8`):** its bare `@import("pal")` masked the fixture with `error[3048]`; corrected to `@import("pal.zig")` + bundled `pal.zig` stub (`@stderrWrite`) + `std.io.printInt` sinks (the `__bootstrap_print_int` extern was F4-removed). Now dump/gcc/link/run all rc=0 (stdout `2030`, stderr `OK`); the emitted `store()` shows direct `t.s=s;t.b=b;t.c=c;` — the documented temp-0 sentinel extra-copy symptom is GONE, superseded by later compiler fixes. **`self_embed_optional_cycle` → GREEN-GUARD (AMENDMENT 6):** the plan's old "real Zig accepts `next: ?X`" oracle was WRONG — real Zig rejects an optional-VALUE self-reference (infinite size) and the canonical self-reference pattern is `?*X` optional POINTER (pointer-sized, null=0; langref linked-list example `prev: ?*Node, next: ?*Node`). Z98's `error[24]` rejection is therefore CORRECT (green-guard). Remaining FAIL=0. 4 MD5 gates byte-identical at json `089e4f04…` (AMENDMENT 4 re-baseline).
- **Post-R2R1-closeout baseline (GATE gate sweep, 2026-08-24, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `0af060d8`, canonical std reinstalled): MAJOR MILESTONE — self-compile gcc-CLEAN (12→0).** The 12 residuals are ALL closed: **F-R2** `143766e2` (array-`.len`→VOID ×6), **F-ORELSEBLK** `7a7f5928` (orelse-block terminator ×5), **F-R1** `a8ec24f7` (Opt_10 assign ×1), plus **F-ACOPY** `0af060d8` (array-copy direct-assign, the AMENDMENT-1 live RED — `emission_misc_xmod` now GREEN). Re-count: `bash scripts/self_compile/build_zig1_5.sh` → dump rc=0, 40 `.c`, in-script gcc -c clean; independent `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2>/tmp/emit_errs_final.txt` → **0 error lines, 40 files** (final link `undefined reference to 'c_exit'` = pre-existing out-of-scope build_zig1_5.sh issue; the gcc -c re-count is the authority). **Corpus 322 dirs: `OK=307 FAIL=9 CRASH=1 ICE=0 GREEN=5`** (307+9+1+5=322; 310 + 10 A-ADD `emission_*_xmod` + the 2 R-task dirs `emission_temp_index_drift_xmod`/`emission_opt10_assign_xmod`). FAIL=9 = documented 7 (`field_store_drop` / `self_embed_optional_cycle` / `parsergap_selfblok_xmod` / `parsergap_slice_expr_xmod` / `parsergap_specifier_xmod` / `parsergap_strict_comma_xmod` / `strictzig_brace_if_xmod` [M1 hard-RED, FAIL by design]) + `emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod` (A-ADD live-RED labeled-stmt classes, out-of-scope live bugs — F-ORELSEBLK Fix A did NOT close them). GREEN=5 = documented 4 (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`) + `emission_pal_xmod` (error[20] reject, pal green-guard per AMENDMENT 1). **CRASH=1 `plat_stubs_missing_xmod` = PRE-EXISTING (mis-recorded previously, now corrected per AMENDMENT 5 `935374d9`):** ASan SEGV `resolveStmtTypes` front_resolution.zig:131, 0 `.c`, dump rc=1; crashes at plan-start HEAD `b9256f2e`, last-known-good ~Aug 18, suspected silent-drop u32-widening `378c71fa`/`50ebbf82` (unverified); prior gate sweeps' "identical rc+stderr" comparisons masked it — no new fix task. 21-example matrix **21/21** dump/gcc/link rc=0. **4 MD5 gates byte-identical (no re-baseline):** gol `4afb203f…` + lisp `5f886646…` (repo-root CWD) + json `d31e43b1…` + mud `a1d0dd55…`. test_analyzer_bin PASS ("5 passed, 4 failed").
- **Post-silent-drop baseline (GATE gate sweep, 2026-08-19, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `50ebbf82`, canonical std reinstalled): `OK=267 FAIL=6 ICE=0 CRASH=0 GREEN=4` over 277 dirs** (267+6+4=277). Corpus grew 266→277 (+3 signed wrap/sat emission probes `sat_i64_mul`/`sat_signed_battery`/`wrap_signed_battery` [commit `13991817`, post-v40-gate] + the 6 R-ladder fixtures `voiddecl_struct_xmod_r1`..`voiddecl_mimic_r6v2` + the 2 boundary repros `voiddecl_boundary_xmod`/`voiddecl_boundary_xmod_err`), all 11 new dirs OK. FAIL=6 set **unchanged** from v40 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` + `parsergap_specifier_xmod` + `parsergap_strict_comma_xmod` + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`). **I-DROP mechanism isolated + FIXED by F1** (u16→u32 whole-class sweep, commits `378c71fa` + `50ebbf82`, order reversed from plan staging — operator accepted): `AstNode.payload` u64 `(start<<32)|count`; `error[3000]` **213x→9**; modules 1-4 register cleanly (`RN:m1`-`RN:m4` present). R-ladder (6 fixtures) all GREEN (none below the 65,536-entry boundary trips); both boundary repros GREEN (voiddecl_boundary_xmod prints `1 7`; voiddecl_boundary_xmod_err prints `1`). 21-example matrix **21/21** dump/gcc/link OK (game_of_life + mud_server + rogue_mud timeout-gated rc=124 with correct output — counted PASS; json_parser parses test.json rc=0 from its dir). 4 MD5 gates byte-identical: gol `9cf758d9…` [→ `4afb203f…`], lisp `88dcb7f9…` [→ `5f886646…`] (repo-root CWD), json `fc357296…` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55…`. test_analyzer_bin PASS ("5 passed, 4 failed"). **True remaining pre-existing blocker (recorded, out of scope): 9 `error[3000] cannot-declare-variable-of-type-void` sema errors** (VOID-decl family, same class as the `var_declared_void` green-guard: main.zig:588, symbol_registrator:258/:357, lower.zig:4410/:5218/:5275/:5319/:5395/:5403) — next blocker = the VOID-decl family (9 sites).
- **Post-self-compile-gaps baseline (GATE gate sweep, 2026-08-18, measured with /tmp/fx_subfolder/zig1, HEAD `3079df02`, canonical std reinstalled): `OK=256 FAIL=6 ICE=0 CRASH=0 GREEN=4` over 266 dirs** (256+6+4=266). FAIL=6 set **unchanged** from v39 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` + `parsergap_specifier_xmod` + `parsergap_strict_comma_xmod` + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`). Corpus grew 264→266 (R1 `parsergap_wrap_arith_xmod` + R3 `parsergap_switch_comma_xmod`), both RED→OK (F1 wrap/sat operator family, F3 switch-prong value-less return) — OK=254→256, FAIL=6 unmoved, **no regression**. 21-example matrix **21/21** dump/gcc/link OK (mud_server rc=124 timeout-gated; rogue_mud boots + exits; json_parser parses test.json rc=0 from its dir). 4 MD5 gates byte-identical: gol `9cf758d9…` [→ `4afb203f…`], lisp `88dcb7f9…` [→ `5f886646…`] (repo-root CWD), json `fc357296…` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55…`. test_analyzer_bin PASS ("5 passed, 4 failed"). Self-compile re-check: all 3 plan constructs pass — 0 `util/hash.zig:18` `*%` hits, 0 `c89_emit.zig:1881` hits, 0 `lexer.zig` value-less-return hits. **True remaining pre-existing blocker (recorded, out of scope): 210 `error[3000] cannot-declare-variable-of-type-void` sema errors** (VOID-decl family; the F3-suspected lexer.zig error[3043] ICE is NOT reproduced — 0 ICE-class hits).
- **Post-strict-zig-if baseline (GATE gate sweep, 2026-08-18, measured with /tmp/fx_subfolder/zig1, rebuilt at HEAD `1585adf2`, canonical std reinstalled): `OK=254 FAIL=6 ICE=0 CRASH=0 GREEN=4` over 264 dirs** (254+6+4=264). Real FAIL=6 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` + `parsergap_specifier_xmod` + `parsergap_strict_comma_xmod` (the plan's expected FAIL=5, unchanged) + `strictzig_brace_if_xmod` (the M1 hard-RED fixture, FAIL **by design**). Corpus grew 258→264 (5 followup parsergap dirs + the M1 fixture). 21-example matrix **21/21** dump/gcc/link OK (mud_server rc=124 timeout-gated; rogue_mud boots + exits). 4 MD5 gates byte-identical: gol `9cf758d9…` [→ `4afb203f…`], lisp `88dcb7f9…` [→ `5f886646…`] (repo-root CWD), json `fc357296…` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55…`. test_analyzer_bin PASS. Self-compile re-check passes the M2 blockers (type_resolver.zig:981/:987-990 — 0 hits) AND the M4-fix 4th site (`sf/src/c89_emit.zig:410-412` — 0 hits); a tree-wide `;`-before-`else` scan proves ZERO same-class sites remain in sf/src. **True remaining pre-existing blockers (ALL recorded, ALL out of scope):** (1) `util/hash.zig:18:21` — `*%` saturating-mul, error[2000]; (2) `c89_emit.zig:1881-1882` — unterminated string literal on a line-split string, error[0] (+cascades 1939); (3) `lexer.zig:236-239` — error[2000] expected-expression/unexpected-token report sites. (The v37 "sole next blocker = hash.zig:18" claim was FALSE — the filtered stderr showed all of the above; corrected 2026-08-18 M4-fix.)
- **Post-parser-gaps baseline (GATE gate sweep, 2026-08-17, measured with /tmp/fx_subfolder/zig1, HEAD `830c5691`): `OK=252 FAIL=2 ICE=0 CRASH=0 GREEN=4` over 258 dirs** (252+2+4=258). FAIL=2 unchanged = `field_store_drop` + `self_embed_optional_cycle`; green-guards unchanged. Corpus grew 252→258 (the 3 parsergap fixtures + `parsergap_value_if_xmod` + `parsergap_value_if_xmod_cross` + `pathnorm_dup_xmod`), all 6 new dirs OK; the 3 previously-deferred parsergap repros (`discard_if` / `array_type` / `trailing_comma`) are now **OK** (A-F1/A-F2/A-F3). 21-example matrix **21/21** dump/gcc/link OK (mud_server rc=124 timeout-gated; rogue_mud boots + exits). 4 MD5 gates byte-identical (gol `9cf758d9…` [→ `4afb203f…`], lisp `524d2872…`, json `fc357296…` [B-F2 re-baseline; → `9720478c…` F1 re-baselined 2026-08-19], mud `a1d0dd55…`). test_analyzer_bin PASS ("5 passed, 4 failed"). Self-compile re-check passes the pre-fix blockers (cinclude.zig:23 / lower.zig:2283 / main.zig:759) and now hits a NEW pre-existing gap at `type_resolver.zig:981` (const-array-size evaluator) — recorded, out of scope.
- **Post-fallback-demotion baseline (F-CLOSEOUT fallback-demotion gate sweep, 2026-08-14, measured with /tmp/fx_subfolder/zig1, HEAD `5c1e17e4`): `OK=246 FAIL=2 ICE=0 CRASH=0 GREEN=4` over 252 dirs** (246+2+4=252). FAIL=2 = `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental, `error[24]` circular type). The 4 `r_fallback_*` repros (fnret / constalias / constalias_prepass / control) are the new dirs — 3 RED→GREEN + 1 control, all OK (bare-key/module-0-key collision fixed across 4 sites: type_resolver / symbol_registrator / const_alias_prepass / semantic_analyzer). The 4 green-guards counted separately. 21-example matrix **21/21** dump/gcc/link OK (mud_server rc=124 timeout-gated; rogue_mud boots + exits). 4 MD5 gates byte-identical (gol `9cf758d9…` [→ `4afb203f…`], lisp `524d2872…`, json `066c9997…` [B-F2 re-baselined 2026-08-17 → `fc357296…`; → `9720478c…` F1 re-baselined 2026-08-19], mud `a1d0dd55…`, unchanged from F3 AMENDMENT B except json). test_analyzer_bin PASS.
- **Post-closeout baseline (F-CLOSEOUT gate sweep, 2026-08-14, measured with /tmp/fx_subfolder/zig1, HEAD `c5856928`): `OK=242 FAIL=2 ICE=0 CRASH=0 GREEN=4` over 248 dirs** (242+2+4=248). FAIL=2 = `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental, `error[24]` circular type). `arena_multi_inst_xmod` is the 248th dir (new RED→OK — the D2 fix). The 4 green-guards counted separately. 21-example matrix **21/21** dump/gcc/link OK (mud_server rc=124 timeout-gated; rogue_mud boots + exits). 4 MD5 gates byte-identical (gol `9cf758d9…` [→ `4afb203f…`], lisp `524d2872…`, json `066c9997…` [B-F2 re-baselined 2026-08-17 → `fc357296…`; → `9720478c…` F1 re-baselined 2026-08-19], mud `a1d0dd55…`, F3 AMENDMENT B re-baseline except json). test_analyzer_bin PASS.
- **Post-search-path baseline (F-MIGRATE/F-GATE gate sweep, 2026-08-14, measured with /tmp/fx_subfolder/zig1, HEAD `51fa4342`): `OK=241 FAIL=2 ICE=0 CRASH=0 GREEN=4` over 247 dirs** (241+2+4=247). FAIL=2 = `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental). `test_stub_0` + `std_import_bare_xmod` moved FAIL→OK (bare `@import("std")` now resolves via the search path). The 4 green-guards counted separately. 21-example matrix **21/21** dump/gcc/link OK (mud_server rc=124 timeout-gated; rogue_mud boots + exits). 4 MD5 gates byte-identical (gol `40749460…`, lisp `b71a0e0c…`, json `b47f9498…`, mud `447c491b…`, runtime-identical per AMENDMENT B). test_analyzer_bin PASS.
- **Post-lisp-defects-plan baseline (F3 gate sweep / closeout, 2026-08-13, measured with /tmp/fx_subfolder/zig1, HEAD `31de6800`): `OK=239 FAIL=3 ICE=0 CRASH=0 GREEN=4` over 246 dirs** (239+3+4=246). FAIL=3 = `field_store_drop` + `test_stub_0` (std-lib-deferred, `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental). The 4 green-guards counted separately. No new FAIL vs the F7 sweep; the 6 plan repro dirs (`union_literal_nested_xmod`, `global_null_init_xmod`, `nested_field_store_xmod`, `nested_field_store_xmod2`, `sizeof_struct_union_xmod`, `union_emission_layout_xmod`) all classify OK. 21-example matrix **21/21 end-to-end** — lisp_interpreter is now dump/gcc/link/run rc=0 AND functionally correct (evaluates `nil`/`true`/`+`/`(quote 5)`/`cons`; Defects A-E fixed); json_parser_workaround run rc=0 (no SEGFAULT); mud_server boots + responds (server, timeout-gated). 4 MD5 gates byte-identical (gol `ff47d18d…`, lisp `c1cb748b…`, json `376fd681…`, mud `fd0fdaa4…`). test_analyzer_bin PASS.
- **Post-std-lib-plan baseline (F7 gate sweep, 2026-08-13, measured with /tmp/fx_subfolder/zig1): `OK=233 FAIL=3 ICE=0 CRASH=0 GREEN=4` over 240 dirs** (233+3+4=240). FAIL=3 = `field_store_drop` + `test_stub_0` (std-lib-deferred, `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental). The 4 green-guards counted separately. No new FAIL vs the F6 sweep. 21-example matrix **20/21 end-to-end** (lisp_interpreter is the sole gcc-FAIL — pre-existing builtins.zig `zT_N` lowerer defect); mud_server boots (server, timeout-gated). 4 MD5 gates byte-identical (mud `fd0fdaa4…` re-baselined post-F6-review). test_analyzer_bin PASS.
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
   **Varargs feature (4-item plan F3-F5/F5b, 2026-08-06):** `...` in fn params (parser.zig:1375-1382
   sets `flags` bit0 → `FnPayload.flags_packed`; `...` in fn-pointer types rejected), `va_list`
   primitive (`TYPE_VA_LIST`=21, type_registry.zig:600), LIR `va_start`/`va_arg`/`va_end`
   (lir.zig:46-48) + C emission (`va_start(vl, last);` / `res = va_arg(vl, T);` / `va_end(vl);`),
   `#include <stdarg.h>` gated on actual `va_*` insts (moduleHasVaInsts, c89_emit.zig:1938),
   variadic externs get C prototypes (Option B, `is_extern==0 OR is_variadic!=0`), `@cVaStart` in a
   non-variadic fn → `error[3012]`. `fn_varargs_unsupported` **FAIL→OK** (runs `printf`),
   `fn_varargs_body` new OK — `sum(3,10,20,30)` → **`sum=60`**. Commits `4448d187`..`ef529f42`; see
   EXPECTED_FAIL.md Task F5 section. [updated: 2026-08-06]
   **Lisp closures (F6, commit `0cb7891c`):** `eval.zig:124` `env_to_value(env.*,…)` →
   `curr_env.*`; `((make-adder 5) 3)`→8, `((add 10) 1)`→11, `((make-func 42))`→42 (were
   `UnboundSymbol`). Composition (`((twice square) 3)`, `((compose square square) 3)`) now
   **SEGFAULTS** — lisp-source env-capture cycle (live `define`-slot pointers back-patched after
   capture), NOT a compiler defect. `(fact 13)` PANICS (`integer cast overflow in @intCast`, rc=134)
   — the intended F1 range-check. [updated: 2026-08-06]
   **Final accounting (F7 gate sweep, 2026-08-06): effective `OK=202 / FAIL=3 / green-guards=4`
   over 209 repros** (202+3+4=209; raw classifier FAIL = 7 — the 4 green-guards are a sub-bucket);
   the 3 FAILs = `field_store_drop` + `test_stub_0` (std-lib-deferred) +
   `self_embed_optional_cycle` (F-8 residual); **4 MD5 gates byte-identical** to the baselines
   below (no re-baseline); the plan's "210 repros / OK=200" prediction double-counted
   `fn_varargs_unsupported`. [updated: 2026-08-06]
   **Labeled statement support (F1, 2026-08-07): effective `OK=203 / FAIL=3 / green-guards=4`
   over 210 repros** (203+3+4=210; raw classifier FAIL stays 7 — the 4 green-guards are a
   sub-bucket). `labeled_stmt_unhandled` **FAIL→OK** (labeled statements now supported in
   parser/sema/lowerer; the labeled `break :game_loop` no longer hangs). The 3 FAILs unchanged =
   `field_store_drop` + `test_stub_0` (std-lib-deferred) + `self_embed_optional_cycle`
   (C89 fundamental). **4 MD5 gates byte-identical** (no re-baseline). [updated: 2026-08-07]
    **rogue_mud emission-defects plan closeout (F5 gate sweep, 2026-08-07): effective
    `OK=208 / FAIL=3 / green-guards=4` over 215 repros** (208+3+4=215; raw classifier FAIL stays
    7 — the 4 green-guards are a sub-bucket; the classifier counts 216 dirs because
    `opt_slice_null_return` is OK-by-gate/type-incorrect and tracked separately). The 5 gap repros
    (`dup_optptr_field_emit`, `dup_val_field_emit`, `undef_arr_struct_literal`,
    `xmod_pub_const_global`, `switch_mixed_case_argtype`) all **FAIL→OK** via F1-F4 (commits
    a5ac4598, ba89a6e0, 317f3a82, b1b3f7e9). The 3 FAILs unchanged = `field_store_drop` +
    `test_stub_0` (std-lib-deferred) + `self_embed_optional_cycle` (C89 fundamental). **4 MD5
    gates byte-identical** (no re-baseline in F5; mud was re-baselined in F2 to
    `906fa59c…` — see the MD5 table). Out-of-scope follow-up: char_literal switch `case` labels
    dropped (lower.zig:3858-3860/:3121-3123) (refs superseded — actual sites lower.zig:3183 expr / :3920 stmt). [updated: 2026-08-07]
    **char_literal switch + opt_slice null repro battery (gate sweep, 2026-08-07): effective
    `OK=223 / FAIL=3 / green-guards=4` over 230 repros** (223+3+4=230; the classifier counts 231
    dirs because `opt_slice_null_return` is OK-by-gate/type-incorrect and tracked separately).
    Corpus grew 216 → 231 dirs by **15 new repros**, ALL classifying **OK** under the gcc-exit
    gate: **12 char_literal switch-case repros are OK-by-compile / RUNTIME-GAP-TRACKED** — they
    compile clean but print wrong runtime output (char switch `case` labels dropped at
    lower.zig:3183 expr / :3920 stmt — every input takes `else`), tracked separately, NOT added
    to FAIL (mirrors `comptime_neg_int` / `opt_slice_null_return`); **3 opt_slice null-payload
    repros are OK-by-gate / LATENT** (`catch return null` in a `?[]T` fn emits an `int`-typed
    null-payload temp — gcc-clean warning-only, breaks only under strict typing). The 3 FAILs and
    4 green-guards UNCHANGED: `field_store_drop` + `test_stub_0` (std-lib-deferred) +
    `self_embed_optional_cycle` (C89 fundamental); `eu_assign_incompat_payload`,
    `field_access_optional`, `var_declared_void`, `euvoid_val_catch`. **4 MD5 gates byte-identical**
    (mud `906fa59c…`, gol `0d8f0092…`, lisp `605b597e…`, json `b5f56ebd…`). See EXPECTED_FAIL.md
    "char_literal switch-case repro battery" + "opt_slice null-payload repro battery" sections.
    Out-of-scope follow-up (updated): the 12 `switch_char_*` repro dirs + the 3 `opt_slice_null_*`
    dirs gate the two post-plan fixes. [updated: 2026-08-07]
    **[updated: 2026-08-07 — char_literal switch + opt_slice null fixes]: effective `OK=223 /
    FAIL=3 / green-guards=4` over 230 repros** (223+3+4=230; classifier counts 231 dirs because
    `opt_slice_null_return` is OK-by-gate/type-incorrect and tracked separately). The 15 battery
    repros are now **fully OK** (F4 gate sweep, F1 `e0a4d6d6` + F2 `5c515a7d` landed): the 12
    `switch_char_*` repros are **no longer runtime-gap-tracked** — F1 emits real `case 'a':`
    labels (lower.zig:3229 expr / :3968 stmt), all 12 print their expected post-fix output
    (`120`, `1120`, `19`, `1`, `109`, …; run-verified); the 3 `opt_slice_null*` repros are **no
    longer latent** — F2 (Option B) drops the dead `int zT_N; zT_N = NULL;` payload temp, 0
    `-Wint-conversion` warnings (was 2/2/3), 0 `= NULL;` sites, still print `1`. FAIL=3 and
    green-guards=4 UNCHANGED. **4 MD5 gates: gol byte-identical `0d8f0092…`; mud/lisp/json
    RE-BASELINED by F2** (mud `6c0a83f1…`, lisp `fad41183…`, json `c403f079…` — full hashes in
    the MD5 table). test_analyzer_bin PASS.
- **F4 std-lib deferral (2026-08-08, docs-only):** the D4 platform-stub gap — the **5 `plat_`
  console/platform-detect stubs** (`plat_is_windows`, `plat_console_gotoxy`,
  `plat_console_setcolor`, `plat_console_putchar`, `plat_console_clear`, all rogue_mud-only;
  declared in `examples/z98/rogue_mud/ui.zig`) missing from ALL runtime files — is a
  **runtime-library gap, NOT a compiler defect** (zig0 fails identically, same undefined-ref
  link rc=1). **Deferred to the std-zig1 library plan — NOT fixed here.** Counts UNCHANGED:
  effective `OK=223 / FAIL=3 / green-guards=4` over 230 (raw classifier FAIL stays 7);
  `plat_stubs_missing_xmod` tracked OK-by-gate/latent like `opt_slice_null_return` /
  `extern_runtime_symbol_xmod`. **rogue_mud remains blocked at link** on exactly these 5
  stubs (20 modules emit, gcc compile rc=0, both single- and multi-module recipes). See
  EXPECTED_FAIL.md F4 section.
- **Multi-module fixes plan closeout (F7 gate sweep, 2026-08-08): effective `OK=223 / FAIL=3 /
  green-guards=4 / ICE=0 / CRASH=0` over 230 manifest repros** (223+3+4=230). Full sweep of
  **all 237 dirs** (230 manifest + 7 tracked-separately: `opt_slice_null_return` + the 6
  plan-added repros) classifies **OK=229 / FAIL=8 / ICE=0 / CRASH=0** (229+8=237) — the 4
  green-guards are the difference vs the manifest count, plus `tagged_union_cmp_xmod` counts
  FAIL on the latent union-`==` emission (was the F3 sweep's ICE=1; F6 SEGV fix → CRASH=0).
  **No new corpus FAIL introduced by this plan.** Fixes landed: F1 `51bfdb3c` @ptrToInt
  (`ptr_to_int_void_xmod` OK, lisp_interpreter unblocked at dump), F3 `021ffcfd` cross-module
  enum member (`zT_missing_fwd_xmod` OK, json_parser_workaround **gcc-clean** — was 6× zT_xx
  compile FAIL), F5 `462ddee4` arena resize (perm 4M/mod 8M/scr 2M; self-compile scratch OOM
  documented as future investigation, NOT a corpus regression), F6 `efbf4807` tagged-union
  member access (SEGV gone, CRASH→0). Deferred (NOT fixed): D2 `arena_alloc_default`
  (json_parser + json_parser_workaround link blocked, std-lib-deferred), D4 `plat_*` stubs
  (rogue_mud link blocked, std-lib-deferred). Follow-ups: union `==` emission, TU payload-read
  lowering, lisp builtins `zT_N` (lisp_interpreter gcc FAIL, pre-existing lowerer defect
  surfaced post-F1 — **RESOLVED by the lisp_defects plan F1-F6, 2026-08-13**; lisp_interpreter
  is now dump/gcc/link/run rc=0 and functionally correct), scratch-arena optimization.
  **4 MD5 gates byte-identical** to the
  post-F1 baselines at that sweep (mud `6c0a83f1…`, gol `0d8f0092…`, lisp `a12f2fce…`, json
  `c403f079…`); test_analyzer_bin PASS. Full 21-example matrix: **16/21 end-to-end working**
  (unchanged vs MEM4) — see EXPECTED_FAIL.md F7 section. **[F3 2026-08-08: D2 arena gap CLOSED
  via the `std_arena.zig` module (json_parser + json_parser_workaround + extern_runtime_symbol_xmod
  link+run rc=0 on the standard sf runtime; json MD5 re-baselined to `ff9b880c…`). 21-example
  matrix now 18/21 end-to-end. See EXPECTED_FAIL.md F3 section.]**

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

| Entry Path | Reference md5 | [updated: 2026-09-02 — spill backend config GATE: table refreshed to the AUTHORITATIVE hashes (established by the memory-refactor plan; re-verified byte-identical at `-s0`..`-s5` by the spill-config GATE, no re-baseline). Historical rows below record the older values and their re-baselines.] |
|---|---|---|
| `examples/z98/mud_server/main.zig` | `53405b3be5bbc5e0f8c9aaba69c8fb6d` |
| `examples/z98/game_of_life/main.zig` | `302df36be57e9876549d6a8b4031bf95` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `3591bad9726ca0947eae3f8a9a6e7273` |
| `examples/z98/json_parser/main.zig` | `76056b978f6330c8af0c7f23b3244135` |

- **mud re-baseline (2026-09-03, SWEXPR `6d71b917` + F-STORE-DROP `f014259b` fixes, operator ruling):** the
  switch-expr capture-placement fix and the store-drop C4-helper fix (global array-element stores —
  `c89_emit.zig` assign_index base liveness) both legitimately change mud_server emission (mud was a
  broken sample pre-fix: `initRooms` never populated the world). Runtime verified vs the zig0 oracle: the
  rebuilt mud_server replies to `north` from start with `A sunny clearing. Exits: south back to forest.`
  (movement now works). mud old→new: `4591fef0346b42738874ce992c72f4c2` →
  `53405b3be5bbc5e0f8c9aaba69c8fb6d` (the table row above is the CURRENT value). gol/lisp/json UNCHANGED
  (byte-identical `302df36b…` / `3591bad9…` / `76056b97…` — no re-baseline).

- **Labeled-break plan B3a gol/lisp re-baseline (2026-08-26, F-EMITMAP fix, operator ruling A):** the
  growable `fl_temps` map (`c89_emit.zig`, commit ea6882ac) removes the name-dedup so each `decl_local`
  registers its own temp→name entry (capture shadowing). gol's `main` re-declares `var x` in two sibling
  while-loops and lisp re-uses capture names, so their emitted bytes change (2nd `x` now resolves to mangled
  `x` instead of raw `zT_274`). Runtime-identical VERIFIED (gol glider grid + lisp REPL outputs diff-clean
  pristine-vs-candidate, both rc=0). json/mud UNCHANGED. Operator approved re-baseline (plan AMENDMENT 3,
  option A). gol old→new: `4afb203fdde7a880ec6e7aed32543691` → `eed963e0640a073ed4eebb292f136e05`;
  lisp old→new: `5f886646b164a70c52bf042eb54bda78` → `c3c5847798e4553b2e34950e085bb6c6`. This fix also
  closes the **self-compiled zig1_5 lowering SEGV** (F2): captures beyond the old `[128]` cap no longer
  strand the value in a temp (self-compiled binary now runs the B1 fixture `emission_lower_crash_xmod`
  rc=0, prints 3).

- **Out-of-scope residual closeout json re-baseline (2026-08-24, NULLWRAP fix, operator ruling):** the
  `.call_direct` need_wrap path now emits `result.has_value = result.value != 0` instead of unconditional
  `1` for optional-wrapped extern-call results (`c89_emit.zig`, commit a6fe169b). json_parser wraps
  `fopen(...) ?*File` with `orelse return error.OpenFailed` and had the same latent bug (unconditional
  has_value=1 → NULL file proceeds, latent crash); its emitted C changes. gol/lisp/mud UNCHANGED
  (byte-identical). Runtime-identity: the change is byte-identical on every program's normal path
  (fopen succeeds → has_value=1 either way) and repairs the NULL path (orelse now fires). Operator approved
  the re-baseline (plan AMENDMENT 4). json old→new: `d31e43b19f752e40b9fd4b8885b13600` →
  `089e4f046464ce3882aa2b2c4e585013`. Self-compiled binary: crash FIXED (runs), but a separate pre-existing
  self-emission fidelity gap remains (self-compiled compiler misparses basic operators; recorded as residual,
  deferred).

- **Self-compile residual closeout gol/lisp re-baseline (2026-08-22, runtime-priority override):** the
  documented gol `9cf758d9…` / lisp `88dcb7f9…` baselines predated the F-attempt emission changes (the
  residual plan's F tasks); current HEAD emits gol `4afb203f…` / lisp `5f886646…` (repo-root CWD —
  CWD-sensitive). Runtime-identity justification (operator's runtime-priority rule): gol renders the
  glider grid rc=0 (md5 `40cfee96…` for 100 gen), lisp REPL evaluates `(+ 1 2)`→3 / `(define x 10)` /
  `(+ x 5)`→15 / `(car (quote (5 6)))`→5 rc=0 — both runtime-identical to base, corpus classification
  unchanged. json `9720478c…` + mud `a1d0dd55…` UNCHANGED (byte-identical). Historical
  `9cf758d9…`/`88dcb7f9…` rows get the `[→ 4afb203f…]`/`[→ 5f886646…]` forward-pointer (2026-08-22).

- **voiddecl-family json re-baseline (2026-08-19, AMENDMENT 3, F1 gate — CURRENT baseline):** the F1
  front-resolution pass types json_parser's untyped module `var g_arena = std.arena.create(1048576)`,
  so 5 temp decls in emitted C change `unsigned int` → `Arena*` (void-collapse artifact removal).
  json old→new: `fc357296537347a0ef58af49b5a40081` → `9720478c937409a29fe23ae0199821cf`. Runtime-identity
  proof (AMENDMENT B precedent): fixed binary parses `test.json` rc=0, byte-identical stdout, corpus
  classification unchanged. Prior (stale): json `fc357296…`. Historical rows carrying `fc357296…`/the
  `066c9997…`→`fc357296…` B-F2 re-baseline get the `→ 9720478c…` forward-pointer.

- **B-F2 re-baseline (2026-08-17, AMENDMENT B runtime-identity):** the for-loop INDEX capture fix
  (Site A, `sf/src/lower.zig` — index capture now runs through `maybeDisambiguateCapture` like the
  element capture) changes json_parser's emitted C ONLY: the `.Object` loop counter is now a
  disambiguated `i_2` decl and the comma condition reads `i_2 < obj.len - 1` (was the stale `.Array`
  counter `i`). json old→new: `066c99974f6052317636854dc4c2a2d5` → `fc357296537347a0ef58af49b5a40081`.
  gol/lisp/mud byte-identical (no for-index collision). Runtime-identity proof: fixed binary parses
  `test.json` rc=0 with object fields comma-separated (`"status": "alpha",` / `"bugs": null`) and NO
  trailing comma after the last field — the pre-fix output had no object-field commas and a trailing
  `,` after `"meta"`. Prior (stale): json `066c9997…`.

- **F3 re-baseline (2026-08-14, commit `a55c65e2`, AMENDMENT B runtime-identity):** the `printInt`
  INT_MIN fix changes the emitted `printInt` body in *every* `std.io` importer (the C89 emitter
  has no dead-code elimination), so all 4 gate MD5s move. Runtime output is byte-identical —
  gol glider md5 `fcbf7e7c…` (100 generations, rc=0), lisp evaluates `nil`/`true`/`+`/
  `(quote 5)`/`cons` correctly (rc=0), json parses `test.json` rc=0, mud "MUD server listening
  on port 4000" rc=124 (timeout-gated server, NOT a hard gate). Prior values (stale): mud
  `447c491b…`, gol `40749460…`, lisp `b71a0e0c…`, json `b47f9498…`.

- **F-MIGRATE gate sweep / closeout (2026-08-14): all 4 re-baselined** (bare `@import("std")`
  resolves through the search path to the canonical `sf/src/std*.zig` installed at
  `<exe_dir>/lib`; `std_io.zig` `print` is now variadic `(s: [*]const c_char, ...)` so the
  enhanced print lowering still interpolates `{}`/`{c}`/`{s}`). Runtime-identical per AMENDMENT B:
  gol glider md5 `fcbf7e7c…` (grid renders, "Generation: N" interpolated), lisp REPL output diff
  empty, json parse output diff empty, mud "MUD server listening on port 4000" rc=124 — all
  byte-identical to the pre-migration outputs. Pre-migration values (stale): mud
  `fd0fdaa4…`, gol `ff47d18d…`, lisp `c1cb748b…`, json `376fd681…`.
- **F3 gate sweep / closeout (2026-08-13): all 4 re-verified byte-identical** to these values
  with `/tmp/fx_subfolder/zig1` (HEAD `31de6800`). gol/lisp/json were re-baselined by the
  lisp_defects plan F2 (operator ruling m0809 — module-scope int-literal coercion now recorded,
  runtime byte-identical); mud is NOT an MD5 gate per the operator. **21-example matrix 21/21
  end-to-end** — lisp_interpreter dump/gcc/link/run rc=0 AND functionally correct;
  json_parser_workaround run rc=0 (no SEGFAULT); test_analyzer_bin PASS; corpus
  OK=239 FAIL=3 ICE=0 CRASH=0 GREEN=4 over 246 dirs (no new FAIL). [updated: 2026-08-13]

- **Re-baselined 2026-08-13 (F6, networking builtins).** mud re-baselined because F6 replaces
  mud_server's 12 `plat_*` socket externs + `plat_fd_set` with `std_net` calls (local
  `std_net.zig` copy); `net_runtime.c` link REMOVED for migrated examples (mud_server +
  rogue_mud) — the F6 builtin-emitted socket C replaces it. Runtime output byte-identical to
  pre-F6 (verified by client-interaction diff: welcome + look/north responses identical; the
  "north → You cannot go that way." quirk is pre-existing). mud_server is NOT an MD5 gate per
  the operator. gol/lisp/json byte-identical. Pre-F6 mud value: `ecd40869…`. F6 gate:
  net_builtin_test dump→gcc→run rc=0 prints `1` WITHOUT net_runtime.c; mud_server
  timeout-gated socket interaction rc=0; rogue_mud dump/gcc/link rc=0 (0 `plat_*`
  refs); corpus OK=233 FAIL=3 ICE=0 CRASH=0 GREEN=4 over 240 dirs (no new FAIL).
  [updated: 2026-08-13]
- **Re-baselined 2026-08-13 (F6 REVIEW, null-coalesce optional socket ptr args).** mud
  re-baselined AGAIN because the F6 review fix (commit `25fb7ce1`, `emitSocketOptPtrValue`)
  changes the emitted `select` call — optional-typed fd args now emit
  `(NAME.has_value ? NAME.value : NULL)` instead of a bare `.value` deref (mirrors
  `.unwrap_optional_abi`; Valgrind-confirmed the pre-fix `.value` read was UB on
  uninit payloads). New mud value: `fd0fdaa42a419b0e72cfdb3226a54c4a` (the whitespace-stripped
  diff vs the `3abbcd5c…` baseline is exactly ONE line). Runtime output unchanged (verified by
  client interaction). gol/lisp/json unaffected (`b246a2fe…`, `141994cc…`, `f50ce1e6…`
  byte-identical). **F7 gate sweep (2026-08-13): all 4 re-verified byte-identical to these
  values** with `/tmp/fx_subfolder/zig1`; 21-example matrix 20/21 end-to-end (only
  lisp_interpreter gcc-FAIL on the pre-existing builtins.zig `zT_N` defect); test_analyzer_bin
  PASS; corpus re-verified OK=233 FAIL=3 ICE=0 CRASH=0 GREEN=4 over 240 dirs (no new FAIL).
  **[F3 closeout (2026-08-13): gol/lisp/json RE-BASELINED by the lisp_defects plan F2 (operator
  ruling m0809) to `ff47d18d…`/`c1cb748b…`/`376fd681…` — see the MD5 table. F3 gate sweep: all 4
  byte-identical; 21-example matrix 21/21 end-to-end (lisp_interpreter functionally correct);
  corpus OK=239 FAIL=3 ICE=0 CRASH=0 GREEN=4 over 246 dirs; test_analyzer_bin PASS.]
  [updated: 2026-08-13]
- **Re-baselined 2026-08-08 (F4, std.io migration).** ALL 4 re-baselined because F4 replaces every
  `__bootstrap_print*`/`__bootstrap_write`/`__bootstrap_sleep_ms` extern in the gate entries with
  `std.io.print`/`printInt`/`write`/`sleepMs` (local `std.zig`/`std_io.zig`/`std_arena.zig` copies;
  json additionally re-points the arena import `std_arena.zig` → `std.zig`/`std.arena`). Runtime
  output byte-identical to pre-F4, verified by run diff (mud "MUD server listening on port 4000"
  rc=124; gol glider md5 `fcbf7e7c…`; lisp byte-identical; json md5 `d90e7828…`) — per the F-5
  AMENDMENT B precedent. Pre-F4 values: mud `6c0a83f1…`, gol `0d8f0092…`, lisp `a12f2fce…`,
  json `ff9b880c…` (all stale). [updated: 2026-08-08]

- **Re-baselined 2026-08-08 (F3, std.arena migration).** json re-baselined because F3 replaces
  the `arena_alloc_default` extern in `json.zig`/`file.zig`/`arena.zig` with the new
  `std_arena.zig` module (`std.create/alloc`) — json's emitted C changes (new `std_arena_*.c`
  module, no extern refs). Runtime output byte-identical to pre-fix (old legacy-linked binary vs
  new standard-linked binary, `diff` empty), per the F-5 AMENDMENT B precedent. mud/gol/lisp
  byte-identical. Pre-F3 json value: `c403f079…`. New json value: `ff9b880c…`.
  [updated: 2026-08-08]
- **Re-baselined 2026-08-08 (F1, @ptrToInt single-arg → usize).** lisp re-baselined because F1
  (commit `51bfdb3c`) makes single-arg `@ptrToInt(x)` resolve to `TYPE_USIZE` — lisp's
  sandbox addr/start/end consts are now `unsigned int`. Runtime output byte-identical to
  pre-fix (verified by stash-revert rebuild; both run rc=0, output md5
  `1c1f0a417d5e943433755a8ce593542f`). Per the F-5 AMENDMENT B precedent the gate is runtime
  behavior, not byte-identity. mud/gol/json byte-identical (F1 verified byte-identical for
  all three). Pre-F1 lisp value: `fad41183…`. New lisp value: `a12f2fce…`. Re-verified
  byte-identical by the F7 gate sweep (2026-08-08). [updated: 2026-08-08]
- **Re-baselined 2026-08-07 (F2, opt_slice null-payload Option B).** mud + lisp + json re-baselined
  because F2 (commit `5c515a7d`) drops the dead `int zT_N; zT_N = NULL;` payload temp in
  optional-null construction — the `null_literal` branch (lower.zig:1183-1214, Option B) emits
  `set_optional_null` directly on an `Opt_`-typed temp for null_src coercions instead of a
  `TYPE_NULL`→`int` temp. `= NULL;` sites: mud 2→0, lisp 3→0, json 1→0; `has_value = 0;` counts
  unchanged (mud 2, lisp 5, json 1) — only dead stores removed. Runtime-verified identical (F2
  report §5: mud rc=124 "MUD server listening on port 4000", gol glider rc=0, lisp rc=0, json
  parses test.json rc=0; output diffs empty). Per the F-5 AMENDMENT B precedent the gate is runtime
  behavior, not byte-identity. gol byte-identical. Pre-F2 values: mud `906fa59c…`, lisp
  `605b597e…`, json `b5f56ebd…`. New values: mud `6c0a83f1…`, lisp `fad41183…`, json
  `c403f079…`. [updated: 2026-08-07]

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

- **Re-baselined 2026-08-07 (F2, undefined-array-field init drop).** mud re-baselined because F2
  (Option A, commit ba89a6e0) skips the `assign_field` for `undefined` array-typed struct-literal
  fields in the lowerer — dropping the dead `[256]u8` zero-fill at mud main.zig:159 and the
  `undefined_const` temp (remaining diffs are pure temp renumbering). Runtime-verified identical:
  new + pristine mud both print "MUD server listening on port 4000" (rc=124 timeout). Per the F-5
  AMENDMENT B precedent the gate is runtime behavior, not byte-identity. gol/lisp/json
  byte-identical. Pre-F2 value: mud `50beb1bf…`. New mud value: `906fa59c…`. [updated: 2026-08-07]

- **Re-baselined 2026-08-06 (F6, lisp closures capture current env).** lisp re-baselined because
  `eval.zig:124` `env_to_value(env.*,…)` → `curr_env.*` (lambda now captures the current dynamic
  tail-call env, not the stale outer param env). Runtime-verified: `((make-adder 5) 3)` → `8`,
  `((add 10) 1)` → `11`, `((make-func 42))` → `42` (all were `UnboundSymbol`). mud/gol/json
  byte-identical. Per the F-5 AMENDMENT B precedent the gate is runtime behavior, not byte-identity.
  New lisp value: `605b597e…`. NOTE: composition of a closure passed as an argument
  (`((twice square) 3)`, `((compose square square) 3)`) now SEGFAULTS (was `UnboundSymbol`) — a
  latent lisp-source env-capture cycle (`env_to_value` stores live `define`-slot pointers that are
  back-patched after capture) exposed by the fix; tracked for a follow-up lisp-source fix, NOT a
  compiler defect. Pre-F6 value: lisp `55044a1f…`. [updated: 2026-08-06]

- **F7 gate sweep (2026-08-06, docs-only):** all 4 MD5s re-verified **byte-identical** to the
  values above (mud `50beb1bf…`, gol `0d8f0092…`, lisp `605b597e…`, json `b5f56ebd…`) with a
  fresh HEAD /tmp bootstrap — no re-baseline needed. [updated: 2026-08-06]

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
- For **mud_server** (z98, F6-migrated) NO `net_runtime.c` is needed — the standard
  `zig_runtime.c` + `zig_pal.c` recipe links it (the F6 builtin-emitted socket C replaces
  net_runtime.c). [updated: 2026-08-13]
- For **json_parser** NO special runtime is needed post-F3 — the standard `zig_runtime.c` +
  `zig_pal.c` recipe links it (the `arena_alloc_default` extern was replaced by the
  `std_arena.zig` module). [updated: 2026-08-08]

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
# use `gcc -c` (no link) for no-main repros; pre-F6 mud_server examples need net_runtime.c (F6-migrated z98 mud_server does not)
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
