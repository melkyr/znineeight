# Phase 3.5 Task 9f.1 — certification of the 31 value-switch emission diffs

**Status: PASS.** Certification/test-only. No `sf/src` change, no fix, no
plan/spec/defects edit, no push.

This document certifies the 31 emission diffs reported by Task 9f between the
pre-Task-9 base compiler and the final Task 9 compiler. It is the gating record
for Task 9f / Phase 3.5 closeout: the diffs must not be called harmless C
without the per-entry gcc build/run results below.

## 1. Scope

- In: the exact 31 canonical-corpus entries whose emitted C differs from
  pre-Task-9 base to final.
- Out: any statement switch or non-switch entry; D16 remains open by design.
- Evidence: `repro/mi_matrix/known_excluded/d15_31_diff/`
  (`entries.tsv`, `results.tsv`, `per_entry_table.tsv`, `all_c_diffs.txt`,
  `pre_d15_results.txt`, `gcc_compile_only_getp.txt`,
  `zig_adapted_results.txt`, `compilers.txt`, `run_cert.sh`, `README.md`).

## 2. Compiler provenance and clean source state

| Compiler | Commit | Path | md5 | sha256 |
|---|---|---|---|---|
| pre-Task-9 base | `d124055d` | `/tmp/t9a_base_build/zig1_5_clean` | `3bf7602b9b396522e17ffc978eaba38d` | `c2b2e4e4078460dafda45e7cd132caaeb26f0b810b3c17461360b4372b12538e` |
| final Task 9 | `ace04574` | `/tmp/t9f2_final_build/zig1_5_clean` | `cac6716d4417c16c2f4140e76f435872` | `a314303b51680c24ee8462ab6be10992edb22a0bdef28e52e28171c82ac65dc2` |
| pre-D15 Z98 (oracle for the 12) | `32473a03` | `/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean` | `1bdedb7419952ed10be80f1cca7b5476` | `bb4ce380c84d2cc0495ba072ed31e07091aa08ad17b0485642ba70549fedfd02` |
| Zig oracle | 0.17.1 | `/tmp/phase35-d15-i/zig-0.17.1/zig` | — | `58959f01285c05a74276f09327b551d42ed6006bf325a78dc661a024e314987b` |

Existing builds were reused because their hashes match the Task 9a/9f recorded
values. Source state at certification:

```text
HEAD                         29b9f923 (docs only)
compiler source              ace04574
git diff --stat ace04574 HEAD -- sf/src   0 files
git status --porcelain -- sf/src          0 lines
```

The only dirty/untracked worktree items are pre-existing docs and unrelated
`lin_bin/`, `zig1/`; none is a compiler-source change.

## 3. Materialization of the exact 31

The list is the Task 9f canonical 1278-entry comparison mismatch set:

```text
/tmp/t9f2_corpus_mismatch.txt : 31 EMIT lines
  examples/z98/z9play
  repro/mi_matrix/emission_mangler_collision_xmod
  repro/mi_matrix/emission_type_storage_extern_threealias_xmod
  repro/mi_matrix/emission_type_storage_extern_xmod
  repro/mi_matrix/emission_void_temp_enum_xmod
  repro/mi_matrix/eu_err_switch
  repro/mi_matrix/eu_val_switch
  repro/mi_matrix/eunum_err_switch
  repro/mi_matrix/eunum_val_switch
  repro/mi_matrix/euopt_err_switch
  repro/mi_matrix/euopt_val_switch
  repro/mi_matrix/euoptptr_err_switch
  repro/mi_matrix/euoptptr_val_switch
  repro/mi_matrix/opt_null_switch
  repro/mi_matrix/opt_val_switch
  repro/mi_matrix/opteu_err_switch
  repro/mi_matrix/opteu_null_switch
  repro/mi_matrix/opteu_val_switch
  repro/mi_matrix/optnum_null_switch
  repro/mi_matrix/optnum_val_switch
  repro/mi_matrix/optopt_null_switch
  repro/mi_matrix/optopt_val_switch
  repro/mi_matrix/optptr_null_switch
  repro/mi_matrix/optptr_val_switch
  repro/mi_matrix/stdlib_errset_capture_qualified_xmod
  repro/mi_matrix/stdlib_switch_case_consts_xmod
  repro/mi_matrix/stdlib_switch_enum_range_xmod
  repro/mi_matrix/switch_case_range_xmod
  repro/mi_matrix/switch_expr_unreachable_xmod
  repro/mi_matrix/switch_neg_enum_min_ok_xmod
  repro/mi_matrix/typealias_agg_xmod
```

