# Task 1F report — formatF64 non-finite emission + precision digits

Status: IN PROGRESS (incremental writes per step)

Scope (plan §Task 1F): `sf/src/include/zig_compat.h` (Z98_INF/Z98_NEGINF/Z98_NAN union type-pun macros), `sf/src/util/format.zig` (`formatF64` non-finite guard), `repro/mi_matrix/lexer_float_rounding_xmod/` (restore inf rows), this report.

Compiler under test base: seed `/tmp/m7_t5_seed2/zig1_5_clean` (fixed point b299b4b435e624d0ddbd2edde681cbc3); source tree at Task 1B commit f967aeff (parseF64 correctly rounded).

## 1. Step 1 — C89 union macros in `zig_compat.h`

Added after the `Z98_U64_MAX` block (alongside `Z98_I64_C`/`Z98_U64_C` group), before the `!__cplusplus` scalar typedefs:

```c
/* IEEE-754 binary64 non-finite constants (C89 union type-pun; no C99
   compound literals, no GCC builtins, no math.h/libm). Little-endian
   layout: u[0] is the low word, u[1] the high word; unsigned long is
   32-bit on every supported toolchain. */
typedef union { unsigned long u[2]; double d; } z98_f64_bits;
static const z98_f64_bits z98_inf_bits  = {{ 0x00000000, 0x7FF00000 }};
static const z98_f64_bits z98_ninf_bits = {{ 0x00000000, 0xFFF00000 }};
static const z98_f64_bits z98_nan_bits  = {{ 0x00000000, 0x7FF80000 }};
#define Z98_INF    (z98_inf_bits.d)
#define Z98_NEGINF (z98_ninf_bits.d)
#define Z98_NAN    (z98_nan_bits.d)
```

Bit values (LE IEEE-754 binary64): `Z98_INF` = `0x7FF0000000000000`, `Z98_NEGINF` = `0xFFF0000000000000`, `Z98_NAN` = `0x7FF8000000000000` (quiet NaN). C89-verified: union static init with brace-enclosed first-member initializer, no C99 compound literal, no GCC builtin (`__builtin_inf`), no `math.h`/libm.

**Scope-extension finding (mandatory, gate-forced):** `zig_compat.h` has a byte-mirror in `sf/src/emit_support.zig` (`emitZigCompatHSupport` writes it into every dump dir; fixture gcc compiles with `-I .` on the dump dir, so the EMITTED copy is the live include). `scripts/check_emit_support.sh` asserts emitted == `sf/src/include/zig_compat.h` byte-for-byte. Both sides updated. Mirror verified by extracting the string-literal stream from `emitZigCompatHSupport` and diffing against the canonical file: `IDENTICAL` (2498 bytes both sides). Files touched by Step 1: `sf/src/include/zig_compat.h`, `sf/src/emit_support.zig` (plan file-list omitted the mirror; impossible to satisfy the byte-equality gate without it).

Precedent: the emitted C89 hex-float printer (`z98_printFloatHex32`, `sf/src/c89_emit.zig:5360`) already uses union type-pun in generated C — same idiom, no new pattern.

## 2. Step 2 — `formatF64` non-finite emission

`sf/src/util/format.zig:98-106` guard replaced (wrong comment "There is no valid C89 literal for inf/nan" removed):

```zig
    // Zero guard. Non-finite values emit the C89 union-type-pun macros from
    // zig_compat.h (Z98_INF / Z98_NEGINF / Z98_NAN) so the emitted C stays
    // C89-valid end to end.
    if (val == 0.0) { sb[0] = '0'; return fmtCopyOut(sb[0..1], buf, cap); }
    if (val != val) { return fmtCopyOut("Z98_NAN", buf, cap); }
    if (val * 2.0 == val) {
        if (val > 0.0) { return fmtCopyOut("Z98_INF", buf, cap); }
        return fmtCopyOut("Z98_NEGINF", buf, cap);
    }
```

Per plan: `+inf` (`val*2.0==val && val>0`) → `"Z98_INF"`; `-inf` (`val*2.0==val && val<0`) → `"Z98_NEGINF"`; NaN (`val!=val`) → `"Z98_NAN"`. Finite/zero path (zero guard + normalization + 17-digit collection) untouched.

