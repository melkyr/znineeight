# M2 Task 1AEx report — Decimal→f64 Algorithm Methodology Decision

**Status:** DONE — RECOMMENDATION LOCKED: **Clinger exact fast path + Simple Decimal Conversion (SDC) fallback, single round-to-nearest-even**
**Branch:** `zig1_improvements`
**Plan:** `docs/superpowers/plans/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan.md` Task 1AEx
**Context:** `.superpowers/sdd/2026-10-19-z98-std-algorithms-m2-noise-lz4-plan/task-1aex-context.md`
**Consumes:** Task 1A report (root cause, correct-value table, 240/1061 inventory); `sf/src/lexer.zig:610-670` `parseF64`
**Scope:** research + recommendation report only. No source, fixture, seed, or tracked-file edits (this report is the only addition).
**Operator rule honored:** best *modern* approach, not era-accurate. Goal: definitive — rounding methodology is never revisited after Task 1B.

---

## 1. Survey of modern decimal→f64 approaches

All correct algorithms share one skeleton: represent the literal as the **exact** finite decimal `D = m × 10^e10`, then produce `RNE_round_53(D)` — one rounding of the exact value to f64 precision, ties-to-even. Divergence is only in *how* the exact value is carried and where provably-safe shortcuts fire.

### (a) Clinger fast path + bignum fallback (glibc `strtod` class)

- **Fast path** (Clinger, "How to Read Floating Point Numbers Accurately", PLDI 1990): if the integer significand `m < 2^53` and `|e10| ≤ 22` (10^0..10^22 are the exact powers of ten in f64; 5^23 > 2^53), compute `f64(m) × 10^e10` or `f64(m) / 10^|e10|` as a **single IEEE operation on two exact operands**. IEEE mul/div rounds the exact product/quotient once, so the result is by construction `RNE_round_53(D)`. "Disguised" variant: fold small powers of ten from `e10` into `m` while `m` stays < 2^53 (extends coverage of the fast path without new rounding).
- **Fallback:** exact multi-precision computation of `m × 10^e10` (binary bignum: limbs, pow10 table or repeated mul; glibc also uses big *division* for `10^-k`), normalize, extract 53 bits + round bit + sticky, one round-to-nearest-even.
- **Guarantee:** correctly rounded for all inputs, given a correct fallback. Fast path hit rate on real code is very high (see §2).

### (b) Eisel-Lemire 2020 (Rust `str::parse::<f64>`, Go `ParseFloat`, Zig middle tier)

- Multiply the normalized truncated significand (≤ 19 decimal digits, fits u64) by a precomputed 64-bit (then 128-bit refined) approximation of `10^e10`; a 128-bit product `W` brackets the true value; rounding-range tests decide the 53-bit RNE result unless the case is ambiguous (half-way neighborhoods where the table error could flip the rounding).
- **Not comprehensive alone.** Fallback required for: mantissa > 19 digits (or > u64), exponents outside the table range (e.g. −325..308 or the tighter −307..288), and the ~0.5–1% ambiguous cases (exact-half neighborhoods, `many_digits` inputs). Zig re-runs EL with `mantissa+1` before falling back.
- **Cost:** 64×64→128 multiply as the core primitive (native u128 on modern hosts; emulatable with four u32×u32→u64 cross products), plus a ~697-row × 2×u64 power-of-ten table ≈ **11 KB**. Core ≈ 80 lines + 700 lines table (Go 1.16 numbers).
- **Guarantee:** correctly rounded **only** combined with a fallback.

### (c) Simple big-integer / Simple Decimal Conversion (SDC)

Two flavors of the same skeleton — carry the exact value as an integer, scale it exactly, round once:

