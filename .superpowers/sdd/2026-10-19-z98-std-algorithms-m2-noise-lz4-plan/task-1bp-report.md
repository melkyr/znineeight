# Task 1Bp — pre-implementation edit plan for `parseF64` fix

Report-only. No source edits in this task. Target: `sf/src/lexer.zig` `parseF64` (lines 610-668).

---

## 1. Current code analysis

`parseF64(text: []const u8) f64` at `sf/src/lexer.zig:610-668`. Shape: sign scan (`-` then optional `+`), integer-digit loop, `.` fraction loop, `e`/`E` exponent, final negation. Three f64 accumulators, all wrong-class:

### 1.1 Exact defects

| # | Site | Defect | Class |
|---|------|--------|-------|
| D1 | int loop `result = result * 10.0 + @intToFloat(f64, dg)` | f64 accumulation; every step rounds once `result ≥ 2^53`. `9007199254740993.0` (2^53+1) silently becomes 2^53. | wrong value, not RNE53(D) |
| D2 | frac loop `result += @intToFloat(f64,dg2) * frac_mul; frac_mul *= 0.1` | `0.1` inexact in binary; `frac_mul` drifts after ~15-17 digits; each `+=` and each `*=` rounds. `0.1`→nearest f64 of 0.1 is OK by luck of one op, but `0.3`, `0.366025403784439`, long fractions accumulate error. | accumulated rounding error |
| D3 | exp loop `exp = exp * 10 + @intCast(i32, text[i]-'0')` | i32 overflow on literals like `1e9999999999` (10 digits) — `@intCast` panics in safe builds, wraps in release-fast → negative/huge exp. | crash / UB |
| D4 | `for (0..@intCast(usize, exp)) power *= 10.0` then `result *= power` / `result /= power` | (a) `power` built by `exp` f64 multiplications — each rounds, so `power` itself is not `10^exp` (e.g. `1e23` power is off-by-1-ulp from true 10^23); (b) final `*`/`/` is a second/third rounding of an already-rounded value; (c) huge `exp` (≥ ~1e6) makes a pathological loop; `exp` from D3 can be negative → `@intCast(usize, exp)` panic. | wrong value + crash |
| D5 | exponent loop `while (i < text.len and isDigit(text[i]))` | does not skip `_`, unlike int/frac loops. `1e1_0` parses exp=1, leaves `_0` unconsumed (scanner-dependent fallout). | inconsistency/bug |
| D6 | x87 path (PII/PIII C89 codegen) | every f64 op above rounds to 64-bit significand then the emitted double store rounds 64→53 — double rounding that can deviate from RNE53(D) near 53-bit ties. Even a "one f64 mul" fix would still double-round. | structural, platform-dependent |
| D7 | no special forms | no hex-float (likely out of scope — scan-only decimal), no inf/nan handling (check caller contract), no overflow→±inf / underflow→±0/subnormal bounds — `1e309` depends on whatever `*power` yields (inf by luck), `1e-400` depends on `/power` (0.0 by luck), `5e-324` / `2.5e-324` not reliably min-subnormal. | missing bounds |

### 1.2 What is already correct (keep)

- Sign handling: `-` first, then optional `+`; final `if (negative) result = -result` preserves `-0.0` only if `result` is `+0.0` at the end — actually `-0.0` works today for `-0` / `-0.0` (result 0.0 negated). Keep the sign-scan shape.
- Digit skipping of `_` in int and frac loops (D5 is the exponent-loop gap only).
- Break-on-`.`/`e`/`E` and push-back (`i -= 1`) handoff between phases.
- Two-arg builtin syntax (`@intCast(T, x)`, `@intToFloat(f64, x)`) — the tree is pre-0.11 Zig; all new code must match this style (see §3).

### 1.3 Caller/existing harness facts to preserve

- `parseF64` is a file-local `fn` in `lexer.zig` (not exported); tests assert through lexer-visible results (fixture `lexer_float_*`), so the signature `fn parseF64(text: []const u8) f64` stays identical.
- `isU64MaxLiteral` / `parseU64` neighbors unaffected.
- Bit-pattern assembly must use the `@ptrCast` u64↔f64 idiom already present at `sf/src/std_math.zig:78-80` (pattern from T1AEx §5.4) — NOT `@bitCast` (T1AEx Z98 constraint list).

### 1.4 Failure-mode corpus (why the fix is mandatory)

Task 1A's mandated rows that current code gets wrong or gets right by accident: `0.366025403784439` (D2 drift), `0.3` (may be right by single-op luck), `0.75`/`1.75` (exact, fine), `−0.16666666666666666` (D2), `1e300`/`1.0e300` (D4a `power` error + D4b), `1e-308` (D4b). Corpus re-scan baseline: 240 mismatches vs `gcc -m32 -std=c89` `strtod` / Python `float` oracle (T1AEx §5.4 verification). Target after fix: 0.

---

## 2. Algorithm specification (per T1AEx §5.1–§5.4)

One rounding, RNE, end to end. **No f64 arithmetic anywhere in the rounding path** — f64 exists only as the finished bit pattern via `@ptrCast` (PII/PIII x87 double-rounding structurally impossible). Two tiers, both compute `RNE53(D)`, dispatch answer-neutral.

### 2.1 Data structure (one struct, Z98-legal)

```zig
const Hpd = struct {
    num_digits: u32,        // significant digits held in digits[]
    decimal_point: i32,     // value = 0.digits[0..num_digits] * 10^decimal_point
    negative: bool,
    truncated: bool,        // true value > held value (dropped tail nonzero)
    digits: [800]u8,        // decimal digits 0..9, d[0] != 0 when num_digits > 0
};
```