Design notes:
- `val*2.0==val` (old code's inf idiom) retained for the inf branch — sign split by `val>0.0` (plan predicate); zero exits earlier so the branch only sees ±inf.
- Output text is a bare identifier token (`Z98_INF` etc.), not a numeric literal — emitted C sites are `temp = <text>;` / call-arg rvalue contexts (`c89_emit.zig:3621`, `c89_emit.zig:7065`), never C static initializers (global float inits with literal initializers go through `__module_init` runtime assignments — `sf/src/main.zig:972-1003` `has_runtime_init` path; non-literal inits likewise). `Z98_INF` expands to a non-constant expression (`z98_inf_bits.d`), which is legal in every call-site context found. Verified no `formatF64` output reaches file-scope initializers: all 6 call sites are `c89_emit` rvalue/stmt emission, `ast.zig:928` (marker), `dump_ast.zig:215`, `dump_tokens.zig:29`, `parser.zig:734` (all diagnostic).
- The macros live in `zig_compat.h`, which every emitted TU includes (`emitIncludes`, `c89_emit.zig:745`) — identifiers resolve wherever `formatF64` output lands.
- Idiom precedent inside the codebase: emitted C89 hex-float printers already use union type-pun (`z98_printFloatHex32` at `c89_emit.zig:5360`).

Risk check (no movers found): no test/golden/marker pins the old `'0'` mapping for non-finite. `dump_tokens`/`dump_ast`/`parser` debug output and the `AS:`/`D2:` marker stream now print `Z98_INF`/`Z98_NEGINF`/`Z98_NAN` for non-finite values instead of `0` — diagnostic-only streams, no committed golden consumes them (checked `repro/`, `tests/`, `scripts/`).

## 3. Step 3 — precision digits (17 sig digits confirmed)

No fix needed — `formatF64` already collects the top 17 digits plus an 18th for half-up rounding (`sf/src/util/format.zig:160-196`), and trims only trailing fractional zeros (`:207`); its own doc block (`:51-59`) documents the round-trip contract. Evidence below.

Probe (`/tmp/t1f_probe/main.zig`, 10 file-scope f64 globals) dumped with the pre-fix compiler (`/tmp/m7_t5_seed2/zig1_5_clean -ffast --dump-c89`). Emitted `__module_init` runtime assignments (also proves float globals are runtime-inited, so `Z98_INF`'s non-constant expression is legal at every emission site):

| lit | emitted text | sig digits | round-trip |
|---|---|---|---|
| 0.1 | `1.0000000000000001e-1` | 17 | OK (3fb999999999999a) |
| 1e300 | `1.0000000000000002e+300` | 17 | see note |
| 5e-324 | `0` | — | see note |
| 1.7976931348623157e308 | `1.7976931348623157e+308` | 17 | OK (7fefffffffffffff) |
| 0.3 | `3.0000000000000004e-1` | 17 | see note |
| 12345678901234567.0 | `1.2345678901234568e+16` | 17 | OK (4345ee2a2eb5a5c4) |
| 2.2250738585072014e-308 | `2.2250738585072024e-308` | 17 | see note |
| 1.0000000000000002 | `1.0000000000000002e+0` | 17 | OK (3ff0000000000001) |
| 3.141592653589793 | `3.1415926535897931e+0` | 17 | OK (400921fb54442d18) |
| 9007199254740993.0 | `9.007199254740992e+15` | 16 (17th digit trailing-zero trimmed) | OK (4340000000000000) |

Digit count: 17 significant digits on every row except the exact-power-of-two row where the 17th digit is `0` and gets trailing-trimmed (still round-trip exact).

**Note (attribution):** the 4 "mismatch" rows are the PRE-1B seed `parseF64` input-side ULP drift (the compiler under test is the unpatched `/tmp/m7_t5_seed2`), NOT `formatF64` output error — e.g. `0.3` reached `formatF64` as `3fd3333333333334` (seed parsed 1 ULP high) and the emitted text faithfully rounds THAT value; correct input `3fd3333333333333` has 17-digit form `2.9999999999999999e-1` (round-trips). `5e-324` → `0` is the seed parser's subnormal drop (Task 1A/1B fixed it). Final isolated formatF64 round-trip evidence is re-run against the self-built (1B+1F) compiler in §5 — same probe, all rows must be OK.

## 4. Step 4 — inf rows restored in `lexer_float_rounding_xmod`

`repro/mi_matrix/lexer_float_rounding_xmod/main.zig` sign/overflow block: the two T1B §4 max-finite workaround rows replaced by the original overflow rows, and the stale T1B ruling comment replaced:

```zig
    // --- sign / overflow / underflow bounds ---
    // Task 1F: formatF64 now emits C89 union-type-pun macros (Z98_INF /
    // Z98_NEGINF via zig_compat.h), so the overflow-to-inf rows are again
    // verifiable end to end (parseF64 overflow arm -> emitter -> runtime bits).
    ckBits(-0.0, 0x8000000000000000, "-0.0");
    ckBits(1e309, 0x7ff0000000000000, "1e309");
    ckBits(-1e309, 0xfff0000000000000, "-1e309");
    ckBits(1e-400, 0x0000000000000000, "1e-400");
    ckBits(-1e-400, 0x8000000000000000, "-1e-400");
```

Golden bits `7ff0000000000000` / `fff0000000000000` re-verified with Python `struct.pack('>d', float('1e309'))` = `0x7ff0000000000000`, `float('-1e309')` = `0xfff0000000000000`. All other rows (1A mandated, controls, subnormal family, tie family, -0.0, ±1e-400, 9007199254740993.0) untouched. Goldens `expected.txt` (`lexer float round ok`) / `expected.rc` (`0`) unchanged.

**Pre-build safety checks:**
- C89-acceptance of the new `zig_compat.h` block: `gcc -m32 -std=c89 -O0 -Wall` compiles the union/static-const macro set cleanly (only `-Wunused-const-variable` when unused — warning-level, no error).
- Closure risk audit for the self-build two-hop fixed point: if any `sf/src` float literal parsed to inf, seed-hop would emit `0` (old `formatF64`) where new-hop emits `Z98_INF` and hop1 != hop2. Swept `sf/src/**/*.zig` for over-range float literals — none (the `1.0e300` in `lower.zig:3607` comment is an f32-narrowing note, finite in f64). Closure unaffected by the macro addition (emitted dump C for in-graph literals is byte-identical).
- `zig_compat.h` header block is unused-const-warning noise in TUs that never emit a non-finite constant; `-Wall` (no `-Werror`) build scripts tolerate it.

Compile-check of the new sources with the pre-fix compiler (dialect acceptance, mirrors T1B §3):
```
/tmp/m7_t5_seed2/zig1_5_clean -ffast --dump-c89 --output-dir /tmp/t1f_compilecheck sf/src/main.zig
→ rc=0, 50 C files emitted (warnings only: null-ptr/MSVC-6 notes, pre-existing)
```

### 3.1 Final round-trip evidence (self-built 1B+1F compiler)

Same probe dumped with the self-built `/tmp/t1f_post/zig1_5_clean` (Task 1B parseF64 + Task 1F formatF64). Python `struct.pack('>d', float(text))` bit-compared against the correctly-rounded literal bits — **ROUND-TRIP ALL OK**:

| lit | emitted text | sig | bits |
|---|---|---|---|
| 0.1 | `1.0000000000000001e-1` | 17 | 3fb999999999999a OK |
| 1e300 | `1.0000000000000001e+300` | 17 | 7e37e43c8800759c OK |
| 5e-324 | `4.9406564584124654e-324` | 17 | 0000000000000001 OK |
| 1.7976931348623157e308 | `1.7976931348623157e+308` | 17 | 7fefffffffffffff OK |
| 0.3 | `2.9999999999999999e-1` | 17 | 3fd3333333333333 OK |
| 12345678901234567.0 | `1.2345678901234568e+16` | 17 | 4345ee2a2eb5a5c4 OK |
| 2.2250738585072014e-308 | `2.2250738585072014e-308` | 17 | 0010000000000000 OK |
| 1.0000000000000002 | `1.0000000000000002e+0` | 17 | 3ff0000000000001 OK |
| 3.141592653589793 | `3.1415926535897931e+0` | 17 | 400921fb54442d18 OK |
| 9007199254740993.0 | `9.007199254740992e+15` | 16 (17th trailing-zero trimmed) | 4340000000000000 OK |

This also closes the §3 attribution note: with correct input bits (1B), `formatF64`'s 17-digit text round-trips every probed class (subnormal, min-normal, mid, max-finite, integer-valued, power-of-two). **No fix required for Step 3.**

### 3.2 `formatF64` contract probe (direct)

`Z98_NEGINF`/`Z98_NAN` text is unreachable through the emitter alone (negation is a separate LIR negate node — `-(Z98_INF)` — and comptime const-folding of `1.0e309 * -1.0` / `0.0 / 0.0` does not fold to a non-finite `float_const` in this compiler). Contract verified with a direct driver calling `formatF64` (temp `repro/mi_matrix/t1f_fmtdrv_tmp/`, deleted after the run):

```
0.0 -> 0
+inf -> Z98_INF
-inf -> Z98_NEGINF
nan -> Z98_NAN
0.5 -> 5e-1
-0.5 -> -5e-1
```

All six arms correct: zero unchanged, the three non-finite arms return the macro identifiers, finite path (incl. negative via the `neg` sign path) unchanged.

## 5. Step 5 — verification (exact commands + outputs)

Compiler under test: self-built `/tmp/t1f_post/zig1_5_clean` (+ sibling `lib/`), produced by `scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t1f_post`.

### 5.1 Self-build (also the Step 5 self-build gate)

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t1f_post
→ [seed] hop1 binary md5: a53510875bc07065c6d5e2dc01136029
→ [seed] hop2 binary md5: 21c957730d268f1e7883176fa5413b65
→ [seed] hop3 binary md5: 21c957730d268f1e7883176fa5413b65
→ [seed] three-hop closure OK (moving point): hop2 == hop3 == 21c957730d268f1e7883176fa5413b65
```

Three-hop (moving point) rather than T1B's two-hop: expected and benign. The committed seed binary's embedded `emit_support` predates T1F, so its dump writes the OLD `zig_compat.h` (no union macros) into the hop1 gen dir while hop1's own dump (new `emit_support`) writes the new one — the unused-`static const` difference lands in every `-O0` object (empirically confirmed: gcc keeps unused file-scope `static const` in the object; `cmp` differs, text 124 vs 100 bytes for a 3-const probe). hop2 == hop3 is the convergence that matters (both compile against byte-identical new headers); the script's moving-point branch covers exactly this and requires hop2 == hop3. Behavior-level fixed point holds.

### 5.2 Fixture GREEN (inf rows included)

```
bash scripts/stdlib/run_fixtures.sh /tmp/t1f_post/zig1_5_clean \
    repro/mi_matrix/lexer_float_rounding_xmod \
    repro/mi_matrix/lexer_float_exponent_xmod
→ PASS repro/mi_matrix/lexer_float_rounding_xmod
→ PASS repro/mi_matrix/lexer_float_exponent_xmod
→ run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

- `lexer_float_rounding_xmod`: PASS — `lexer float round ok`, rc 0. All rows bit-exact end to end, including the restored `1e309` → `7ff0000000000000` and `-1e309` → `fff0000000000000` (28 rows: 1A mandated + controls + subnormal family + tie family + ±0 + ±1e-400 + 9007199254740993.0 + the two inf rows).
- `lexer_float_exponent_xmod` (regression): PASS unchanged.

Emission proof — the fixture dump (`/tmp/t1f_fixdump/main_*.c`) contains the new macros at the inf call sites:
```c
zF_..._ckBits((zT_..._f64)(Z98_INF), ...);                    /* 1e309  */
zF_..._ckBits((zT_..._f64)(-(zT_..._f64)(Z98_INF)), ...);     /* -1e309 */
```
(`-1e309` is a LIR negate over the `+inf` const — `-inf` reaches the runtime as `-(Z98_INF)` = `fff0000000000000`; the emitted `zig_compat.h` carries the `z98_f64_bits` union.) Golden bits re-verified in Python: `struct.pack('>d', float('1e309'))` = `7ff0000000000000`, `float('-1e309')` = `fff0000000000000`.

### 5.3 Support-file byte-equality gate (T1F touched the mirror)

```
bash scripts/check_emit_support.sh /tmp/t1f_post/zig1_5_clean
→ [check] OK: 8/8 support files byte-identical to canonical (6 core + 2 conditional preludes)
```
including `emitted zig_compat.h == sf/src/include/zig_compat.h`.

### 5.4 Float-adjacent fixture sweep

```
bash scripts/stdlib/run_fixtures.sh /tmp/t1f_post/zig1_5_clean \
    repro/mi_matrix/stdlib_parse_parsefloat_xmod \
    repro/mi_matrix/stdlib_print_ptr_hexfloat_xmod \
    repro/mi_matrix/stdlib_as_float_guard_xmod \
    repro/mi_matrix/stdlib_comptime_float_compare_xmod \
    repro/mi_matrix/stdlib_floatcast_xmod
→ 5 PASS / 0 FAIL
```

`repro/mi_matrix/comptime_float_compare_reject_xmod` was probed too: `run_fixtures` reports MISSING-GOLDEN because it is a compile-reject class fixture (`expected.rc` 2, no `expected.txt` — never a runtime stdout golden; the harness contract is runtime-only). Verified per its NOTES contract instead: rc 2, 3× `error[3059]`, 0 `.c` emitted, and stderr **byte-identical** between pre-fix `/tmp/m7_t5_seed2` and post-fix `/tmp/t1f_post` compilers (zero drift from T1F).

### 5.5 C89 macro runtime validation (standalone)

`gcc -m32 -std=c89 -O0 -Wall` on a probe including the new `zig_compat.h` block: `7ff0000000000000` / `fff0000000000000` / `7ff8000000000000` bit patterns read back exactly via `z98_*_bits.d`, and the three predicates (`Z98_INF*2==Z98_INF`, `Z98_NEGINF<0`, `Z98_NAN!=Z98_NAN`) all hold.

## 6. Files changed

1. `sf/src/include/zig_compat.h` — C89 union type-pun macros (Step 1).
2. `sf/src/emit_support.zig` — byte-mirror of the same block in `emitZigCompatHSupport` (gate-forced, §1).
3. `sf/src/util/format.zig` — `formatF64` non-finite guard (Step 2).
4. `repro/mi_matrix/lexer_float_rounding_xmod/main.zig` — inf rows restored (Step 4).
5. This report.

## 7. Concerns

1. **Unused-const warnings.** The three `static const` union objects produce `-Wunused-const-variable` in emitted TUs that never reference `Z98_INF`/`Z98_NEGINF`/`Z98_NAN` (warning-level; all build scripts use `-Wall` without `-Werror`). The plan mandates the static-const form; a `__attribute__((unused))` variant would be GCC-specific and violate the "true C89" constraint. Left as specified.
2. **Moving-point closure is now three-hop.** Any future T1F-style change to `emit_support.zig` bytes moves the point again (seed embeds old support). Convergence criterion remains hop2 == hop3. Not a defect; recorded so the next task does not misread hop1 != hop2 as a regression.
3. **`Z98_NAN` has no end-to-end runtime pin.** NaN cannot be built from a Z98 source literal and const-folding does not produce a non-finite `float_const` (probe §3.2), so the macro is only reachable via `formatF64` direct-call sites (AST markers, dumpers) and future comptime paths. Contract is unit-verified (§3.2); a permanent fixture pin would need a `@bitCast`-style NaN source (currently rejected by the language).
4. **Marker/dump streams changed textually.** `AS:`/`D2:` markers and `dump_tokens`/`dump_ast`/`parser` debug output now print `Z98_INF`/`Z98_NEGINF`/`Z98_NAN` instead of `0` for non-finite values. No committed golden consumes those streams (checked); if one is ever added it must expect the macro names.

## 8. Checklist

- [x] Step 1: C89 union macros in `zig_compat.h` + `emit_support.zig` mirror (byte-equal, gate green)
- [x] Step 2: `formatF64` emits `Z98_INF`/`Z98_NEGINF`/`Z98_NAN`; wrong comment removed; finite/zero unchanged
- [x] Step 3: 17 significant digits confirmed (code + two probes); no fix needed
- [x] Step 4: inf rows restored (`1e309` → `7ff0000000000000`, `-1e309` → `fff0000000000000`); fixture GREEN
- [x] Step 5: fixture + `lexer_float_exponent_xmod` + self-build (three-hop closure hop2==hop3==21c957730d268f1e7883176fa5413b65) + `check_emit_support` 8/8 + float sweep 5/5
- [x] Step 6: commits below

## 9. Commits

1. `fix(format): emit C89 union-type-pun inf/nan via zig_compat.h` — `sf/src/include/zig_compat.h`, `sf/src/emit_support.zig`, `sf/src/util/format.zig`, `repro/mi_matrix/lexer_float_rounding_xmod/main.zig`
2. `docs(sdd): M2 T1F report` — this file + progress ledger