Split reproduced from the Task 9f final-vs-interim comparison
(`/tmp/t9f2_interim_full_mismatch.txt`, `5011d08c…` interim):

- **12 recovered** = `RC interim=2 final=0` and `EMIT interim=2 final=0`:
  `eu_err_switch`, `eunum_err_switch`, `euopt_err_switch`, `euopt_val_switch`,
  `euoptptr_err_switch`, `opt_null_switch`, `opteu_err_switch`,
  `opteu_null_switch`, `optnum_null_switch`, `optopt_null_switch`,
  `optopt_val_switch`, `optptr_null_switch`.
- **19 value-switch** = `EMIT interim=0 final=0`: the remaining entries, exactly
  Task 9k's enumeration.
- Asserted `12 + 19 = 31` in `repro/mi_matrix/known_excluded/d15_31_diff/entries.tsv`.

## 4. Commands

All from `/workspace/znineeight`. `BASE`, `FINAL`, `PRE`, and `--lib-dir` are
canonical (see `README.md` in the evidence directory).

```sh
BASE=/tmp/t9a_base_build/zig1_5_clean
FINAL=/tmp/t9f2_final_build/zig1_5_clean
PRE=/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean
ROOT=/workspace/znineeight

# dump
"$BASE"  -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir out/base  "$entry"
"$FINAL" -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir out/final "$entry"
"$PRE"   -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir out/pre   "$entry"

# gcc -m32 -std=c89 compile, then canonical link
( cd out/base && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long \
    -Wno-pointer-sign -Wno-implicit-function-declaration -I . -c ./*.c )
( cd out/base && gcc -m32 -O0 ./*.o -o ../../base.bin )

# run (runnable entries)
timeout 20 out/base.bin </dev/null >base.stdout 2>base.stderr; echo $?
```

The full loop, including per-entry diff extraction, is
`repro/mi_matrix/known_excluded/d15_31_diff/run_cert.sh`.

## 5. Per-entry certification

`Cat`: `19-val` = Task 9k value-switch coercion; `12-rec` = D15-recovered.
`Dump b/f` = dump rc base/final. Run columns are base/final rc; stdout equality
was compared byte-for-byte (`YES` = rc and stdout equal). `pre-D15` compares the
12 recovered cases to the `32473a03` Z98 build.

