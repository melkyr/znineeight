# d15_parity — D15 expected-type/peer-type three-way probes

Investigation-only fixture set for Phase 3.5 Task 9j (D15). No `sf/src` change is
part of this directory. Probes compare real **Zig 0.17.1**, **Z98 pre-D15**
(`280a3b12^` = `32473a03`) and **Z98 current** (`cf4cc032` tree, rebuilt). Exact
oracle URLs, hashes, commits and build commands are in `results/compilers.txt`.

## Layout

| Path | Contents |
|---|---|
| `matrix/` | Expected type × position cross product: `ret`, `typed_const`, `typed_var`, `untyped_const`, `untyped_var`, `callarg`, `field`, `array`, `nested` × `i32`, `?i32`, `error{E}!i32`, `error{E}!?i32`, `??i32`, `?*i32`, `[]const u8`, `f32` (plus `ret_anyerror_i32.zig`). |
| `corpus_adapted/` | The 12 re-opened corpus cases with Zig-0.17.1 hygiene only (`var`/never-mutated, `@intToPtr` → `&g`) while keeping the typed var/switch shape. |
| `corpus_raw/` | Verbatim copies of the 12 corpus `main.zig` files. They are not valid Zig 0.17.1 (old `var`/`@intToPtr` syntax), so Zig rejects them for unrelated reasons; `corpus_adapted/` is the parity twin. |
| `neg/` | D15 mixed int/bool negatives (runtime selector): direct, inferred, use, reverse, bool-return. |
| `selectors/` | Statement vs value switches, comptime/runtime selectors, tagged-union capture, noreturn/undefined, plus `if_expected_positions/` controls proving the expected-type stack is already populated at every result position. |
| `results/results.tsv` | Observed three-way summary. |
| `results/run.log` | Full observed output (first 40 lines per compiler per probe). |
| `results/safe_spotcheck.tsv` | `-fsafe --check` spot check. |
| `results/compilers.txt` | Oracle/pre/current provenance and exact build commands. |

## Exact run

```sh
cd repro/mi_matrix/known_excluded/d15_parity
ZIG=/tmp/phase35-d15-i/zig-0.17.1/zig \
PRE=/tmp/phase35-d15-i/pre-d15-build/zig1_5_clean \
CUR=/tmp/phase35-d15-i/current-build/zig1_5_clean \
./run_d15_parity.sh
```

Per probe the harness runs:

```sh
# Zig oracle (no C emission; rc + diagnostics only)
zig build-exe <probe>.zig \
  --cache-dir /tmp/.../zig-cache --global-cache-dir /tmp/.../zig-global \
  -femit-bin /tmp/.../out

# Z98, both compilers
<Z> --check -ffast <probe>.zig
<Z> --dump-c89 -ffast --output-dir <tmp>/dump <probe>.zig
```

`results.tsv` columns: `probe`, `zig_rc`, `zig_diag`, `zig_errors`,
`pre_check_rc`, `pre_diag`, `pre_c`, `pre_dump_rc`, `cur_check_rc`, `cur_diag`,
`cur_c`, `cur_dump_rc`. Diagnostics are the unique observed `error[...]` codes;
the full first diagnostic and notes are in `run.log`. `pre_c`/`cur_c` are the
number of `.c` files observed after `--dump-c89` (0 on a sema reject; 5 on
accept = translation unit + four runtime support files).

## Headline result

- `corpus_adapted/`: **12/12 Zig accept, 12/12 pre-D15 accept, 12/12 current
  reject `error[3000]` with 0 `.c`**. Current is the only over-rejecting layer.
- `matrix/`: all annotated expected-type positions `ret`, `typed_const`,
  `typed_var`, `callarg`, `field`, `array`, `nested` over `?i32`, `E!i32`,
  `E!?i32`, `??i32`, `?*i32` are Zig-accepted and pre-D15-accepted but
  current-rejected. Untyped positions and `i32`/slice/`f32` are accepted by all
  three.
- `neg/`: Zig rejects all five; pre-D15 accepts all; current rejects all.
- `selectors/`: current still **accepts** mixed statement switches that Zig and
  the D15 spec reject; current **rejects** comptime-known switches that Zig
  accepts. Both are called out in the Task 9j report.

Do not add this directory to the live corpus; it stays under `known_excluded/`
and is never enumerated by `scripts/corpus/list_corpus_dirs.sh`.