~816 B + loop locals. Stack budget ≤ 1.7 KB (T1AEx §5.2). **Invariants** (must hold after every mutator): `num_digits == 0` or `digits[0] ∈ 1..9`; trailing zeros trimmed (`digits[num_digits-1] != 0`); `value = 0.digits × 10^decimal_point`. The trailing-zero invariant is load-bearing for the tie rule (§2.5).

### 2.2 Helpers (all file-local, replace nothing else in `lexer.zig`)

| fn | signature | role |
|----|-----------|------|
| `f64FromBits` | `fn f64FromBits(bits: u64) f64` | `@ptrCast(*f64, &bits); return p.*` — mirror `std_math.zig:78-80` |
| `pow5of` | `fn pow5of(k: u32) u64` | `5^k`, `k ≤ 22` (`5^22 = 2384185791015625 < 2^52`), iterative `r = r * 5` — no table |
| `bitlen128` | `fn bitlen128(hi: u64, lo: u64) u32` | MSB position + 1 of two-limb value |
| `shr128` | `fn shr128(hi: u64, lo: u64, shift: u32) u64` | low 64 of `(hi:lo) >> shift` |
| `bit128` | `fn bit128(hi: u64, lo: u64, i: u32) u64` | bit `i` of two-limb value |
| `lowNonZero128` | `fn lowNonZero128(hi: u64, lo: u64, cnt: u32) bool` | OR of bits `0..cnt-1` (sticky aggregation) |
| `mul128by64` | inlined in fast path | `m × 5^e → (hi,lo)` via 32-bit limbs (`m < 2^53`, `5^e < 2^52` ⇒ product `< 2^105`) |
| `fastRound` | `fn fastRound(qhi: u64, qlo: u64, sticky: bool, e_prime: i32, negative: bool) f64` | one integer RNE to 53 bits + pack |
| `hpdTrim` | `fn hpdTrim(h: *Hpd) void` | drop trailing zeros |
| `hpdMul2` | `fn hpdMul2(h: *Hpd) void` | `value × 2` exact (digit×2 + carry; carry-out ⇒ prepend `1`, `decimal_point += 1`; buffer full ⇒ drop LSB with `truncated` sticky) |
| `hpdDiv2` | `fn hpdDiv2(h: *Hpd) void` | `value / 2` exact (`×5` then `×10⁻¹`: carry `c ∈ 0..4`; `c > 0` ⇒ prepend `c`, `decimal_point` unchanged; `c == 0` ⇒ `decimal_point -= 1`) |
| `hpdRound` | `fn hpdRound(h: *Hpd) u64` | Zig `decimal.zig` `round()`: integer part = first `decimal_point` digits; round bit = `digits[dp] ≥ 5`; **exact-half tie** (`digits[dp]==5`, it is the last digit — guaranteed by trim invariant) ⇒ up iff `truncated` or kept LSB odd (ties-to-even) |

1-bit shift variant chosen deliberately (T1AEx: "simplest to audit"; ≤60-bit window table is a drop-in speed upgrade, not required for correctness).

### 2.3 Control flow of `parseF64`

1. **Scan** (keep existing shape): sign, int digits, `.`, frac digits, `e`/`E` exponent; `_` skipped in **all three** digit loops (fixes D5). Accumulate `e10` into i32, saturating at `±10⁶` (stop multiplying once `|e10| ≥ 100000`; no i32 overflow). Count `int_digits` (full int-part digit count, uncapped).
2. **Build HPD**: store first 800 digits; any dropped digit ≠ 0 ⇒ `truncated = true` (dropped zeros ⇒ exact). `decimal_point = int_digits + e10` (so `value = M × 10^(dp−n)` for the full digit string `M`, `n` digits). Strip trailing zeros (`n -= 1`, `dp` unchanged). Drop leading zeros (`n -= 1`, `dp -= 1` each). `num_digits == 0` ⇒ return signed `0.0` (covers `-0.0`).
3. **Bounds** (Zig constants proven sufficient): `dp < -324` ⇒ ±0.0; `dp ≥ 310` ⇒ ±inf. Saturated `e10` lands here, so `1e9999999999` is a clean inf — fixes D3/D4 crash class.
4. **Tier 1 fast path** (§2.4) if gate passes; else **Tier 2 SDC** (§2.5).

### 2.4 Tier 1 — exact-integer fast path (NOT f64 arithmetic)

Gate: `!truncated` and `n ≤ 16` and `m = M as u64 < 2^53` and `|e| ≤ 22` where `e = decimal_point − n` (so `D = m × 10^e`).

- `e ≥ 0`: `N = m × 5^e` in two u64 limbs (exact, `< 2^105`); `Q = N`, `sticky = false`, `E' = e`.
- `e < 0`: `k = −e`, `p5 = 5^k`; one u64 `divmod(m, p5)`: `q = m / p5`, `r = m % p5`. Generate binary digits of `r/p5` (long-division: `rr = rr*2; bit = (rr ≥ p5); rr −= bit·p5`; `rr < p5 < 2^52` ⇒ no overflow) into `Q = (q << t) | frac` (two limbs) **until `bitlen128(Q) ≥ 54` or `rr == 0`**; `sticky = (rr ≠ 0)`; `E' = −(t+k)`. Value `= (Q + θ)×2^E'`, `θ ∈ [0,1)`, `θ > 0` iff `sticky`.
  - Generation depth ≥ 54 whenever `sticky`: guarantees the round bit comes from generated bits, never from the unknown `θ` (this is why fixed-55-bit generation is insufficient when `q = 0`).