| # | Cat | Entry | Changed C files (base→final) | Lines | Dump b/f | gcc -std=c89 | Link | Run b/f | rc/stdout equal | pre-D15 equal |
|---:|---|---|---|---:|---|---|---|---|---|---|
| 1 | 19-val | `examples/z98/z9play` | floor_3057FA6C.c | 22 | 0/0 | rc 0 | OK | 1/1 | YES | — |
| 2 | 19-val | `repro/mi_matrix/emission_mangler_collision_xmod` | cmod1_F84B6A15.c, cmod2_051C6598.c | 28 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 3 | 19-val | `repro/mi_matrix/emission_type_storage_extern_threealias_xmod` | mod_b_FF89D2B5.c, mod_c_DC75BFB2.c, mod_d_2DFA548F.c | 62 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 4 | 19-val | `repro/mi_matrix/emission_type_storage_extern_xmod` | mod_b_B96661BC.c, mod_c_808F6C7F.c | 28 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 5 | 19-val | `repro/mi_matrix/emission_void_temp_enum_xmod` | mod_b_5BDBD10A.c | 20 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 6 | 12-rec | `repro/mi_matrix/eu_err_switch` | main_FBE75381.c | 34 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 7 | 19-val | `repro/mi_matrix/eu_val_switch` | main_A6C2E28D.c | 34 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 8 | 12-rec | `repro/mi_matrix/eunum_err_switch` | main_E41A4169.c | 34 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 9 | 19-val | `repro/mi_matrix/eunum_val_switch` | main_6D349245.c | 38 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 10 | 12-rec | `repro/mi_matrix/euopt_err_switch` | main_88CD6B78.c | 40 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 11 | 12-rec | `repro/mi_matrix/euopt_val_switch` | main_8FC083F8.c | 36 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 12 | 12-rec | `repro/mi_matrix/euoptptr_err_switch` | main_8BE3DFF4.c | 44 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 13 | 19-val | `repro/mi_matrix/euoptptr_val_switch` | main_7EB44BFC.c | 42 | 0/0 | rc 0 | compile-only\* | — | YES (stub) | — |
| 14 | 12-rec | `repro/mi_matrix/opt_null_switch` | main_82A9C634.c | 24 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 15 | 19-val | `repro/mi_matrix/opt_val_switch` | main_20D9085E.c | 34 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 16 | 12-rec | `repro/mi_matrix/opteu_err_switch` | main_595971D4.c | 48 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 17 | 12-rec | `repro/mi_matrix/opteu_null_switch` | main_C5FEEACE.c | 30 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 18 | 19-val | `repro/mi_matrix/opteu_val_switch` | main_5DF2B35C.c | 48 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 19 | 12-rec | `repro/mi_matrix/optnum_null_switch` | main_295EA7C2.c | 24 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 20 | 19-val | `repro/mi_matrix/optnum_val_switch` | main_10F22C68.c | 38 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 21 | 12-rec | `repro/mi_matrix/optopt_null_switch` | main_0AFD2FB9.c | 30 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 22 | 12-rec | `repro/mi_matrix/optopt_val_switch` | main_286E3D35.c | 32 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 23 | 12-rec | `repro/mi_matrix/optptr_null_switch` | main_77CC72C8.c | 24 | 0/0 | rc 0 | OK | 0/0 | YES | YES |
| 24 | 19-val | `repro/mi_matrix/optptr_val_switch` | main_B447D61A.c | 26 | 0/0 | rc 0 | compile-only\* | — | YES (stub) | — |
| 25 | 19-val | `repro/mi_matrix/stdlib_errset_capture_qualified_xmod` | main_B371182F.c | 42 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 26 | 19-val | `repro/mi_matrix/stdlib_switch_case_consts_xmod` | main_C6A06A48.c | 194 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 27 | 19-val | `repro/mi_matrix/stdlib_switch_enum_range_xmod` | main_13AC5D2E.c | 128 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 28 | 19-val | `repro/mi_matrix/switch_case_range_xmod` | main_14A2705C.c | 28 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 29 | 19-val | `repro/mi_matrix/switch_expr_unreachable_xmod` | main_03DCC368.c | 4 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 30 | 19-val | `repro/mi_matrix/switch_neg_enum_min_ok_xmod` | main_A9F8D9D4.c | 20 | 0/0 | rc 0 | OK | 0/0 | YES | — |
| 31 | 19-val | `repro/mi_matrix/typealias_agg_xmod` | mod_b_A698EDD9.c | 14 | 0/0 | rc 0 | OK | 0/0 | YES | — |

