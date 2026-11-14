# d15_31_diff — Task 9f.1 certification evidence

Test/certification-only evidence for the 31 value-switch emission diffs between
pre-Task-9 base `3bf7602b…` and final `cac6716d…`. No `sf/src` change is part of
this directory. It lives under `known_excluded/`, so
`scripts/corpus/list_corpus_dirs.sh` never enumerates it.

## Files

| File | Contents |
|---|---|
| `entries.tsv` | The exact 31 entries, split `19-value-switch` / `12-recovered`. |
| `results.tsv` | Per-entry dump/build/run/compare results. |
| `per_entry_table.tsv` | Per-entry changed C files, changed-line counts and results. |
| `all_c_diffs.txt` | Unified diffs of every changed emitted `.c` file (base vs final). |
| `pre_d15_results.txt` | Pre-D15 (`32473a03`) dump/build/run metadata for the 12 recovered cases. |
| `gcc_compile_only_getp.txt` | The two entries whose canonical link needs the fixture extern. |
| `zig_adapted_results.txt` | Zig 0.17.1 acceptance for the 12 adapted parity twins. |
| `compilers.txt` | Exact compiler commits, md5/sha256 and clean-source state. |
| `run_cert.sh` | The harness that produced `results.tsv` (paths in `/tmp/t9f1_evidence`). |

## Materialization of the 31

The list is the Task 9f canonical-corpus emission mismatch set:

```sh
# Task 9f comparison output (pre-Task-9 base vs final, 1278 entries)
cat /tmp/t9f2_corpus_mismatch.txt   # 31 EMIT lines
```

Split rule, reproduced from the Task 9f report and cross-checked against the
final-vs-interim comparison (`/tmp/t9f2_interim_full_mismatch.txt`):

- `12-recovered` = the `RC interim=2 final=0` / `EMIT interim=2 final=0` rows:
  the 12 `*_err_switch` / `*_null_switch` cases.
- `19-value-switch` = the `EMIT interim=0 final=0` rows: Task 9k's enumerated
  value-switch coercions.
- `12 + 19 = 31`; asserted by `entries.tsv`.

## Exact commands

All commands run from `/workspace/znineeight` unless noted.

```sh
# Compiler provenance / reuse check (must match before reuse)
md5sum /tmp/t9a_base_build/zig1_5_clean   # 3bf7602b9b396522e17ffc978eaba38d
md5sum /tmp/t9f2_final_build/zig1_5_clean # cac6716d4417c16c2f4140e76f435872

# Per entry (BASE=pre-Task-9, FINAL=final, PRE=pre-D15):
BASE=/tmp/t9a_base_build/zig1_5_clean
FINAL=/tmp/t9f2_final_build/zig1_5_clean
PRE=/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean
ROOT=/workspace/znineeight
entry=<resolved main.zig>

# dump
( cd "$ROOT" && "$BASE"  -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir out/base  "$entry" )
( cd "$ROOT" && "$FINAL" -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir out/final "$entry" )
( cd "$ROOT" && "$PRE"   -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir out/pre   "$entry" )

# gcc (canonical build_next_gen.sh recipe)
( cd out/base && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long \
    -Wno-pointer-sign -Wno-implicit-function-declaration -I . -c ./*.c )
( cd out/base && gcc -m32 -O0 ./*.o -o ../../base.bin )

# run
timeout 20 out/base.bin </dev/null >base.stdout 2>base.stderr; echo $?
```

The full loop is `run_cert.sh`. It resolves the entry as
`<dir>/main.zig`, else `<dir>/<basename>.zig`, else the first `*.zig`.

## Result summary

- 31/31: base dump rc 0, final dump rc 0, gcc `-m32 -std=c89` compile rc 0.
- 29/31: canonical link rc 0; run rc and stdout identical base vs final.
- 2/31 (`euoptptr_val_switch`, `optptr_val_switch`): canonical link fails only
  on the fixture's intentional `extern fn getp() *i32` with no definition,
  identically for base and final. Compilation succeeds for both. A supplemental
  `int *getp(void)` stub links and runs both; rc 0 and stdout equal (empty).
- 12/12 recovered: final rc/stdout equal to pre-D15 Z98 (`1bdedb74`) and to
  pre-Task-9 base.
- 19/19 value-switch: diffs are expected-type prong coercions (prong-level
  optional/error-union wrapping and prong cast to the expected type), with the
  outer peer-type wrap removed. No `switch`/`case`/`goto` line changed.