- **`fastRound`** — one rounding only: `L = bitlen128(Q)` (`≥ 1`), `E = E' + L − 1`, `prec = 53`, or `prec = E + 1075` when `E < −1022` (subnormal precision), or `prec ≤ 0` ⇒ `E < −1075` → signed `0.0`; `E == −1075` → min subnormal (`bits = 1`) unless exact tie `Q == 2^(L−1) && !sticky` (midpoint 2⁻¹⁰⁷⁵ ties-to-even → `0`). RNE: `shift = L − prec`; `shift ≤ 0` ⇒ exact pad `Q << (prec−L)` (invariant ⇒ `sticky` false here); else `keep = shr128(Q, shift)`, `round = bit128(Q, shift−1)`, `sticky2 = sticky || lowNonZero128(Q, shift−1)`, up iff `round && (sticky2 || keep&1)`. `prec == 53`: carry `keep == 2^53` ⇒ `keep = 2^52`, `E += 1`; `E > 1023` ⇒ ±inf; pack `sign | (E+1023)<<52 | (keep & 0x000fffffffffffff)`. `prec < 53`: `bits = keep` (subnormal grid `2^-1074`; `keep == 2^52` is exactly min-normal's bit pattern — carry case self-assembles).
- Coverage: Task 1A's 4 fast rows (`0.366025403784439`, `0.3`, `0.75`, `1.75`) + most short corpus literals. 4 fallback rows (`−0.16666666666666666`, `1e300`, `1.0e300`, `1e-308` — `m > 2^53` or `|e| > 22`) go SDC.

### 2.5 Tier 2 — SDC fallback (Zig `convert_slow` shape, 1-bit shifts)

After bounds: `exp2 = 0`.

1. **Right toward [½,1)**: `while (decimal_point > 0) { hpdDiv2(); exp2 += 1; }` (value halves each step ⇒ terminates).
2. **Left toward [½,1)**: `while (!(dp == 0 && digits[0] ≥ 5)) { hpdMul2(); exp2 -= 1; }` (value < 0.5 before each step ⇒ ×2 < 1, no overshoot; unique representation ⇒ terminates exactly at `[½,1)`).
3. `exp2 -= 1` — semantics switch: now `value = 1.f × 2^exp2`.
4. **Subnormal clamp**: `while (-1022 > exp2) { hpdDiv2(); exp2 += 1; }` (Zig `min_exponent = −1023` for f64, clamp to `min_exponent+1`). Underflow bounds: `dp < −324` already returned 0 before this.
5. **Overflow**: `exp2 + 1023 ≥ 2047` ⇒ ±inf (re-check after rounding carry too).
6. **Scale to hidden bit**: `53 × hpdMul2` (`value ∈ [2^52, 2^53)`), `mantissa = hpdRound()`; if `mantissa ≥ 2^53` (carry): `hpdDiv2(); exp2 += 1; mantissa = hpdRound();` re-check inf.
7. **Assemble** (Zig): `power2 = exp2 + 1023`; `if (mantissa < 2^52) power2 -= 1` (hidden clear ⇒ subnormal/zero); `mantissa &= 0x000fffffffffffff`; `bits = mantissa | (power2 << 52)`; sign bit; `f64FromBits`.

### 2.6 Rounding rule (single sentence)

Round **once**, to nearest, ties-to-even, on the exact decimal value `D`: round bit = the bit/digit at the 53-bit boundary (first fractional decimal digit ≥ 5 ⇔ ≥ ½ ulp), sticky = everything below it (including HPD `truncated`), exact half (digit 5, nothing further, `truncated` clear) rounds up iff the kept significand LSB is odd. Both tiers implement exactly this; no second rounding exists (§5.5 T1AEx).

### 2.7 Edge cases pinned

`−0.0` → `8000000000000000`; `1e309`/`1e9999999999` → ±inf; `1e-400` → ±0; `5e-324` → `0000000000000001`; `2.5e-324` → `0000000000000001` (above midpoint 2⁻¹⁰⁷⁵ ≈ 2.4703282292062327e-324); `2.47e-324` → `0000000000000000` (below); `2.48e-324` → `0000000000000001`; exact 2⁻¹⁰⁷⁵ (752-digit literal) → `0000000000000000` (tie-to-even) vs same string + trailing `1` → `0000000000000001` (sticky over tie); `9007199254740993.0` → `4340000000000000` (tie down to 2^53); `1.0e300` ≡ `1e300` bit-identical; `1_000.5`; all Task 1A §3 rows. Scanner-parity note: `lexerScanNumber` (lexer.zig:411) still stops the exponent at `_` — parser-side `_` skip is defense-in-depth (D5), scanner change is **out of scope** here.

---

## 3. Exact edit — `sf/src/lexer.zig`

**One hunk:** delete `fn parseF64` (lines 610-668) and insert the block below in its place (helpers immediately above `parseF64`, no other file touched). Dialect constraints verified against the tree: two-arg `@intCast(T, x)` / `@intToFloat` / `@ptrCast(*T, &x)` (`std_math.zig:78-85`), u64 `<<` `>>` (`std_math.zig:110-181`), u64 `/` `%` (`std_parse.zig:117-118`), `while (true)` (`std_stream.zig:197`), struct literals (`std_math.zig:154`), pointer-to-struct params (`*Lexer`). No negative literals / no unary minus on integers (dialect-safe form used throughout). Shift RHS cast to `u64` (pattern `std_math.zig:220`).

```zig
const Hpd = struct {
    num_digits: u32,
    decimal_point: i32,
    negative: bool,
    truncated: bool,
    digits: [800]u8,
};

fn f64FromBits(bits: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &bits);
    return p.*;
}

fn f64SignedZero(negative: bool) f64 {
    if (negative) return f64FromBits(0x8000000000000000);
    return f64FromBits(0);
}

fn f64SignedInf(negative: bool) f64 {
    if (negative) return f64FromBits(0xFFF0000000000000);
    return f64FromBits(0x7FF0000000000000);
}

fn pow5of(k: u32) u64 {
    var r: u64 = 1;
    var i: u32 = 0;
    while (i < k) {
        r = r * 5;
        i += 1;
    }
    return r;
}

fn bitlen128(hi: u64, lo: u64) u32 {
    var v: u64 = hi;
    var base: u32 = 0;
    if (v == 0) {
        v = lo;
    } else {
        base = 64;
    }
    if (v == 0) return 0;
    var n: u32 = base;
    while (v != 0) {
        v = v >> 1;
        n += 1;
    }
    return n;
}

fn shr128(hi: u64, lo: u64, shift: u32) u64 {
    if (shift == 0) return lo;
    if (shift >= 64) return hi >> @intCast(u64, shift - 64);
    return (lo >> @intCast(u64, shift)) | (hi << @intCast(u64, 64 - shift));
}

fn bit128(hi: u64, lo: u64, i: u32) u64 {
    if (i >= 64) return (hi >> @intCast(u64, i - 64)) & 1;
    return (lo >> @intCast(u64, i)) & 1;
}

fn lowNonZero128(hi: u64, lo: u64, cnt: u32) bool {
    if (cnt == 0) return false;
    if (cnt >= 64) {
        if (lo != 0) return true;
        if (cnt == 64) return false;
        var hm: u64 = (@intCast(u64, 1) << @intCast(u64, cnt - 64)) - 1;
        return (hi & hm) != 0;
    }
    var lm: u64 = (@intCast(u64, 1) << @intCast(u64, cnt)) - 1;
    return (lo & lm) != 0;
}

fn fastRound(qhi: u64, qlo: u64, sticky: bool, e_prime: i32, negative: bool) f64 {
    var l: i32 = @intCast(i32, bitlen128(qhi, qlo));
    if (l == 0) return f64SignedZero(negative);
    var e: i32 = e_prime + l - 1;
    if (e + 1075 < 0) return f64SignedZero(negative);
    if (e + 1075 == 0) {
        var is_pow2 = (qhi == 0) and ((qlo & (qlo - 1)) == 0);
        if (is_pow2 and !sticky) return f64SignedZero(negative);
        return f64FromBits(1);
    }
    var prec: i32 = 53;
    if (e + 1022 < 0) {
        prec = e + 1075;
    }
    var keep: u64 = 0;
    var shift: i32 = l - prec;
    if (shift <= 0) {
        keep = qlo << @intCast(u64, prec - l);
    } else {
        keep = shr128(qhi, qlo, @intCast(u32, shift));
        var round_bit = bit128(qhi, qlo, @intCast(u32, shift - 1));
        var sticky2 = sticky or lowNonZero128(qhi, qlo, @intCast(u32, shift - 1));
        if (round_bit != 0 and (sticky2 or (keep & 1) != 0)) {
            keep = keep + 1;
        }
    }
    if (prec == 53) {
        if (keep >= (@intCast(u64, 1) << 53)) {
            keep = @intCast(u64, 1) << 52;
            e = e + 1;
        }
        if (e > 1023) return f64SignedInf(negative);
        var biased: u64 = @intCast(u64, e + 1023);
        var frac: u64 = keep & 0x000fffffffffffff;
        var bits: u64 = (biased << 52) | frac;
        if (negative) bits = bits | 0x8000000000000000;
        return f64FromBits(bits);
    }
    if (negative) return f64FromBits(keep | 0x8000000000000000);
    return f64FromBits(keep);
}

fn hpdTrim(h: *Hpd) void {
    var n: usize = @intCast(usize, h.num_digits);
    while (n != 0 and h.digits[n - 1] == 0) {
        n -= 1;
    }
    h.num_digits = @intCast(u32, n);
}

fn hpdMul2(h: *Hpd) void {
    var n: usize = @intCast(usize, h.num_digits);
    if (n == 0) return;
    var carry: u32 = 0;
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        var t: u32 = @intCast(u32, h.digits[i]) * 2 + carry;
        h.digits[i] = @intCast(u8, t % 10);
        carry = t / 10;
    }
    if (carry != 0) {
        if (n == 800) {
            if (h.digits[799] != 0) {
                h.truncated = true;
            }
            var j: usize = 799;
            while (j > 0) {
                h.digits[j] = h.digits[j - 1];
                j -= 1;
            }
            h.digits[0] = @intCast(u8, carry);
        } else {
            var j: usize = n;
            while (j > 0) {
                h.digits[j] = h.digits[j - 1];
                j -= 1;
            }
            h.digits[0] = @intCast(u8, carry);
            n += 1;
            h.num_digits = @intCast(u32, n);
        }
        h.decimal_point += 1;
    }
    hpdTrim(h);
}

fn hpdDiv2(h: *Hpd) void {
    var n: usize = @intCast(usize, h.num_digits);
    if (n == 0) return;
    var carry: u32 = 0;
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        var t: u32 = @intCast(u32, h.digits[i]) * 5 + carry;
        h.digits[i] = @intCast(u8, t % 10);
        carry = t / 10;
    }
    if (carry != 0) {
        if (n == 800) {
            if (h.digits[799] != 0) {
                h.truncated = true;
            }
            var j: usize = 799;
            while (j > 0) {
                h.digits[j] = h.digits[j - 1];
                j -= 1;
            }
            h.digits[0] = @intCast(u8, carry);
        } else {
            var j: usize = n;
            while (j > 0) {
                h.digits[j] = h.digits[j - 1];
                j -= 1;
            }
            h.digits[0] = @intCast(u8, carry);
            n += 1;
            h.num_digits = @intCast(u32, n);
        }
    } else {
        h.decimal_point -= 1;
    }
    hpdTrim(h);
}

fn hpdRound(h: *Hpd) u64 {
    if (h.num_digits == 0 or h.decimal_point < 0) return 0;
    if (h.decimal_point > 18) return 0xFFFFFFFFFFFFFFFF;
    var dp: usize = @intCast(usize, h.decimal_point);
    var n: usize = @intCast(usize, h.num_digits);
    var acc: u64 = 0;
    var i: usize = 0;
    while (i < dp) {
        acc = acc * 10;
        if (i < n) {
            acc = acc + @intCast(u64, h.digits[i]);
        }
        i += 1;
    }
    var round_up = false;
    if (dp < n) {
        round_up = h.digits[dp] >= 5;
        if (h.digits[dp] == 5 and dp + 1 == n) {
            round_up = h.truncated or ((dp != 0) and ((1 & h.digits[dp - 1]) != 0));
        }
    }
    if (round_up) {
        acc = acc + 1;
    }
    return acc;
}

fn parseF64(text: []const u8) f64 {
    var h: Hpd = undefined;
    h.num_digits = 0;
    h.decimal_point = 0;
    h.negative = false;
    h.truncated = false;
    var i: usize = 0;
    var int_digits: i32 = 0;

    if (i < text.len and text[i] == '-') { h.negative = true; i += 1; }
    if (i < text.len and text[i] == '+') { i += 1; }

    while (i < text.len) {
        var c = text[i];
        i += 1;
        if (c == '_') continue;
        if (c == '.' or c == 'e' or c == 'E') { i -= 1; break; }
        if (!isDigit(c)) { i -= 1; break; }
        if (h.num_digits < 800) {
            h.digits[@intCast(usize, h.num_digits)] = c - @intCast(u8, '0');
        } else {
            if (c != '0') h.truncated = true;
        }
        h.num_digits += 1;
        int_digits += 1;
    }

    if (i < text.len and text[i] == '.') {
        i += 1;
        while (i < text.len) {
            var c = text[i];
            i += 1;
            if (c == '_') continue;
            if (c == 'e' or c == 'E') { i -= 1; break; }
            if (!isDigit(c)) break;
            if (h.num_digits < 800) {
                h.digits[@intCast(usize, h.num_digits)] = c - @intCast(u8, '0');
            } else {
                if (c != '0') h.truncated = true;
            }
            h.num_digits += 1;
        }
    }

    var e10: i32 = 0;
    var e10_neg = false;
    if (i < text.len and (text[i] == 'e' or text[i] == 'E')) {
        i += 1;
        if (i < text.len and text[i] == '-') { e10_neg = true; i += 1; }
        if (i < text.len and text[i] == '+') { i += 1; }
        while (i < text.len) {
            var c = text[i];
            if (c == '_') { i += 1; continue; }
            if (!isDigit(c)) break;
            i += 1;
            if (e10 < 100000) {
                e10 = e10 * 10 + @intCast(i32, c - @intCast(u8, '0'));
            }
        }
    }
    if (e10_neg) {
        h.decimal_point = int_digits - e10;
    } else {
        h.decimal_point = int_digits + e10;
    }

    while (h.num_digits != 0 and h.digits[@intCast(usize, h.num_digits - 1)] == 0) {
        h.num_digits -= 1;
    }
    var lz: usize = 0;
    var tot: usize = @intCast(usize, h.num_digits);
    while (lz < tot and h.digits[lz] == 0) {
        lz += 1;
    }
    if (lz > 0) {
        var j: usize = 0;
        while (lz + j < tot) {
            h.digits[j] = h.digits[lz + j];
            j += 1;
        }
        h.num_digits -= @intCast(u32, lz);
        h.decimal_point -= @intCast(i32, lz);
    }
    if (h.num_digits == 0) return f64SignedZero(h.negative);

    if (h.decimal_point + 324 < 0) return f64SignedZero(h.negative);
    if (h.decimal_point >= 310) return f64SignedInf(h.negative);

    var n: usize = @intCast(usize, h.num_digits);
    if (!h.truncated and n <= 16) {
        var m: u64 = 0;
        var j: usize = 0;
        while (j < n) {
            m = m * 10 + @intCast(u64, h.digits[j]);
            j += 1;
        }
        if (m < (@intCast(u64, 1) << 53)) {
            var e: i32 = h.decimal_point - @intCast(i32, n);
            if (e + 22 >= 0 and e <= 22) {
                if (e >= 0) {
                    var p5: u64 = pow5of(@intCast(u32, e));
                    var m_lo: u64 = m & 0xFFFFFFFF;
                    var m_hi: u64 = m >> 32;
                    var p_lo: u64 = p5 & 0xFFFFFFFF;
                    var p_hi: u64 = p5 >> 32;
                    var ll: u64 = m_lo * p_lo;
                    var lh: u64 = m_lo * p_hi;
                    var hl: u64 = m_hi * p_lo;
                    var hh: u64 = m_hi * p_hi;
                    var mid: u64 = (ll >> 32) + (lh & 0xFFFFFFFF) + (hl & 0xFFFFFFFF);
                    var lo: u64 = (mid << 32) | (ll & 0xFFFFFFFF);
                    var hi: u64 = hh + (lh >> 32) + (hl >> 32) + (mid >> 32);
                    return fastRound(hi, lo, false, e, h.negative);
                } else {
                    var k: i32 = 0 - e;
                    var p5b: u64 = pow5of(@intCast(u32, k));
                    var q: u64 = m / p5b;
                    var rr: u64 = m % p5b;
                    var qhi: u64 = 0;
                    var qlo: u64 = q;
                    var t: i32 = 0;
                    while (bitlen128(qhi, qlo) < 54 and rr != 0) {
                        rr = rr * 2;
                        var bit: u64 = 0;
                        if (rr >= p5b) {
                            rr = rr - p5b;
                            bit = 1;
                        }
                        var carry: u64 = qlo >> 63;
                        qlo = qlo * 2 + bit;
                        qhi = qhi * 2 + carry;
                        t += 1;
                    }
                    var e_prime: i32 = 0 - t - k;
                    return fastRound(qhi, qlo, rr != 0, e_prime, h.negative);
                }
            }
        }
    }

    var exp2: i32 = 0;
    while (h.decimal_point > 0) {
        hpdDiv2(&h);
        exp2 += 1;
    }
    while (true) {
        if (h.decimal_point == 0 and h.digits[0] >= 5) break;
        hpdMul2(&h);
        exp2 -= 1;
    }
    exp2 -= 1;
    while (exp2 + 1022 < 0) {
        hpdDiv2(&h);
        exp2 += 1;
    }
    if (exp2 + 1023 >= 2047) return f64SignedInf(h.negative);

    var s: u32 = 0;
    while (s < 53) {
        hpdMul2(&h);
        s += 1;
    }
    var mantissa: u64 = hpdRound(&h);
    if (mantissa >= (@intCast(u64, 1) << 53)) {
        hpdDiv2(&h);
        exp2 += 1;
        mantissa = hpdRound(&h);
        if (exp2 + 1023 >= 2047) return f64SignedInf(h.negative);
    }
    var power2: i32 = exp2 + 1023;
    if (mantissa < (@intCast(u64, 1) << 52)) {
        power2 -= 1;
    }
    mantissa = mantissa & 0x000fffffffffffff;
    var bits: u64 = (@intCast(u64, power2) << 52) | mantissa;
    if (h.negative) bits = bits | 0x8000000000000000;
    return f64FromBits(bits);
}
```

### 3.1 Code notes

1. `f64` never participates in rounding — only `f64FromBits` at the exits (x87 double-rounding impossible; T1AEx §5.3 step 1).
2. Scan/HPD build fixes D1-D5 in one pass; D3/D4 crash class dies at the `dp` bounds (saturated `e10`); D5 exponent `_` skip included.
3. `hpdRound` is Zig `decimal.zig` `round()` verbatim semantics: the `dp + 1 == n` exact-half arm is safe **only** because `hpdTrim` runs after every shift (invariant §2.1) — do not remove trims.
4. `fastRound` subnormal arm emits `keep` directly (`keep == 2^52` bit pattern == min normal, carry self-assembles); the `prec == 53` arm does the explicit carry (`keep >>= 1`-equivalent + `e += 1`) and inf re-check, mirroring `convert_slow.zig`'s `mantissa >= (1 << 53)` branch.
5. Integer tie in `fastRound` (`e + 1075 == 0`): exact midpoint 2⁻¹⁰⁷⁵ iff `Q` is a power of two and `!sticky` → ties-to-even → 0; anything else above the midpoint → min subnormal. `2.5e-324` (above midpoint) → `0000000000000001` ✓ (T1AEx fix-round-1 item 2).
6. Size: ~330 lines Z98 (est. 500-560 C89, ~3.5-4 KB i386); stack ≤ ~0.9 KB (`Hpd` 816 B + locals), no tables, no heap (T1AEx §5.2 budget).
7. Placement: helpers + `Hpd` sit between `isU64MaxLiteral`'s neighborhood and `parseF64`'s current slot; `lexer.zig:422` call site (`var value = parseF64(text);`) unchanged — signature identical.

---

## 4. Fixture specification — `repro/mi_matrix/lexer_float_rounding_xmod/`

Compiler-class fixture (no `stdlib_` prefix ⇒ not in `scripts/stdlib/expected_dirs.txt`, run explicitly — same class as `lexer_float_exponent_xmod`, see its header). Three files, goldens are the DESIRED GREEN behaviour from Task 1A §3 + T1AEx §5.4 edge list (all re-verified this session with Python `struct.pack('>d', float(s))`, which is correctly rounded).

### 4.1 `expected.txt` / `expected.rc`

```
expected.txt: lexer float round ok
expected.rc:  0
```

### 4.2 Long-literal generator (run at implementation time, paste output into `main.zig`)

```sh
python3 - <<'EOF'
D = str(5**1075)                       # exact 2^-1075 significand, 752 digits
print("var tie_lit: f64 = " + D + "e-1075;")            # exact midpoint 0|1
print("var tie_up_lit: f64 = " + D + "1e-1076;")         # midpoint + 1e-1076
print("var tie_trunc_lit: f64 = " + D + "0"*48 + "1e-1124;")  # 801 sig digits: kept prefix = exact tie, dropped tail "1"
print("var tie_tz_lit: f64 = " + D + "0"*128 + "e-1203;")     # 880 sig digits: dropped tail all zero
EOF
```

Verified goldens for these four: `tie_lit → 0000000000000000` (tie-to-even), `tie_up_lit → 0000000000000001`, `tie_trunc_lit → 0000000000000001` (truncation sticky over tie), `tie_tz_lit → 0000000000000000` (dropped zeros ⇒ not truncated ⇒ still an exact tie). Literal-text lengths 752/753/801/880 significant digits — all ≤ 800 except the two truncation rows (stored 800 + sticky), well inside the HPD cap.

### 4.3 `main.zig` (full shape)

```zig
// lexer_float_rounding_xmod — Task 1B permanent regression pin.
// Pins exact f64 bit patterns for decimal literals (Task 1A table +
// T1AEx edge list). Compiled by the compiler under test: its parseF64
// must produce these bits. Compiler-class fixture: run explicitly.
const std = @import("std");

var g_fail: u32 = 0;

fn f64ToBits(d: f64) u64 {
    var p: *u64 = @ptrCast(*u64, &d);
    return p.*;
}

fn ckBits(lit: f64, expected: u64, what: []const u8) void {
    if (f64ToBits(lit) != expected) {
        g_fail += 1;
        _ = what;
    }
}

pub fn main() void {
    // --- Task 1A mandated rows (correct bits, RNE) ---
    ckBits(0.366025403784439, 0x3fd76cf5d0b0995b, "0.366025403784439");
    ckBits(-0.16666666666666666, 0xbfc5555555555555, "-0.16666666666666666");
    ckBits(1e300, 0x7e37e43c8800759c, "1e300");
    ckBits(1.0e300, 0x7e37e43c8800759c, "1.0e300");
    ckBits(1e-308, 0x000730d67819e8d2, "1e-308");
    ckBits(0.3, 0x3fd3333333333333, "0.3");
    ckBits(0.75, 0x3fe8000000000000, "0.75");
    ckBits(1.75, 0x3ffc000000000000, "1.75");
    if (f64ToBits(1.0e300) == f64ToBits(1e300)) {} else { g_fail += 1; }

    // --- control rows (Task 1A additional) ---
    ckBits(1.5e-3, 0x3f589374bc6a7efa, "1.5e-3");
    ckBits(2.5e10, 0x42174876e8000000, "2.5e10");
    ckBits(12345678901234567.0, 0x4345ee2a2eb5a5c4, "12345678901234567.0");
    ckBits(0.211324865405187, 0x3fcb0cb174df99c3, "0.211324865405187");
    ckBits(1000.5, 0x408f440000000000, "1000.5");
    ckBits(1_000.5, 0x408f440000000000, "1_000.5");

    // --- sign / overflow / underflow bounds ---
    ckBits(-0.0, 0x8000000000000000, "-0.0");
    ckBits(1e309, 0x7ff0000000000000, "1e309");
    ckBits(-1e309, 0xfff0000000000000, "-1e309");
    ckBits(1e-400, 0x0000000000000000, "1e-400");
    ckBits(-1e-400, 0x8000000000000000, "-1e-400");

    // --- subnormal boundary family ---
    ckBits(5e-324, 0x0000000000000001, "5e-324");
    ckBits(2.5e-324, 0x0000000000000001, "2.5e-324");
    ckBits(2.47e-324, 0x0000000000000000, "2.47e-324");
    ckBits(2.48e-324, 0x0000000000000001, "2.48e-324");

    // --- integer tie / long-significand family ---
    ckBits(9007199254740993.0, 0x4340000000000000, "9007199254740993.0");

    // --- exact-half + sticky/tie/truncation rows (generated literals above) ---
    ckBits(tie_lit, 0x0000000000000000, "tie_lit");
    ckBits(tie_up_lit, 0x0000000000000001, "tie_up_lit");
    ckBits(tie_trunc_lit, 0x0000000000000001, "tie_trunc_lit");
    ckBits(tie_tz_lit, 0x0000000000000000, "tie_tz_lit");

    if (g_fail == 0) {
        std.io.write("lexer float round ok\n");
    } else {
        std.io.write("lexer float round FAIL\n");
    }
}
```

Notes:
1. `f64ToBits` is the `std_math.zig:82-85` `sqrtD2B` idiom — `@ptrCast` is legal in user fixtures (`xmod_amp_arena_union_store/main.zig`, `stdlib_map_determinism_xmod/main.zig` already use it).
2. Golden hex values re-verified this session: Python `struct.pack('>d', float(s))` on every decimal row; `tie_*` rows verified against `Decimal(2)**Decimal(-1075)` construction (§4.2).
3. `2.5e-324 → 0000000000000001` is **above** the 0|min-subnormal midpoint 2⁻¹⁰⁷⁵; `2.47e-324` is below it (T1AEx fix-round-1 item 2).
4. `1_000.5` pins underscore skipping in the mantissa; scanner accepts it in int/frac position.
5. Program exit: `g_fail == 0` path prints the ok line; exit code is 0 implicitly (mirror `lexer_float_exponent_xmod`). If the harness needs an explicit nonzero rc on failure, follow that fixture's exact failure convention (it `@panic`s per-row; panic ⇒ rc 133). Preferred here: keep printing FAIL and let the golden `expected.txt` mismatch fail the run (also covers rc 0-on-FAIL drift: compare stdout strictly).
6. RED today: `0.366025403784439` (+2 ULP), `−0.16666666666666666`, `0.3`, `0.75`, `1.75`, `1e300`, `1.0e300`, `1e-308` all mismatch current `parseF64` (Task 1A §3 "Z98 bits (bug)" column) ⇒ fixture prints FAIL before the fix.

---

## 5. Verification commands (Task 1B step 3 record)

All commands from repo root. Build recipe is the canonical seed bootstrap (`scripts/seed/build_from_seed.sh`): it dumps `sf/src/main.zig` with the seed compiler → gcc `-m32 -std=c89` → `zig1_5_clean` + sibling `lib/`, then verifies the two-hop fixed-point closure (md5 hop1 == md5 hop2) automatically. **The self-build is itself a parseF64 stress test** — it parses all 306 `sf/src` float literals through the new code.

### 5.1 RED — before the fix (record output verbatim)

```sh
scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t1b_pre
scripts/stdlib/run_fixtures.sh /tmp/t1b_pre/zig1_5_clean \
    repro/mi_matrix/lexer_float_rounding_xmod
```

Expected RED: fixture run FAILs — observed stdout `lexer float round FAIL` (rc 0) vs golden `lexer float round ok`; `run_fixtures.sh` prints `FAIL ... (stdout mismatch)`. Save the observed byte diff in the Task 1B report. (If `run_fixtures.sh` refuses non-stdlib dirs in future revisions, fall back to its 4 internal steps verbatim: `zig1 -ffast -o <tmp> <entry>` → `gcc -m32 -std=c89 ... -c` emitted `.c` → `sh <tmp>/build_target.sh linux <tmp>/prog` → run under `timeout 120`, diff stdout/`$?` to `expected.txt`/`expected.rc`.)

### 5.2 GREEN — after the fix

```sh
scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t1b_post
scripts/stdlib/run_fixtures.sh /tmp/t1b_post/zig1_5_clean \
    repro/mi_matrix/lexer_float_rounding_xmod \
    repro/mi_matrix/lexer_float_exponent_xmod
```

Expected: both `PASS`; stdout `lexer float round ok` / `lexer float exp ok`, rc 0 both; `build_from_seed.sh` prints `md5(hop1) == md5(hop2)` closure OK. Record both md5s and the fixture summaries.

### 5.3 Regression sweep (same `zig1_5_clean`, record-only classification)

```sh
scripts/stdlib/run_fixtures.sh /tmp/t1b_post/zig1_5_clean \
    repro/mi_matrix/stdlib_parse_parsefloat_xmod \
    repro/mi_matrix/stdlib_parse_ftoa_xmod \
    repro/mi_matrix/stdlib_comptime_float_compare_xmod \
    repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod \
    repro/mi_matrix/stdlib_rand_stat_xmod
```

These are Task 1A class E (tolerance/invariant pins, "rerun-only") — expect PASS or document any observed drift. **Known expected fallout (do NOT block 1B on it):** `stdlib_noise_basic_xmod` (class D-fixture-golden) will change — `sf/src/std_noise.zig:39-40` compensation literals are deliberately mismatched against correct rounding (Task 1A §3 workaround note), so the PGM hash moves when the parser becomes correct. Compensation removal + golden re-pin is Task 1D's scope; run this fixture, record the delta in the T1B report, leave it red-with-ticket.

### 5.4 Optional corpus re-scan (strongest evidence; T1AEx §5.4)

Re-run the Task 1A inventory (method fully described in `task-1a-report.md` §4: Python scanner replicating `lexerScanNumber` + `parseF64` over all `.zig` under `sf/src`, `examples/z98`, `repro/mi_matrix`, `stdlib_test`; oracle `gcc -m32 -std=c89` `strtod` + Python `float`): **240 mismatches → 0**. Equivalent end-to-end variant: `zig1_5_clean --dump-c89` spot files and re-parse the emitted 17-digit decimals with `strtod` — bits must equal the oracle bits of the source literals. Minimum bar if the scanner is not reconstructed: the §5.1–§5.3 rows above.

### 5.5 Pass criteria (Task 1B step 3 checklist)

- [ ] RED recorded for `lexer_float_rounding_xmod` before the fix
- [ ] `lexer_float_rounding_xmod` PASS after (all §4.3 bits match)
- [ ] `lexer_float_exponent_xmod` still PASS (exponent half of the I/F pair)
- [ ] compiler self-build succeeds with two-hop fixed-point closure
- [ ] in-file lexer tests (`lexerRunAllTests` via `test_runner.zig`) green
- [ ] class-D noise delta recorded, ticketed to Task 1D
- [ ] (optional) corpus 240 → 0

Commands for the in-file tests: run `test_runner.zig` the way CI does (see `sf/tests/`); it invokes `lexerRunAllTests()` which covers `lexerTestScanNumber` float-kind assertions.

---

## 6. Commit

Two commits in Task 1B (not this task): `fix(lexer): correctly round decimal f64 literals` (source + fixture) then `docs(sdd): M2 T1B report`. **This task (1Bp) is report-only** — committed as `docs(sdd): M2 T1Bp edit plan`.