\* **Compile-only exception (fully explained, not a mismatch).** Both
`euoptptr_val_switch` and `optptr_val_switch` declare
`extern fn getp() *i32` in the fixture with no definition. Compilation succeeds
for base and final; the canonical link fails on the same undefined `getp` in
both. A supplemental `int *getp(void) { static int g = 7; return &g; }` stub
links and runs both: rc 0 and empty stdout in both, equal. The emitted-C diff
for both is the expected prong-level `?*i32` / `!?*i32` wrapping; no other
difference. Details in `gcc_compile_only_getp.txt`.

`examples/z98/z9play` run rc 1/1 is its no-argument usage path; stdout is the
same usage block byte-for-byte for base and final.

## 6. Diff analysis

`all_c_diffs.txt` contains the unified diffs of every changed emitted `.c`.
Across all 31 entries:

- Changed-line shapes are exactly: prong temp declaration changes; expected-type
  casts at the prong (e.g. `zT_N = (int)zT_N`); optional/error-union wraps moved
  to the prong (`has_value`/`value`/`data.payload`/`is_error`); the equivalent
  outer peer-type wrap removed; and the return-position outer cast removed.
- `grep` over non-header diff lines for `switch`, `case `, or `goto z_bb`: **0**.
  No switch dispatch or statement-switch code changed.
- Every entry's diff is confined to value-result switch prong coercions to the
  known expected type. This is the intended Task 9k expected-type-first
  semantics.

## 7. Oracle comparison

- **12 recovered:** final behavior equals pre-D15 Z98 (`32473a03`, md5
  `1bdedb74…`) for all 12: dump rc 0, compile/link rc 0, run rc 0, stdout equal.
  The adapted parity twins in
  `repro/mi_matrix/known_excluded/d15_parity/corpus_adapted/` are accepted by
  Zig 0.17.1 (12/12 rc 0, fresh run in `zig_adapted_results.txt`), matching the
  pre-D15 accept and the final accept.
- **19 value-switch:** final is accepted and emits the expected-type prong
  coercion, matching the Zig 0.17.1 expected-position evidence in
  `repro/mi_matrix/known_excluded/d15_parity/results/results.tsv`: every
  `typed_var`/`typed_const`/`ret`/`callarg`/`field`/`array`/`nested` expected
  position over `?i32`, `E!i32`, `E!?i32`, `??i32`, `?*i32` is Zig-accepted
  (`zig_rc=0`, `pre_check_rc=0`), which is the semantics the final compiler now
  implements.

## 8. Boundary confirmation

- **31/31 are switch entries.** Every changed C hunk is a value-result switch
  prong coercion; no non-switch entry is present.
- **No statement-switch emission shift.** Zero switch/case/goto lines changed.
  The Task 9l statement-switch repro set (35 entries) has no emission diff
  member, and D16's statement-switch behavior is unchanged.
- **`z9play` nuance:** `z9play` also contains statement switches and therefore
  appears in the Task 9l statement-switch repro35 set, but its only emission
  diff is the value-result `return switch` in `floor_*.c` (`quantRange`). No
  statement-switch C changed. It is in the 31 because Task 9f/9k enumerate its
  value-switch shift, not a statement-switch shift.
- **D16 remains open** (mixed statement switches, assignment-void, `anyerror`,
  comptime-prong pruning). No D16 work was done or claimed here.

## 9. Concerns / notes

1. The two compile-only fixtures need a fixture stub to link. This is a property
   of the `extern fn getp()` fixtures, identical in base and final, not a
   compiler regression; both were also runtime-checked with a stub and matched.
2. `z9play` is a mixed entry (value + statement switches) but its diff is
   value-switch-only; see §8.
3. D16 stays open by design; this certification does not close or weaken it.

## 10. Conclusion

All 31 emission diffs certify as expected value-switch expected-type coercions:
31/31 dump and `gcc -m32 -std=c89` compile; 29/31 run directly with identical
base/final rc+stdout; the remaining 2 are fixture-external-link compile-only with
identical stub-run behavior; 12/12 recovered cases match pre-D15 Z98. No
statement switch, no non-switch entry, no unexplained mismatch. **Task 9f.1
PASSES.**
