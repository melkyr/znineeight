# M2 Task 1A report — Lexer f64 rounding investigation

**Status:** DONE — bug CONFIRMED (operator gate passed; full inventory + migration list completed)
**Branch:** `zig1_improvements`
**Plan:** `docs/superpowers/plans/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan.md` Task 1A
**Brief:** `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1A-brief.md`
**Context:** `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1a-context.md`
**Compiler under test:** `/tmp/m7_t5_seed2/zig1_5_clean` (md5 `b299b4b435e624d0ddbd2edde681cbc3`, matches context pin)
**Scope:** report-only. No source, fixture, seed, or tracked-file edits (this report is the only addition).

## 0. Verdict (operator gate)

**The bug is real.** All three D6 claims (commit `d13c3a93`) reproduce bit-for-bit through the real
compiler's `--dump-c89` path, and both mandated error paths (mantissa fraction loop and exponent
`power *= 10.0`) independently produce wrong roundings. `sf/src/lexer.zig` `parseF64` is **not**
correctly rounded IEEE-754. Proceeding with the full Task 1A plan (Steps 1–6) is therefore correct;
this is NOT a STOP-present.

## 1. Root cause — `sf/src/lexer.zig` `parseF64` (`sf/src/lexer.zig:610-670`)

Three sequential accumulators, each independently lossy; the parser never re-rounds from exact
integer significand + decimal exponent the way `strtod` does:

1. **Integer-part loop** (`parseF64` first `while`): `result = result * 10.0 + digit` per digit.
   Exact only while the partial value stays <= 2^53; each step rounds once the magnitude exceeds
   that. Latent contributor (see control cases in §3: `9007199254740993.0` and
   `12345678901234567.0` happened to land correctly, and no corpus mismatch is driven by this loop
   alone).