- **Binary bignum flavor** (glibc's actual fallback): exact `m × 10^e10` in base-2^32/2^64 limbs; for negative exponents either divide (`m / 5^k`, keep 54+ quotient bits + remainder-nonzero sticky — glibc's hand-rolled mpn division) or multiply the numerator and compare. Needs bignum mul, shift, compare, and division.
- **Decimal bignum flavor = SDC** (Nigel Tao & Ken Thompson, "Processing Long Numbers Quickly", arXiv 2101.11408; Tao blog 2020-11-02): an **HPD** (high-precision decimal) = exact decimal digit string (`digits[800]`, `decimal_point`, `truncated` sticky flag). Scaling uses only exact non-truncating shifts: divide-by-2^S = multiply digits by 5^S and move the decimal point (`D/2 = (D×5)×10^(dp−1)`), implemented either as 1-bit ×2 / ×5-with-point-move passes or as ≤60-bit sliding-window passes with a u64 accumulator (each produced digit exact). Scale to `[½, 1)` (or `[1, 2)`), scale to 53/54 significant bits, round once with round bit + sticky (`truncated` distinguishes "exact half" from "half and a little bit more"). No bignum multiply, no division, no pow10 table.
- Used as the always-correct core/fallback by: Go `strconv` (SDC since 2008, now also EL tier), Wuffs (fallback), Zig `std.fmt.parseFloat` (`convertSlow`).
- **Guarantee:** correctly rounded for **all** f64 (normals, subnormals, ±0, overflow/underflow) by single-rounding of the exact value. The 767-digit bound (Handbook of Floating Point Arithmetic; Zig uses `max_digits = 768`) is the exact number of decimal digits that can participate in a worst-case f64 tie; 800 digits (Tao's buffer) is a safe margin. Digits beyond the cap only set the sticky flag.

### (d) x87 80-bit extended (PII/PIII native)

- 64-bit mantissa gives one extra rounding beyond f64's 53 bits → **double rounding** (80-bit round, then 64→53 round) is not IEEE-correct in general; classic halfway counterexamples exist where the first rounding lands exactly on a 53-bit tie and ties-to-even then picks the wrong neighbor.
- 80-bit still cannot hold `10^k` exactly for large k, and long digit strings still need exact machinery — i.e. the bignum fallback is required anyway (this is why glibc's long-double tricks always had an mpn path behind them).
- Platform-dependent by definition. The project already treats x87 excess precision as a *hazard*: `sf/src/std_math.zig:208` forces statement-level f64 stores so "x87 80-bit excess precision cannot leak into the result" for reproducibility. An x87-based parser would reintroduce exactly that non-determinism and violate "no platform dependency".
- **Verdict: rejected.**

### (e) Steele & White / Dragon inverse

- Steele & White 1990 is the *ftoa* direction (Dragon, shortest representation). The read direction is Clinger 1990 (a) and David Gay's `gdtoa` — exact bignum with unbounded scale/compare intervals. Historically important; strictly more machinery than SDC for the same guarantee. Superseded.
- **Verdict: historical reference only.**

---

## 2. PII/PIII tradeoff analysis (Z98→C89, 200–400 MHz, 16–32 MB RAM, no u128/generics/libc, no f64 `@bitCast`)

Target workload: **compile-time** literal parsing in the zig1 lexer (`parseF64` called from `lexerScanNumber`, `sf/src/lexer.zig:422`). The whole tracked corpus is 1,061 decimal float literals; per-compilation counts are small. This is not a GB/s parsing service — throughput algorithms buy almost nothing here.

| approach | code size (Z98→C89) | stack/arena (800-digit worst case) | speed on PII/III | correct for ALL f64 | Z98 complexity |
|---|---|---|---|---|---|
| (a) Clinger fast + **binary bignum** fallback | fast ~40 lines; fallback 350–500 lines + pow10 tables 4–8 KB | ~700 B limbs + scratch ≈ 1.5 KB | fast path ~100% of real literals (µs); fallback ~0.1–10 ms | YES (single rounding) | bignum mul/shift/compare; big **division** for `10^-k` is the hard part; no u128 needed if base-2^32 limbs |
| (b) Eisel-Lemire | core ~150–200 lines + **11 KB table** + u64×u64→u128 emulation ~40 lines | trivial | fastest fallback-free tier, but irrelevant at compile-time scale | NO alone — fallback mandatory | u128 emulation (4×u32 muls per 64×64→128), table generation/validation, ambiguity checks |
| (c) **SDC (decimal)** + Clinger fast path | fast ~40 lines; SDC ~230–280 lines; no large tables | HPD 800 B (+ optional 800 B scratch) ≈ **0.9–1.7 KB** | fast path ~100% of real literals; SDC worst pathological 800-digit literal ~15k–440k digit-ops (≈ 0.1–3 ms @ 300 MHz) | YES (single rounding) | u8 digit array + u64-window shifts + integer round; **no mul/div tables, no u128**; `@ptrCast` u64↔f64 exactly like `sqrtD2B` (`sf/src/std_math.zig:78`) |
| (d) x87 80-bit | small | trivial | fast | **NO** (double rounding; residual cases need bignum anyway) | platform-specific; fights the project's x87-determinism policy |
| (e) Steele & White / Dragon inverse | largest | ~1 KB bignums | slow-ish | YES | unbounded scaling loops + exact bignum; most code of all options |

Key observations:

- **Fast-path hit rate on this corpus is effectively 100% for the common shapes.** Every 8-significant-digit scientific literal in `floor.zig` (e.g. `1.0649863e-07` → m=10649863 < 2^53, e10=−14) hits the Clinger fast path. Of Task 1A's 8 mandated repro rows, 5 hit the fast path (`0.366025403784439`, `0.3`, `0.75`, `1.75`, and the unsigned half of the `0.166...` case once re-spelled) and 3 must use the fallback (`0.16666666666666666` — m=16666666666666666 > 2^53; `1e300`; `1e-308`).
- **Eisel-Lemire is the wrong tier for this machine-set.** Its value is parse throughput; its cost here is u128 emulation + 11 KB table + one more correctness surface — and the fallback it sits on is still mandatory. When the fallback is mandatory anyway, the only question is which fallback is cheapest to make provably right in Z98.
- **SDC is the cheapest provably-right fallback in Z98.** Binary bignum needs multiplication and (for `10^-k`) division; SDC needs only digit-string ×2 / ×5-with-decimal-point moves (or ≤60-bit sliding windows with a u64 accumulator), which are exact digit rewrites. Everything is u8/u32/u64/i32 arithmetic — well inside the Z98 subset and C89 output.
- **Stack is bounded and static.** Worst-case 800-digit literals cost one ~800-byte HPD (+optional scratch) per call; lexer parses one literal at a time, no recursion. Trivial against 16–32 MB.
- **Precision guarantee:** both tiers of the recommended composite are independently `RNE_round_53(D)` (proof in §5), so the composite is correctly rounded for **all** f64 — the binding constraint.

---

## 3. How C solves it — glibc `strtod` and musl `strtod`

### glibc (`stdlib/strtod_l.c`, current master)

- **Algorithm class:** exact multi-precision (a), fallback flavor = binary bignum + big division. **No Eisel-Lemire** in glibc.
- Path: digits → `str_to_mpn` packs 9/19 decimal digits per limb (base 2^32/2^64, `_tens_in_limb`); positive decimal exponent folded in via exact `__tens` powers-of-ten table (`fpioconst.h`) with a bit-decomposed pow10 walk (`__mpn_mul` per set bit); then `bits > MANT_DIG` → slice out 53 bits + round limb + `more_bits` sticky → `round_and_return` (RNE via `round_away`, also honors the FP rounding mode). Negative exponent path builds the fraction `num/den` and runs a hand-rolled mpn long division ("quasi fix point") extracting `MANT_DIG+1` quotient bits plus `n != 0` sticky. Denormals get extra right-shifts in `round_and_return` (single rounding preserved).
- **Dependencies (all libc/platform):** GMP mpn internals (`__mpn_mul`, `__mpn_rshift`, `udiv_qrnnd`, `umul_ppmm` — 64×64→128 asm where available), the large `__tens` exact-pow10 table, locale machinery (decimal point, thousands grouping), errno/ERANGE conventions, `MPN_VAR` stack sizing derived from `FLT_*`. Correctly rounded, but **not liftable** into Z98: no libc, no GMP, no locale, and far too much code/table.

### musl (`src/internal/__floatscan.c`, `decfloat`)

- **Algorithm class:** decimal big-integer scaling + single rounding — the same family as (c), with a long-double final step. **No Eisel-Lemire** in musl either.
- Path: base-10^9 digit ring `uint32_t x[KMAX]` (KMAX = 128 or 2048 by long-double config); exact small-integer fast paths (`lrp==dc && dc<10` etc.); overflow/underflow early-outs; radix-point alignment by base-10^9 shifts; then scale by powers of two in 29-bit and 1-bit steps (up-scale by `x[k]<<29` base-10^9 carries; down-scale by `x[k]>>sh`) until the top chunks bracket the `LD_B1B_MAX` threshold = exactly `MANT_DIG` significant bits; assemble the top 2–3 chunks into a `long double` (exactly representable), remaining chunks fold into a `frac` sticky (±0.25/0.5/0.75 by tail digits), and the `bias` trick (`y += 2^(2·LDBL_MANT_DIG−bits−1)`, `y −= frac`) forces **one** rounding to the target precision; `scalbnl(y, e2)`.
- **Guarantee:** correctly rounded RNE (tail logic distinguishes exact-half from half-plus-epsilon; ties-to-even via `!fmodl(frac,1)` handling).
- **Dependencies:** `long double` with extra precision beyond the target (x87 80-bit for `double` on x86), `scalbnl`/`fmodl`/`copysignl`, FILE-based scanning (`shgetc`). Correct on its platforms; **not usable in Z98** (no libc, no long double contract, determinism policy).

Both C libraries confirm the modern consensus: **exact decimal/binary scaling + one rounding** is how "correct for all f64" is achieved; speed tiers are optional garnish.

## 4. How Zig solves it — `std.fmt.parseFloat`

Pipeline (`lib/std/fmt/parse_float.zig` + `convert_fast.zig` / `convert_eisel_lemire.zig` / `convert_slow.zig` / `decimal.zig`):

1. `parse.parseNumber` — significand, decimal exponent, `many_digits` flag (input truncated at 19 digits), hex-float branch.
2. `convertFast` — Clinger fast path with the disguised extension (`man × 10^k` folding via `fastIntPow10`, overflow-checked). Fires only when every input to the single IEEE mul/div is exact.
3. `convertEiselLemire` — 128-bit Eisel-Lemire; if `many_digits`, must agree on `mantissa` and `mantissa+1` before accepting.
4. `convertSlow` — **Simple Decimal Conversion**: `Decimal(T)` HPD with `max_digits = 768` for f64 (Handbook bound `−emin + p2 + ⌊(emin+1)·log2(10) − log(1−2^−p2, 10)⌋`), `truncated` sticky, `leftShift`/`rightShift` non-truncating digit shifts (≤60-bit windows, `powers[19]` shift table, pow5-lexicographic new-digit count), then `round()` to the 53-bit mantissa with round bit + sticky ties-to-even; subnormal/overflow bounds (`min_exponent = −324`, `max_exponent = 310`, `decimal_point_range = 2047`).

**Is it correctly rounded? Yes.** The docstrings state the fallback "will always determine how to round the significant digits to the nearest machine float, allowing us to handle near half-way cases", and the fast tiers are accepted only under provable exactness/ambiguity checks. Tests pin round-to-even, subnormals, max/min normals, and multi-hundred-digit inputs. Guarantee: `parseFloat` returns the IEEE-754 nearest f64 to the decimal value, ties-to-even, for **every** input — the same guarantee Task 1B must replicate without libc, u128, or generics.

Note: Zig's `convertSlow` is exactly SDC as recommended here; its `convertFast` is exactly the Clinger fast path. The only tier we deliberately skip is `convertEiselLemire`, for the §2 reasons.

---

## 5. CONCLUSION

### 5.1 The ONE recommended algorithm

**Clinger exact fast path + Simple Decimal Conversion (SDC) fallback — one rounding, round-to-nearest-even, end to end.**

- Tier 1 (fast, provable): significand `m < 2^53` and effective `e10 ∈ [−22, 22]` (plus the optional disguised folding `m ← m × 10^k` while `m < 2^53`) → single f64 mul or div by exact `10^|e10|`.
- Tier 2 (always correct): SDC — HPD 800 digits + `truncated` sticky; exact power-of-two scaling (×2 / ×5-with-decimal-point, or ≤60-bit windows); scale to 53/54 bits; single integer RNE rounding with round + sticky; subnormal precision clamp; overflow/underflow bounds; assemble bits via `@ptrCast` u64↔f64 (pattern already in `sf/src/std_math.zig:78-80`).

Rejected: x87 80-bit (double rounding + platform dependence + determinism policy); Dragon/Steele-White inverse (superseded, more code); Eisel-Lemire as a required tier (11 KB table + u128 emulation for compile-time scale; keep as an *optional future* middle tier for `std_parse` runtime throughput — it cannot change the answer, only get there faster). Binary-bignum fallback (glibc flavor) is correct but pays bignum mul + big division for no benefit at this scale.

### 5.2 Justification for PII/PIII + 16–32 MB

- **Correctness for all f64 is structural, not empirical** (proof below) — satisfies the binding "correctly rounded ALL f64" constraint and ends the rounding topic permanently.
- **Code size:** ~280–330 lines Z98 (~450–550 lines C89, est. 2.5–4 KB i386 code) with **no large tables** — the smallest correct option; Eisel-Lemire alone would add ~11 KB table + emulation.
- **Memory:** static ~0.9–1.7 KB stack per call, no heap/arena, worst-case 800-digit literal handled by cap + sticky. 16–32 MB is not a constraint.
- **Speed:** the Clinger fast path covers essentially all real corpus literals at ~100 cycles; SDC runs only on long/exotic literals at ~0.1–3 ms worst case on a 300 MHz PII — irrelevant at 1,061 literals/compile scale.
- **Z98 feasibility:** only u8 arrays, u32/u64 arithmetic, i32 exponents, bools, one struct, `@ptrCast` bit moves. No u128, no generics, no `@bitCast`, no libc, no new language surface.

### 5.3 Proof sketch of correct rounding (all f64)

Let `D` be the exact finite decimal value of the literal (digits + exponent), and let `RNE53(·)` denote one rounding to f64 with ties-to-even.

1. **Fast path.** Fires only when `D = m × 10^e` with integer `m < 2^53` and `10^|e|` exactly representable (`|e| ≤ 22`, or disguised-folded equivalently). Both IEEE operands are exact, and IEEE mul/div returns `RNE` of the exact result, so the result is `RNE53(D)` — a *single* rounding; double rounding is impossible with one operation.
2. **SDC.** The HPD holds `D` exactly except for low-order truncation past 800 significant digits, where `truncated` records `D > D'` (the kept prefix). Scaling steps are exact digit rewrites of multiplication/division by powers of two (`D/2 = (D×5)×10^(dp−1)`; window shifts emit exact digits), so after scaling we hold the exact value `D × 2^k` (plus sticky). Rounding extracts a 54-bit window, rounds to 53 bits using the round bit and sticky: an exact-half tie is recognized only when the next digit is 5, all further digits are zero, **and** `truncated` is clear (else "half and a bit more" rounds up). Subnormals are handled by additional exact right-shifts and rounding at the reduced precision `bits = clamp(53 + exp2 − emin)` — still one rounding of the exact value. Overflow to ±inf and underflow to ±0/subnormal occur only outside f64's representable bounds. Hence the result is `RNE53(D)` for all `D`, including 800+ digit literals, exact ties, subnormals, and ±0.
3. **Composite.** Both tiers compute `RNE53(D)` on their (overlapping) input sets, so the dispatch is answer-neutral.

### 5.4 Implementation blueprint for Task 1B (`sf/src/lexer.zig` `parseF64` replacement)

**Data structures** (all inside `lexer.zig`; no new modules, no language surface):

```zig
const Hpd = struct {
    num_digits: u32,
    decimal_point: i32,
    negative: bool,
    truncated: bool,
    digits: [800]u8,   // exact significant digits, 0..9
};
```

~816 B; plus an optional `[800]u8` scratch if left-shift new-digit count is computed by writing to scratch instead of the pow5-cutoff table (recommended for code size: scratch ≈ +800 B stack, saves ~130 constant table entries; worst-case stack 0.9–1.7 KB).

**Pipeline:**

1. **Scan** (keep existing `parseF64` shape): sign, integer digits, `.`, fraction digits, `e`/`E` exponent (skipping `_`). Accumulate `e10` into i32 with saturation at ±100000 (bounds later decide inf/0; avoids overflow UB).
2. **Build HPD:** drop leading zeros; count `decimal_point`; copy significant digits; trim trailing zeros; if `num_digits > 800`, keep 800 and set `truncated` if any dropped digit ≠ 0. All-zero → return signed `0.0`.
3. **Fast path:** if `!truncated` and digits fit `u64` `m < 2^53` and effective `e10 ∈ [−22, 22]` (optional disguised loop folding ×10 while `m` stays < 2^53): `f = u64→f64(m)` (exact), `f = e10 ≥ 0 ? f * pow10[e10] : f / pow10[−e10]` with `pow10[0..22] = 1e0..1e22` literals; apply sign; return.
4. **SDC core:**
   - Bounds (Zig's constants proven sufficient): zero early-out; `decimal_point > 310` → ±inf; `decimal_point < −324` and beyond `decimal_point_range = 2047` handling → ±0.0.
   - Right-shift loop (by ≤60-bit windows, u64 accumulator over digits — Zig `convertSlow` shape; or ×5-with-point−1 per bit) until `decimal_point ≤ 0`, tracking `exp2`.
   - Left-shift loop until value in `[½, 1)` (`decimal_point == 0` and `digits[0] ≥ 5`), tracking `exp2`; then `exp2 − 1` for `[1, 2)`.
   - Subnormal clamp: while `exp2 < emin + 1`, extra right-shifts; `bits = clamp(53 + exp2 − emin, 0, 53)`.
   - Left-shift by `bits + 1` (54-bit window); `round()` to 53 bits: integer `m54` from the leading window digits, round-up iff next digit > 5, or == 5 and (`truncated` or any further digit nonzero or `m54` odd); overflow of the increment → re-normalize and `exp2 += 1`.
   - Assemble `u64` bits: `sign | (exp2 + 1022 + overflow) << 52 | (m53 & 0x000fffffffffffff)`; `@ptrCast` to f64 (mirror of `sqrtD2B`); exp ≥ 0x7ff → ±inf; exp ≤ 0 path already produced subnormal/zero.
5. **Edge cases to pin:** `−0.0`; `1e309` → inf; `1e-400` → 0; `5e-324` (min subnormal) / `2.5e-324` (exact half of min subnormal, ties to 0.0); `9007199254740993.0` (2^53+1, ties down to `2^53`); a 900-digit exact-half string and the same string with a trailing `1` (sticky/tie split); `1.0e300` == `1e300` bit-identical; underscores `1_000.5`; all Task 1A table rows.

**Estimated size:** fast path 30–40 lines; HPD parse/trim 70; shifts 60–90 (1-bit ×2/×5 variant is the simplest to audit; ≤60-bit windows are a drop-in speed upgrade); scheduler + bounds + subnormals 60; round + assemble 70 → **~280–330 lines Z98 → ~450–550 lines C89, ~2.5–4 KB code, ≤1.7 KB stack.**

**Verification (feeds Task 1B steps 1–3):** fixture `lexer_float_rounding_xmod` pins Task 1A's 8 bit patterns; `lexer_float_exponent_xmod` stays green; compiler self-build green; corpus re-scan flips 240 → 0 mismatches (oracle: `gcc -m32 -std=c89` `strtod` / Python `float`); optional randomized cross-check of N ≥ 10⁴ strings including adversarial ties and 800-digit inputs.

### 5.5 Why no further rounding fixes will be needed

1. The output is **defined** as `RNE53(D)` — the same definition C `strtod`, Python `float()`, and gcc's C89 literal parser implement. The methodology contains no approximation steps that could be later "compensated": the fast path is a single IEEE operation on exact operands; SDC carries the exact decimal (sticky-preserving) and rounds once. There is no second rounding anywhere in the pipeline.
2. The only degree of freedom left is implementation bugs, which the 1B fixture + corpus + oracle diff will catch mechanically. Methodology-level "fixes" (adjacent-literal compensation like `sf/src/std_noise.zig:39-40`) become structurally unnecessary — that compensation is removed in Task 1D and can never be required again.
3. Downstream is also safe: the C emitter prints the f64 as 17 significant decimal digits, which is the proven round-trip width for f64, so `gcc` re-parsing the emitted literal reproduces the identical bits. Correct `parseF64` ⇒ end-to-end bitwise correctness with no emitter change.
4. Scope note: `sf/src/std_parse.zig:124-148` `parseFloat` (runtime std) has the same class of bug; it should later share this exact core. That is a follow-up task, not a rounding-methodology question — the decision above covers it unchanged.

---

## 6. Commit

Committed as `docs(sdd): M2 T1AEx methodology report` (report-only; no source/fixture/seed edits; `run.err` untouched).