2. **Fraction loop** (mandated path #1): `result += digit * frac_mul; frac_mul *= 0.1` per digit.
   `0.1` is not representable in binary, so `frac_mul` is already wrong after one step and
   compounds one rounding per further digit; each `+=` adds one more rounding. This path alone
   mis-rounds even exactly-representable values (`0.75` -> `3fe8000000000001`, `1.75` ->
   `3ffc000000000001`).
3. **Exponent path** (mandated path #2): `power` is built by `exp` successive `power *= 10.0`
   roundings, then a single `result *= power` or `result /= power`. For `1e300` (no decimal point
   at all) this alone yields `7e37e43c8800759d` instead of `7e37e43c8800759c`. Negative exponents
   add a division rounding (`result /= power`), e.g. `1e-308` -> `000730d67819e8d3` vs correct
   `000730d67819e8d2`.

**Both mandated paths confirmed.** Corpus evidence split over the 240 mismatched literals:

| literal shape | mismatches | driver |
|---|---|---|
| fraction only (no exponent) | 172 | path 2 |
| exponent only (no decimal point) | 2 (`1e300`, `1e-308`) | path 3 |
| fraction + exponent | 66 | paths 2 and 3 |

Abs-ULP distribution of all 240: 141 x 1 ULP, 82 x 2 ULP, 13 x 3 ULP, 4 x 4 ULP (max 4 ULP observed).

Note the second-order effect: the C emitter prints the already-wrong f64 as a 17-digit decimal, so
`gcc -std=c89` faithfully reproduces the wrong value end-to-end (verified in §2).

## 2. Minimal repro (exact commands)

Program `/tmp/t1a_work/a.zig`:

```zig
pub fn main() void {
    const a: f64 = 0.366025403784439;
    const b: f64 = -0.16666666666666666;
    const c: f64 = 1e300;
    const d: f64 = 1e-308;
    const e: f64 = 0.3;
    const f: f64 = 0.75;
    const g: f64 = 1.75;
    _ = a; _ = b; _ = c; _ = d; _ = e; _ = f; _ = g;
}
```

Command (md5 of compiler `b299b4b435e624d0ddbd2edde681cbc3`):

```sh
mkdir -p /tmp/t1a_work/out
/tmp/m7_t5_seed2/zig1_5_clean --dump-c89 /tmp/t1a_work/a.zig -o /tmp/t1a_work/out
```

Emitted C (`out/a_82688E3E.c:18-30`, exact observed text):

```c
zT_1  = 3.660254037844391e-1;
zT_4  = -(zT_00435AEB_f64)(1.6666666666666669e-1);
zT_6  = 1.0000000000000002e+300;
zT_8  = 1.0000000000000004e-308;
zT_10 = 3.0000000000000004e-1;
zT_12 = 7.5000000000000011e-1;
zT_14 = 1.7500000000000002e+0;
```

The brief's two claimed strings reproduce exactly: `0.366025403784439` emits `3.660254037844391e-1`
and `-0.16666666666666666` emits `1.6666666666666669e-1` (unary minus wraps the literal). Feeding
those decimal strings to `gcc -m32 -std=c89` `strtod` yields the claimed wrong bit patterns
`3fd76cf5d0b0995d` and `bfc5555555555556` — i.e. the wrong values survive the whole pipeline.

## 3. Correct-value table (round-to-nearest-even)

Two independent oracles agree on every row: Python `float()` (correctly rounded) and
`gcc -m32 -std=c89 -pedantic` `strtod` (glibc, correctly rounded). Both were run; oracle sources
`/tmp/t1a_work/oracle.c` and Python `struct.pack('>d', float(s))`. "Z98 bits" are the f64 the lexer
produces today (verified end-to-end via `--dump-c89` + `strtod` on the emitted text).

| literal | correct bits | Z98 bits (bug) | ULP | Z98-emitted decimal |
|---|---|---|---|---|
| `0.366025403784439` | `3fd76cf5d0b0995b` | `3fd76cf5d0b0995d` | +2 | `3.660254037844391e-1` |
| `-0.16666666666666666` | `bfc5555555555555` | `bfc5555555555556` | +1 | `-(1.6666666666666669e-1)` |
| `1e300` | `7e37e43c8800759c` | `7e37e43c8800759d` | +1 | `1.0000000000000002e+300` |
| `1.0e300` | `7e37e43c8800759c` | `7e37e43c8800759d` | +1 | `1.0000000000000002e+300` |
| `1e-308` | `000730d67819e8d2` | `000730d67819e8d3` | +1 | `1.0000000000000004e-308` |
| `0.3` | `3fd3333333333333` | `3fd3333333333334` | +1 | `3.0000000000000004e-1` |
| `0.75` | `3fe8000000000000` | `3fe8000000000001` | +1 | `7.5000000000000011e-1` |
| `1.75` | `3ffc000000000000` | `3ffc000000000001` | +1 | `1.7500000000000002e+0` |

Additional rows used for root-cause/control (not required by the brief):

| literal | correct bits | Z98 bits | ULP | role |
|---|---|---|---|---|
| `0.16666666666666666` | `3fc5555555555555` | `3fc5555555555556` | +1 | unsigned half of the `-0.166...` repro |
| `0.3660254037844389` | `3fd76cf5d0b09959` | `3fd76cf5d0b0995b` | +2 | `sf/src/std_noise.zig:39` workaround (intentionally wrong text) |
| `0.16666666666666664` | `3fc5555555555554` | `3fc5555555555555` | +1 | `sf/src/std_noise.zig:40` workaround (intentionally wrong text) |
| `1.5e-3` | `3f589374bc6a7efa` | `3f589374bc6a7efa` | 0 | control: single exact division, parses correctly |
| `9007199254740993.0` | `4340000000000000` | `4340000000000000` | 0 | control: integer loop, ties-to-even lands correct |
| `12345678901234567.0` | `4345ee2a2eb5a5c4` | `4345ee2a2eb5a5c4` | 0 | control: long integer part, happens to land correct |
| `0.211324865405187` | `3fcb0cb174df99c3` | `3fcb0cb174df99c3` | 0 | control: `sf/src/std_noise.zig:33` `STRETCH_CONSTANT_2D` parses correctly |

**Workaround note (D6 fix round 1):** `0.3660254037844389` and `0.16666666666666664` in
`sf/src/std_noise.zig` are non-canonical spellings chosen so that the *buggy* parser lands on the
intended doubles (`3fd76cf5d0b0995b` / `3fc5555555555555`). They are deliberately mismatched
against correct rounding — that is the compensation Task 1D must remove.

## 4. Inventory

Method: Python scanner that replicates `lexerScanNumber` + `parseF64` digit-for-digit (skipping
comments, strings, char literals, multiline strings and identifiers; hex/octal/binary ints are not
floats in Z98) over **all `.zig` sources** under `sf/src`, `examples/z98`, `repro/mi_matrix`,
`stdlib_test`. A literal is a **mismatch** when `parseF64(text)` bits differ from correctly rounded
`strtod`/Python `float` bits. `.c`/`.h` files in those trees are compiled by `gcc` (correct
`strtod`) and are out of scope for the Z98-lexer defect.

Scanner was validated against the real compiler: 8 spot literals (including 5 from the corpus)
compiled with `/tmp/m7_t5_seed2/zig1_5_clean --dump-c89`, the emitted decimals re-parsed with
`gcc -m32 -std=c89` `strtod` — every result equals the scanner's `parseF64` prediction
(`/tmp/t1a_work/out2`, `/tmp/t1a_work/oracle2.c`).

**Recomputed totals — the plan baseline is confirmed exactly:**

| metric | value |
|---|---|
| decimal float literals scanned | **1,061** |
| mismatches (parseF64 != correct rounding) | **240** |
| files containing >= 1 literal | 53 |
| files containing >= 1 mismatch | **13** |

Per-tree: `sf/src` 306 literals / 2 mismatches; `examples/z98` 389 / 207; `repro/mi_matrix` 366 / 31;
`stdlib_test` 0 / 0.

Per-file mismatches and impact classes (definitions below):

| file | mismatches | impact class |
|---|---|---|
| `examples/z98/z9play/floor.zig` | 198 | A-audio-decode |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig` | 20 | D-fixture-golden |
| `examples/z98/z9play/tests/dsp_test.zig` | 5 | B-app-test |
| `repro/mi_matrix/lexer_float_exponent_xmod/main.zig` | 4 | E-fixture-tol |
| `examples/z98/z9play/tests/floor_test.zig` | 3 | B-app-test |
| `sf/src/std_noise.zig` | 2 | C-lexer-workaround |
| `repro/mi_matrix/stdlib_rand_stat_xmod/main.zig` | 2 | E-fixture-tol |
| `examples/z98/z9play/tests/setup_test.zig` | 1 | B-app-test |
| `repro/mi_matrix/stdlib_comptime_float_compare_xmod/main.zig` | 1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_parse_ftoa_xmod/main.zig` | 1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_parse_parsefloat_xmod/main.zig` | 1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_parse_stress_xmod/main.zig` | 1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod/main.zig` | 1 | E-fixture-tol |

Impact classes:

- **A-audio-decode** — `floor.zig` 256-entry `FLOOR1_INVERSE_DB_TABLE`, "included verbatim from
  spec 10.1" (`examples/z98/z9play/floor.zig:31-33`). Spec decimal text, currently mis-parsed by
  up to 4 ULP; the compiled decoder therefore runs on slightly wrong table values today. After the
  lexer fix the same text parses to the true spec values. **Not workaround literals — `floor.zig`
  must not be edited** (answers Task 1C's "unless Task 1A proves a workaround literal" condition).
- **B-app-test** — z9play test constants under tolerance/relative asserts (`tests/dsp_test.zig`,
  `tests/floor_test.zig`, `tests/setup_test.zig`).
- **C-lexer-workaround** — `sf/src/std_noise.zig:39-40` intentional compensation (see §3).
- **D-fixture-golden** — fixture literals that feed a pinned golden/hash that must move
  (`stdlib_noise_basic_xmod` PGM hash).
- **E-fixture-tol** — fixture literals inside tolerance/relative asserts or invariant pins
  (rerun-only).

### Full mismatch table (all 240)

| file:line | literal | Z98 bits (current) | correct bits | ULP | impact |
|---|---|---|---|---|---|
| `examples/z98/z9play/floor.zig:49` | `1.0649863e-07` | `3e7c9687b6622afa` | `3e7c9687b6622afb` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:49` | `1.1341951e-07` | `3e7e72211ef8f8aa` | `3e7e72211ef8f8a9` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:49` | `1.2079015e-07` | `3e8036516543d7e6` | `3e8036516543d7e7` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:49` | `1.2863978e-07` | `3e81440778a2f268` | `3e81440778a2f267` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:50` | `1.4590251e-07` | `3e83952c0cd58ec9` | `3e83952c0cd58eca` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:50` | `1.5538408e-07` | `3e84daf4d264c67c` | `3e84daf4d264c67d` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:50` | `1.6548181e-07` | `3e8635e964ed21d8` | `3e8635e964ed21d7` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:51` | `1.7623575e-07` | `3e87a76a0d03c212` | `3e87a76a0d03c211` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:51` | `1.8768855e-07` | `3e8930edf1ebbd1d` | `3e8930edf1ebbd1c` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:52` | `2.2670913e-07` | `3e8e6daa98b1dacc` | `3e8e6daa98b1dac9` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:52` | `2.4144197e-07` | `3e9033f10387e909` | `3e9033f10387e90a` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:52` | `2.5713223e-07` | `3e91417f81cda0e2` | `3e91417f81cda0e3` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:53` | `2.9163793e-07` | `3e93924d2e3801ae` | `3e93924d2e3801af` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:53` | `3.3077411e-07` | `3e9632a7eba28c34` | `3e9632a7eba28c35` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:53` | `3.5226968e-07` | `3e97a3f26fe53e3d` | `3e97a3f26fe53e3e` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:54` | `3.9954229e-07` | `3e9ad0159317375e` | `3e9ad0159317375f` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:54` | `4.2550680e-07` | `3e9c8e26b27b1c77` | `3e9c8e26b27b1c76` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:54` | `4.5315863e-07` | `3e9e6934bb4d4b5b` | `3e9e6934bb4d4b5c` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:55` | `4.8260743e-07` | `3ea03190f63d4164` | `3ea03190f63d4165` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:55` | `5.4737065e-07` | `3ea25de0c9ebf418` | `3ea25de0c9ebf417` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:57` | `7.9862701e-07` | `3eaacc275e149bc3` | `3eaacc275e149bc2` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:57` | `9.0579828e-07` | `3eae64bf7b88fc9d` | `3eae64bf7b88fc9c` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:57` | `9.6466216e-07` | `3eb02f31430507da` | `3eb02f31430507db` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:58` | `1.0273513e-06` | `3eb13c70b33dbccd` | `3eb13c70b33dbcce` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:58` | `1.2409384e-06` | `3eb4d1ca333d469c` | `3eb4d1ca333d469d` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:59` | `1.3215816e-06` | `3eb62c265614cb95` | `3eb62c265614cb96` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:59` | `1.4074654e-06` | `3eb79d0492afa13d` | `3eb79d0492afa13e` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:59` | `1.4989305e-06` | `3eb925db8394117e` | `3eb925db8394117f` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:60` | `1.7000785e-06` | `3ebc85c814319c07` | `3ebc85c814319c06` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:60` | `1.8105592e-06` | `3ebe604ae4a73c4e` | `3ebe604ae4a73c4f` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:61` | `2.4804557e-06` | `3ec4cebcf131d509` | `3ec4cebcf131d50a` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:61` | `2.6416497e-06` | `3ec628e647e481ce` | `3ec628e647e481cf` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:62` | `2.8133190e-06` | `3ec7998e7a00983d` | `3ec7998e7a00983e` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:62` | `2.9961443e-06` | `3ec9222bbf8839d3` | `3ec9222bbf8839d4` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:62` | `3.1908506e-06` | `3ecac44cab293d48` | `3ecac44cab293d49` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:62` | `3.3982101e-06` | `3ecc8199c260b178` | `3ecc8199c260b179` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:63` | `3.6190449e-06` | `3ece5bd6f9789de2` | `3ece5bd6f9789de3` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:63` | `4.3714470e-06` | `3ed255ce33a1145a` | `3ed255ce33a11459` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:64` | `4.6555282e-06` | `3ed386d5d8eaee6c` | `3ed386d5d8eaee6d` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:64` | `5.2802740e-06` | `3ed625a6aa4b41a9` | `3ed625a6aa4b41a8` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:64` | `5.6234160e-06` | `3ed79618d1e898dd` | `3ed79618d1e898de` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:65` | `6.7925283e-06` | `3edc7d6bf643225a` | `3edc7d6bf643225b` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:65` | `7.2339451e-06` | `3ede5763b0231d51` | `3ede5763b0231d50` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:66` | `8.7378876e-06` | `3ee2531e2096bb05` | `3ee2531e2096bb06` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:66` | `9.3057248e-06` | `3ee383f913eb6281` | `3ee383f913eb6280` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:67` | `9.9104632e-06` | `3ee4c8a3b0cd2d94` | `3ee4c8a3b0cd2d93` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:67` | `1.0554501e-05` | `3ee6226792655cf2` | `3ee6226792655cf1` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:68` | `1.4459606e-05` | `3eee52f11dc30c60` | `3eee52f11dc30c62` | -2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:68` | `1.5399272e-05` | `3ef025b5e9f8fa16` | `3ef025b5e9f8fa17` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:69` | `1.8600792e-05` | `3ef3811cb16fff00` | `3ef3811cb16fff01` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:70` | `2.2467911e-05` | `3ef78f2f165764bb` | `3ef78f2f165764ba` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:70` | `2.3928002e-05` | `3ef9171fc6daeba3` | `3ef9171fc6daeba5` | -2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:70` | `2.5482978e-05` | `3efab888e9f1172f` | `3efab888e9f1172e` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:71` | `2.7139006e-05` | `3efc75124a9cce40` | `3efc75124a9cce3f` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:71` | `2.8902651e-05` | `3efe4e7f0d919e95` | `3efe4e7f0d919e97` | -2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:71` | `3.2781225e-05` | `3f012fd2507b5fcc` | `3f012fd2507b5fcb` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:72` | `3.4911534e-05` | `3f024dbf2c9caa8b` | `3f024dbf2c9caa8c` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:72` | `3.9596466e-05` | `3f04c28c364964ed` | `3f04c28c364964ee` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:72` | `4.2169667e-05` | `3f061beab9a5c4db` | `3f061beab9a5c4da` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:73` | `4.4910090e-05` | `3f078bbaf1469676` | `3f078bbaf1469675` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:73` | `4.7828601e-05` | `3f0913723784a047` | `3f0913723784a046` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:73` | `5.4246931e-05` | `3f0c70e65b3ecbe9` | `3f0c70e65b3ecbe8` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:74` | `6.1526565e-05` | `3f1020fa5689d8bd` | `3f1020fa5689d8be` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:75` | `7.4317983e-05` | `3f137b6539d86e86` | `3f137b6539d86e85` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:76` | `0.00010181521` | `3f1ab0b3fd1e2988` | `3f1ab0b3fd1e2986` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:76` | `0.00010843174` | `3f1c6cbb1bccc89e` | `3f1c6cbb1bccc89c` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:76` | `0.00011547824` | `3f1e459d0e8a59a8` | `3f1e459d0e8a59a5` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:77` | `0.00012298267` | `3f201e9d175c20ec` | `3f201e9d175c20eb` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:77` | `0.00013097477` | `3f212ac8b51eddf8` | `3f212ac8b51eddf7` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:77` | `0.00013948625` | `3f224861c39469dc` | `3f224861c39469da` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:77` | `0.00014855085` | `3f23788a15c83243` | `3f23788a15c83241` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:78` | `0.00015820453` | `3f24bc76909a8a65` | `3f24bc76909a8a62` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:78` | `0.00016848555` | `3f26156fdaacaa07` | `3f26156fdaacaa05` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:78` | `0.00017943469` | `3f2784d44029aae8` | `3f2784d44029aae5` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:78` | `0.00019109536` | `3f290c18a4ab0765` | `3f290c18a4ab0763` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:79` | `0.00020351382` | `3f2aacca670197e3` | `3f2aacca670197e1` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:79` | `0.00021673929` | `3f2c6890531a117a` | `3f2c6890531a1178` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:79` | `0.00023082423` | `3f2e412d09b7029e` | `3f2e412d09b7029d` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:79` | `0.00024582449` | `3f301c402525a8af` | `3f301c402525a8ad` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:80` | `0.00026179955` | `3f312844815f1c3a` | `3f312844815f1c37` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:80` | `0.00027881276` | `3f3245b3af97a23d` | `3f3245b3af97a23c` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:80` | `0.00029693158` | `3f3375af6cdd2888` | `3f3375af6cdd2886` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:80` | `0.00031622787` | `3f34b96c5c1782a8` | `3f34b96c5c1782a7` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:81` | `0.00033677814` | `3f36123318e92878` | `3f36123318e92876` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:81` | `0.00035866388` | `3f378161a285f41c` | `3f378161a285f41a` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:81` | `0.00038197188` | `3f39086cbb8b2024` | `3f39086cbb8b2020` | +4 | A-audio-decode |
| `examples/z98/z9play/floor.zig:81` | `0.00040679456` | `3f3aa8e154d60587` | `3f3aa8e154d60585` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:82` | `0.00043323036` | `3f3c64663a535962` | `3f3c64663a535960` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:82` | `0.00046138411` | `3f3e3cbda9d0eab3` | `3f3e3cbda9d0eab0` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:82` | `0.00049136745` | `3f4019e390648fef` | `3f4019e390648fed` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:82` | `0.00052329927` | `3f4125c0a015fa07` | `3f4125c0a015fa05` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:83` | `0.00059352311` | `3f4372d52c663e3a` | `3f4372d52c663e39` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:83` | `0.00063209358` | `3f44b662a086ba45` | `3f44b662a086ba43` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:83` | `0.00067317058` | `3f460ef6d017e640` | `3f460ef6d017e63f` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:84` | `0.00071691700` | `3f477def88d33c9a` | `3f477def88d33c97` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:84` | `0.00076350630` | `3f4904c14b5d7837` | `3f4904c14b5d7836` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:84` | `0.00081312324` | `3f4aa4f8dc98f254` | `3f4aa4f8dc98f253` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:84` | `0.00086596457` | `3f4c603cc0fa806c` | `3f4c603cc0fa806a` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:85` | `0.00092223983` | `3f4e384ef45771da` | `3f4e384ef45771d6` | +4 | A-audio-decode |
| `examples/z98/z9play/floor.zig:85` | `0.00098217216` | `3f501787539976b6` | `3f501787539976b3` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:85` | `0.0010459992` | `3f51233d16c2d75b` | `3f51233d16c2d759` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:85` | `0.0011139742` | `3f524058b07c5165` | `3f524058b07c5163` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:86` | `0.0011863665` | `3f536ffb5463735d` | `3f536ffb5463735c` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:86` | `0.0012634633` | `3f54b35963679132` | `3f54b35963679130` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:86` | `0.0013455702` | `3f560bbb0038e363` | `3f560bbb0038e360` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:86` | `0.0014330129` | `3f577a7de2936477` | `3f577a7de2936475` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:87` | `0.0015261382` | `3f5901166a1f8f87` | `3f5901166a1f8f85` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:87` | `0.0016253153` | `3f5aa11103c9be45` | `3f5aa11103c9be43` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:87` | `0.0017309374` | `3f5c5c13e19026a2` | `3f5c5c13e190269f` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:87` | `0.0018434235` | `3f5e33e0e94a9812` | `3f5e33e0e94a9810` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:88` | `0.0019632195` | `3f60152b71840cfe` | `3f60152b71840cfc` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:88` | `0.0020908006` | `3f6120ba0661f407` | `3f6120ba0661f405` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:88` | `0.0022266726` | `3f623dabbfde6831` | `3f623dabbfde6830` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:88` | `0.0023713743` | `3f636d21e21517f3` | `3f636d21e21517f1` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:89` | `0.0025254795` | `3f64b0507b7eb7a8` | `3f64b0507b7eb7a7` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:89` | `0.0026895994` | `3f66087faecb7fd4` | `3f66087faecb7fd2` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:89` | `0.0028643847` | `3f67770cd3825b82` | `3f67770cd3825b80` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:89` | `0.0030505286` | `3f68fd6c12520618` | `3f68fd6c12520615` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:90` | `0.0032487691` | `3f6a9d29a12d1994` | `3f6a9d29a12d1990` | +4 | A-audio-decode |
| `examples/z98/z9play/floor.zig:90` | `0.0034598925` | `3f6c57eba4535bf5` | `3f6c57eba4535bf3` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:90` | `0.0036847358` | `3f6e2f73782c3d77` | `3f6e2f73782c3d74` | +3 | A-audio-decode |
| `examples/z98/z9play/floor.zig:90` | `0.0039241906` | `3f7012cfe4a4f2cf` | `3f7012cfe4a4f2ce` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:91` | `0.0041792066` | `3f711e373ab94053` | `3f711e373ab94051` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:91` | `0.0044507950` | `3f723aff2f758e79` | `3f723aff2f758e77` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:91` | `0.0047400328` | `3f736a48ddba3bef` | `3f736a48ddba3bee` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:91` | `0.0050480668` | `3f74ad481d063d61` | `3f74ad481d063d5f` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:92` | `0.0053761186` | `3f760544d9100b99` | `3f760544d9100b98` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:92` | `0.0057254891` | `3f77739c470279d7` | `3f77739c470279d6` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:92` | `0.0060975636` | `3f78f9c243f4dbe8` | `3f78f9c243f4dbe6` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:92` | `0.0064938176` | `3f7a9942e37db3fa` | `3f7a9942e37db3f8` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:93` | `0.0069158225` | `3f7c53c3f766287f` | `3f7c53c3f766287e` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:93` | `0.0073652516` | `3f7e2b06abfb21f5` | `3f7e2b06abfb21f3` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:94` | `0.0088964928` | `3f8238530d003428` | `3f8238530d003426` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:94` | `0.009474637` | `3f8367704073a75d` | `3f8367704073a75b` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:94` | `0.010090352` | `3f84aa401ec2d293` | `3f84aa401ec2d292` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:94` | `0.010746080` | `3f86020a714816c7` | `3f86020a714816c5` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:95` | `0.011444421` | `3f87702c2f554f8b` | `3f87702c2f554f8a` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:95` | `0.013823725` | `3f8c4f9cf6456c1c` | `3f8c4f9cf6456c1b` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:96` | `0.014722068` | `3f8e269a84b7458e` | `3f8e269a84b7458d` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:96` | `0.015678791` | `3f900e19da57e0fa` | `3f900e19da57e0f9` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:96` | `0.016697687` | `3f911932ce55db4c` | `3f911932ce55db4b` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:96` | `0.017782797` | `3f9235a74e2f854c` | `3f9235a74e2f854b` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:97` | `0.018938423` | `3f9364980db0f636` | `3f9364980db0f635` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:97` | `0.021479854` | `3f95fed099cfb92c` | `3f95fed099cfb92a` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:97` | `0.022875735` | `3f976cbc96c9b090` | `3f976cbc96c9b08e` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:98` | `0.024362330` | `3f98f2704a6add46` | `3f98f2704a6add44` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:98` | `0.025945531` | `3f9a91771c7d4a6c` | `3f9a91771c7d4a6a` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:98` | `0.027631618` | `3f9c4b767e950efb` | `3f9c4b767e950ef9` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:98` | `0.029427276` | `3f9e222f101f1831` | `3f9e222f101f182f` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:99` | `0.031339626` | `3fa00bbf597a4d59` | `3fa00bbf597a4d57` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:99` | `0.033376252` | `3fa116b12d9b29fa` | `3fa116b12d9b29f9` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:99` | `0.035545228` | `3fa232fbef93e5eb` | `3fa232fbef93e5ea` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:99` | `0.037855157` | `3fa361c04a999276` | `3fa361c04a999274` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:100` | `0.040315199` | `3fa4a4319a7934ef` | `3fa4a4319a7934ed` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:100` | `0.042935108` | `3fa5fb97296ba302` | `3fa5fb97296ba300` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:100` | `0.045725273` | `3fa7694d904576c7` | `3fa7694d904576c6` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:100` | `0.048696758` | `3fa8eec80e0ffce9` | `3fa8eec80e0ffce7` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:101` | `0.051861348` | `3faa8d92132c4676` | `3faa8d92132c4674` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:101` | `0.055231591` | `3fac4750aa1a22f6` | `3fac4750aa1a22f4` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:101` | `0.058820850` | `3fae1dc4362555fd` | `3fae1dc4362555fb` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:101` | `0.062643361` | `3fb0096532ce7838` | `3fb0096532ce7837` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:102` | `0.066714279` | `3fb1142fde7b3137` | `3fb1142fde7b3135` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:102` | `0.071049749` | `3fb23050fc5810f5` | `3fb23050fc5810f4` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:102` | `0.075666962` | `3fb35ee8f72d7c19` | `3fb35ee8f72d7c18` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:102` | `0.080584227` | `3fb4a12afb89d739` | `3fb4a12afb89d737` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:103` | `0.085821044` | `3fb5f85e3149e031` | `3fb5f85e3149e02f` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:103` | `0.091398179` | `3fb765defdb80d60` | `3fb765defdb80d5e` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:103` | `0.097337747` | `3fb8eb20680804bc` | `3fb8eb20680804ba` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:103` | `0.10366330` | `3fba89ad934ba1c0` | `3fba89ad934ba1bf` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:104` | `0.11039993` | `3fbc432b78d4a80e` | `3fbc432b78d4a80d` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:104` | `0.11757434` | `3fbe195a192616c2` | `3fbe195a192616c0` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:104` | `0.12521498` | `3fc0070b6208dea2` | `3fc0070b6208dea1` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:105` | `0.14201813` | `3fc22da66be50077` | `3fc22da66be50075` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:105` | `0.15124727` | `3fc35c120f213028` | `3fc35c120f213026` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:105` | `0.16107617` | `3fc49e24d9284fd6` | `3fc49e24d9284fd5` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:105` | `0.17154380` | `3fc5f525b16a70b8` | `3fc5f525b16a70b7` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:106` | `0.18269168` | `3fc76270e36cf750` | `3fc76270e36cf74f` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:106` | `0.19456402` | `3fc8e7794b706bcf` | `3fc8e7794b706bce` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:106` | `0.20720788` | `3fca85c9ae096835` | `3fca85c9ae096834` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:107` | `0.23501402` | `3fce14f07d0030d3` | `3fce14f07d0030d2` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:107` | `0.25028656` | `3fd004b1eb75038e` | `3fd004b1eb75038d` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:107` | `0.28387361` | `3fd22afc37c96ff7` | `3fd22afc37c96ff6` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:108` | `0.30232132` | `3fd3593b859225b3` | `3fd3593b859225b2` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:108` | `0.32196786` | `3fd49b1f154409f2` | `3fd49b1f154409f0` | +2 | A-audio-decode |
| `examples/z98/z9play/floor.zig:108` | `0.34289114` | `3fd5f1edae18d793` | `3fd5f1edae18d792` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:108` | `0.36517414` | `3fd75f035b294676` | `3fd75f035b294675` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:109` | `0.38890521` | `3fd8e3d2ad8c6ab3` | `3fd8e3d2ad8c6ab2` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:109` | `0.41417847` | `3fda81e669d6de4a` | `3fda81e669d6de49` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:109` | `0.44109412` | `3fdc3ae2d4f6e7d4` | `3fdc3ae2d4f6e7d3` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:109` | `0.46975890` | `3fde1087a22050d9` | `3fde1087a22050d8` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:110` | `0.50028648` | `3fe00258cac76401` | `3fe00258cac76402` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:110` | `0.53279791` | `3fe10cae33da7807` | `3fe10cae33da7806` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:110` | `0.56742212` | `3fe228526f0da9e1` | `3fe228526f0da9e2` | -1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:110` | `0.60429640` | `3fe356656762e5a9` | `3fe356656762e5a8` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:111` | `0.68538959` | `3fe5eeb626423403` | `3fe5eeb626423402` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:111` | `0.72993007` | `3fe75b964e608b31` | `3fe75b964e608b30` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:112` | `0.88168307` | `3fec36bf69e2c7b7` | `3fec36bf69e2c7b6` | +1 | A-audio-decode |
| `examples/z98/z9play/floor.zig:112` | `0.9389798` | `3fee0c1f5d93590f` | `3fee0c1f5d93590e` | +1 | A-audio-decode |
| `examples/z98/z9play/tests/dsp_test.zig:116` | `0.75` | `3fe8000000000001` | `3fe8000000000000` | +1 | B-app-test |
| `examples/z98/z9play/tests/dsp_test.zig:120` | `0.75` | `3fe8000000000001` | `3fe8000000000000` | +1 | B-app-test |
| `examples/z98/z9play/tests/dsp_test.zig:145` | `0.0009460463` | `3f4f0002f5a1d9e7` | `3f4f0002f5a1d9e4` | +3 | B-app-test |
| `examples/z98/z9play/tests/dsp_test.zig:146` | `0.0085006468` | `3f8168c98001bc1b` | `3f8168c98001bc1a` | +1 | B-app-test |
| `examples/z98/z9play/tests/dsp_test.zig:148` | `0.9999995525` | `3fefffff0fc0117f` | `3fefffff0fc0117e` | +1 | B-app-test |
| `examples/z98/z9play/tests/floor_test.zig:283` | `1.0649863e-07` | `3e7c9687b6622afa` | `3e7c9687b6622afb` | -1 | B-app-test |
| `examples/z98/z9play/tests/floor_test.zig:287` | `0.00031622787` | `3f34b96c5c1782a8` | `3f34b96c5c1782a7` | +1 | B-app-test |
| `examples/z98/z9play/tests/floor_test.zig:288` | `0.00033677814` | `3f36123318e92878` | `3f36123318e92876` | +2 | B-app-test |
| `examples/z98/z9play/tests/setup_test.zig:119` | `0.000001` | `3eb0c6f7a0b5ed8f` | `3eb0c6f7a0b5ed8d` | +2 | B-app-test |
| `repro/mi_matrix/lexer_float_exponent_xmod/main.zig:43` | `1.0e300` | `7e37e43c8800759d` | `7e37e43c8800759c` | +1 | E-fixture-tol |
| `repro/mi_matrix/lexer_float_exponent_xmod/main.zig:44` | `1e300` | `7e37e43c8800759d` | `7e37e43c8800759c` | +1 | E-fixture-tol |
| `repro/mi_matrix/lexer_float_exponent_xmod/main.zig:50` | `0.0014` | `3f56f0068db8bac9` | `3f56f0068db8bac7` | +2 | E-fixture-tol |
| `repro/mi_matrix/lexer_float_exponent_xmod/main.zig:50` | `0.0016` | `3f5a36e2eb1c432e` | `3f5a36e2eb1c432d` | +1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_comptime_float_compare_xmod/main.zig:54` | `0.3` | `3fd3333333333334` | `3fd3333333333333` | +1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:77` | `0.0137` | `3f8c0ebedfa43fe8` | `3f8c0ebedfa43fe6` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:78` | `0.0071` | `3f7d14e3bcd35a88` | `3f7d14e3bcd35a86` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:78` | `1.75` | `3ffc000000000001` | `3ffc000000000000` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:84` | `0.0137` | `3f8c0ebedfa43fe8` | `3f8c0ebedfa43fe6` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:85` | `0.0071` | `3f7d14e3bcd35a88` | `3f7d14e3bcd35a86` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:85` | `1.75` | `3ffc000000000001` | `3ffc000000000000` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:86` | `0.0033` | `3f6b089a02752548` | `3f6b089a02752546` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:97` | `0.017` | `3f916872b020c49d` | `3f916872b020c49c` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:98` | `0.011` | `3f86872b020c49bc` | `3f86872b020c49ba` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:99` | `0.0001` | `3f1a36e2eb1c432f` | `3f1a36e2eb1c432d` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:101` | `0.001` | `3f50624dd2f1a9fd` | `3f50624dd2f1a9fc` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:112` | `0.021` | `3f95810624dd2f1c` | `3f95810624dd2f1b` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:113` | `0.013` | `3f8a9fbe76c8b43b` | `3f8a9fbe76c8b439` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:113` | `0.75` | `3fe8000000000001` | `3fe8000000000000` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:118` | `0.021` | `3f95810624dd2f1c` | `3f95810624dd2f1b` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:119` | `0.013` | `3f8a9fbe76c8b43b` | `3f8a9fbe76c8b439` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:119` | `0.75` | `3fe8000000000001` | `3fe8000000000000` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:120` | `0.009` | `3f826e978d4fdf3d` | `3f826e978d4fdf3b` | +2 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:140` | `0.08` | `3fb47ae147ae147c` | `3fb47ae147ae147b` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_noise_basic_xmod/main.zig:140` | `0.08` | `3fb47ae147ae147c` | `3fb47ae147ae147b` | +1 | D-fixture-golden |
| `repro/mi_matrix/stdlib_parse_ftoa_xmod/main.zig:38` | `0.001` | `3f50624dd2f1a9fd` | `3f50624dd2f1a9fc` | +1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_parse_parsefloat_xmod/main.zig:26` | `0.0000001` | `3e7ad7f29abcaf4c` | `3e7ad7f29abcaf48` | +4 | E-fixture-tol |
| `repro/mi_matrix/stdlib_parse_stress_xmod/main.zig:81` | `0.000001` | `3eb0c6f7a0b5ed8f` | `3eb0c6f7a0b5ed8d` | +2 | E-fixture-tol |
| `repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod/main.zig:142` | `1e-308` | `000730d67819e8d3` | `000730d67819e8d2` | +1 | E-fixture-tol |
| `repro/mi_matrix/stdlib_rand_stat_xmod/main.zig:73` | `0.0001` | `3f1a36e2eb1c432f` | `3f1a36e2eb1c432d` | +2 | E-fixture-tol |
| `repro/mi_matrix/stdlib_rand_stat_xmod/main.zig:94` | `16.81` | `4030cf5c28f5c290` | `4030cf5c28f5c28f` | +1 | E-fixture-tol |
| `sf/src/std_noise.zig:39` | `0.3660254037844389` | `3fd76cf5d0b0995b` | `3fd76cf5d0b09959` | +2 | C-lexer-workaround |
| `sf/src/std_noise.zig:40` | `0.16666666666666664` | `3fc5555555555555` | `3fc5555555555554` | +1 | C-lexer-workaround |

## 5. Migration list for Tasks 1B / 1C / 1D

### 5.1 Task 1B (lexer fix) — new permanent pin

- **Create** `repro/mi_matrix/lexer_float_rounding_xmod/{main.zig,expected.txt,expected.rc}`
  pinning the §3 table (all 7 mandated values + the `1e300`/`1.0e300` pair), printing
  `lexer float round ok` with rc 0 only on full match. Run RED before the fix (record the failure),
  GREEN after.
- **Verify unchanged after fix:** `repro/mi_matrix/lexer_float_exponent_xmod` (its asserts are
  relative: `big == big_ref`, `small` in `(0.0014, 0.0016)` window — all four mismatched literals
  there move consistently; measured to stay green).
- **Compiler self-build** must succeed; `sf/src/lexer.zig` self-tests only assert token kinds
  (`lexer.zig:898-905`) — value-free, unaffected.

### 5.2 Definite movers (must change in 1C/1D — proven or provable)

1. **z9play byte-exact PCM pins** (floor.zig table feeds the Vorbis decode path):
   - `examples/z98/z9play/tests/tier_decode.sh:173` `EXACT_MD5="e7f24870ec03b924be1b8e55a1962fb3"`
     (sine_stereo_44100 `--pcm` byte-exact pin).
   - `examples/z98/z9play/tests/tier_stream.sh:261` `PCM_MD5="e7f24870ec03b924be1b8e55a1962fb3"`
     (`--pcm` regression pin, 352,844 bytes).
2. **`--dump-c89` md5 pins** (C89 text embeds the f64 decimals; z9play's compile unit contains
   207 mismatched literals):
   - `examples/z98/z9play/README.md` (current M9 Linux pins `23f9b5ec...`/`76d0fc83...` and `-osw`
     pins `6cd349b5...`/`294e3fde...`; historical pin prose).
   - `examples/z98/z9play/NOTES.md:9,209-218,242,1091-1094` (MD5 section + current pins).
   - `docs/sf/QUICK_REF.md:338` (`ui.zig --dump-c89` = `e7bc57a2a38a72cb83f51a1ce7497239`).
   - `examples/z98/z9play/demo/win9x_README.txt:61` (`ad9ccfd34aa2ba26c38abbcf48eedeb0`).
3. **`repro/mi_matrix/stdlib_noise_basic_xmod/expected.txt`** — `pgm fnv1a64 4921c94f3ec08543`.
   20 mismatched coordinate literals in the fixture + the 2 `std_noise` constants (restored in 1D)
   change every sampled `noiseFbm2d` value. Re-capture the hash (plan 1D step 2 says re-capture
   only this PGM hash).
4. **`sf/src/std_noise.zig`** (1D step 1): restore `0.366025403784439` and
   `-0.16666666666666666`; delete the compensating comment (`std_noise.zig:35-38`).
5. **Seed artifacts + fixed-point pins** (1C rotates v104 because `lexer.zig` changes the compiler
   binary, so the self-build fixed point moves off `b299b4b435e624d0ddbd2edde681cbc3`):
   - `release/seed/zig1-seed.tgz`, `release/seed/CHANGELOG.md` (v104 in 1C, v105 in 1D).
   - Hardcoded seed-md5 asserts: `examples/z98/z9play/tests/tier_flac.sh:110`,
     `tier_stream.sh:112`, `tier_tui.sh:102` (all pin `b299b4b4...` as "v102 fixed point").
   - `examples/z98/z9play/demo/win9x_README.txt:25-26` (md5 + two-hop closure).
   - `docs/sf/QUICK_REF.md` seed section (all `b299b4b4...` fixed-point occurrences, archive md5s,
     `lib/` 33-file count), `examples/z98/z9play/NOTES.md:18,22,811-818,963,986,1040` seed prose.
   - 1D v105: lib payload changes (`std_noise.zig`) but the fixed point **must equal Task 1C's**
     (std_noise is not linked into the compiler binary — verified: no `sf/src` module imports it).
6. **Truth-ups (docs):** `examples/torrent_example_defects.md:254` D6 status -> FIXED (1D step 3);
   `sf/docs/std_lib/noise.md` noise docs; `docs/sf/QUICK_REF.md` counts/pins.
7. **`scripts/seed/archive_seed.sh`** — interim std count prose `33` -> `34` (plan 1C step 4;
   `std_noise.zig` already in the copy lists).

### 5.3 Rerun-only (assertions are tolerance/relative; expected still green — re-run, do not rewrite)

- **Vorbis PCM goldens `examples/z98/z9play/testdata/expected/*.pcm` are `oggdec` reference
  oracles** (`tests/tier_decode.sh:1-22` compares by tolerance, max|delta| <= 2 LSB, RMS <= 0.1
  LSB; exact SHA-1 is informational). **Do not rewrite these goldens.** After the fix the decode
  gets closer to the spec (the table becomes correctly rounded), so tolerance margins should
  improve; if any tolerance compare regresses, escalate — that would be a new defect, not a golden
  update. Same for `tests/tier_audio.sh` (tolerance vs M3 goldens).
- `examples/z98/z9play/tests/tier_flac.sh` — FLAC is lossless over the same goldens; floor.zig is
  Vorbis-only. Expect unchanged green.
- `examples/z98/z9play/tests/dsp_test.zig`, `floor_test.zig`, `setup_test.zig` — tolerance asserts
  over B-class literals.
- `repro/mi_matrix/lexer_float_exponent_xmod` — asserts stay green (all four mismatched literals
  are compared relatively/tolerantly). **Comment truth-up needed:** the header claims `1e300`
  "parses correctly" — false (it is 1 ULP high; only its *exponent* is no longer dropped). Not in
  any plan Files list (flagged in §6).
- `repro/mi_matrix/stdlib_comptime_float_compare_xmod` — `MTHIRD < 0.5` and `1.5e1 == 15.0` stay
  true (`0.3` shifts 1 ULP, still < 0.5); stdout contract unchanged.
- `repro/mi_matrix/stdlib_parse_ftoa_xmod`, `stdlib_parse_parsefloat_xmod`,
  `stdlib_parse_stress_xmod` — tolerance compares (`d < 0.001`, `d < 0.0000001`) dwarf the <=4 ULP
  shifts.
- `repro/mi_matrix/stdlib_rand_stat_xmod` — chi2 threshold `16.81` and `0.0001` shift 1-2 ULP;
  statistical asserts keep large margins.
- `repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod` — the `1e-308` literal is mismatched, but the
  pinned `d8=0x0.00000000316a2p-1022` line is **measured invariant** under the fix: `1e-308/1e10`
  rounds to the same f64 from either numerator (verified both ways). Re-verify; no pin change
  expected. (Initially classed as a definite mover; measurement downgraded it.)
- `repro/mi_matrix/comptime_float_compare_reject_xmod` — `18446744073709551616.0` (2^64) parses
  correctly today and must keep doing so (inexact-significand reject shapes must stay rejected).
- `scripts/stdlib/vectors/std_noise/grid.expected` — **must stay byte-identical** (Task 1D step 2
  invariant; it pins `noise2d`/`noise3d` bits of the reference algorithm).
- `stdlib_test/*` — 0 decimal float literals; nothing to do.
- All other `repro/mi_matrix` fixtures and all other `examples/z98` apps — no mismatched literals;
  their dumps and outputs are invariant.

### 5.4 Sequencing hazard (1B -> 1D window)

After 1B alone, `sf/src/std_noise.zig`'s workaround literals flip meaning:
`0.3660254037844389` -> `3fd76cf5d0b09959` (2 ULP low of intended) and
`0.16666666666666664` -> `3fc5555555555554` (1 ULP low of intended). Until 1D restores the
canonical spellings, `stdlib_noise_cross_xmod` vs `grid.expected` and the `stdlib_noise_basic`
PGM hash **fail**. This is expected: 1C's battery records these as movers and must NOT "fix" them;
1D step 1-2 owns them. The plan's ordering (1B fix -> 1C z9play+seed -> 1D std_noise) already
encodes this.

### 5.5 What must NOT change

- `examples/z98/z9play/floor.zig` — spec text; no edit (Task 1A condition answered).
- `scripts/stdlib/vectors/std_noise/grid.expected` — reference oracle output.
- `examples/z98/z9play/testdata/expected/*.pcm` — `oggdec`/source oracles.
- `repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod/expected.txt` — measured invariant.
- `run.err` (untracked), and every tracked file in this task (report-only).

## 6. Concerns

1. **Plan gap — seed-md5 asserts:** Task 1C's Files list names `tier_decode.sh`/`tier_stream.sh`
   but not `tier_flac.sh:110` or `tier_tui.sh:102`, which also hardcode
   `b299b4b435e624d0ddbd2edde681cbc3`. They must move with the v104 fixed point. Operator should
   widen 1C's Files or fold them into "as measured".
2. **Plan gap — comment truth-ups:** `lexer_float_exponent_xmod` header (false "parses correctly"
   claim about `1e300`) and `sf/src/std_math.zig:208` ("the lexer's decimal-float parser is not
   correctly rounded") need truth-ups after 1B; neither appears in 1B/1C/1D Files lists.
   `std_math.zig` itself builds constants from exact bit patterns (`@ptrCast`) and needs no code
   change.
3. **`stdlib_print_ptr_hexfloat_xmod` pin is invariant only because of a second rounding**
   (`1e-308 / 1e10` absorbs the 1-ULP numerator shift). If 1B ever adds constant folding of
   division, re-measure; do not assume.
4. **`floor.zig` currently ships up to 4-ULP-wrong table entries** (198 of 256). After 1B the
   decode becomes spec-correct and every byte-exact z9play pin moves. The oggdec-tolerance
   compares should tighten, not loosen; any looseness is a red flag.
5. **Fixed-point claim in plan 1D** ("must equal Task 1C's fixed point") depends on `std_noise.zig`
   staying out of the compiler link closure — verified today (no `sf/src` imports it), but if a
   future change imports std_noise into the compiler, 1D would move the binary too.
6. **Scanner scope** is `.zig` only (matches the baseline exactly: 1,061/240/13). Decimal floats in
   `.c`/`.h` under those trees are gcc-parsed and unaffected by the Z98 lexer; no Z98-side risk.

## 7. Commits

- This report only: `docs(sdd): M2 T1A investigation report` (`git add -f` on
  `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1a-report.md`).
- No code/fixture/seed changes. No push. `run.err` left untracked and untouched.

## 8. Evidence index (scratch, outside the repo)

- `/tmp/t1a_work/a.zig` + `out/a_82688E3E.c` — Step 2 repro dump.
- `/tmp/t1a_work/oracle.c` — `gcc -m32 -std=c89` `strtod` oracle (7 mandated values + emitted texts).
- `/tmp/t1a_work/scan.py` — inventory scanner (lexer-faithful `parseF64` mirror + tokenizer).
- `/tmp/t1a_work/inventory.json` — all 240 mismatch rows (source of the table above).
- `/tmp/t1a_work/b.zig` + `out2/` + `oracle2.c` — end-to-end scanner validation vs the real compiler.
- `/tmp/t1a_work/c.zig` + `out3/` — path-isolation probes (`0.75`, `1e300`, `1.5e-3`, long integers).
