# sat_i64_mul — GREEN: i64 signed saturating multiplication (`*|`) emission

## What it tests
The i64 signed saturating-multiplication emission path — the exact bug class
fixed in `10ba14e9` (`sf/src/c89_emit.zig` `emitSatBinary` op 21, 64-bit
branch: the signed i64 clamp expression with `9223372036854775807` /
`(-9223372036854775807 - 1)` / `(unsigned long long)` magnitude checks).
The u8-only R1 fixture and the u8/u32 corpus gates give this i64 signed path
**zero committed regression coverage**. Fixture is self-contained: bare
`@import("std")` + `std.io.printInt` + `std.io.writeByte(@intCast(u8, ' '))`
separators.

Added as part of the F1 fix wave for the self-compile-gaps plan final review
(operator ruling: signed wrap/sat emission needs committed regression coverage).

## Status: GREEN — RED baseline NO LONGER EXISTS

The i64 sat-mul emission was fixed in `10ba14e9` (pre-fix the i64 branch fell
into the ≤32-bit signed path and produced wrong results for i64 overflow
clamps). There is NO RED baseline for this fixture; it is a
**regression-coverage** probe for the i64 signed `*|` path.

## How results are verified
`std.io.printInt` is i32-only (`std_io.zig:19`), and the i64 `{}` interpolation
path is broken (prints garbage — a pre-existing print-lowering quirk, NOT this
fixture's target). Each sat-mul result is therefore verified **exactly** by
`if (x == expected_i64_var)` comparisons that print `1`/`0`. All boundary
values are built through `@intCast(i64, <literal>)` (or `@intCast(i64,
@intCast(u32, <literal>))` for values that need the 32-bit bit-pattern) because
a bare `var x: i64 = <big-literal>` init truncates the literal temp to 32-bit
`int` (a pre-existing literal-typing gap — NOT this fixture's target; see the
F7/`comptime_u64_fold_overflow` history).

## Expected printed output (all flags `1` = every sat-mul result matches its expected i64 value)

```
1 1 1 1 1 1
```

| # | Expression | i64 math | Expected | Zig semantics |
|---|-----------|----------|----------|---------------|
| 1 | `minv *\| negone` | INT64_MIN · -1 = 2^63 | `e1` = 9223372036854775807 | saturate to MAX (the `10ba14e9` special case) |
| 2 | `maxv *\| twov` | MAX · 2 overflows | `e1` = 9223372036854775807 | clamp MAX |
| 3 | `minv *\| twov` | MIN · 2 overflows | `e2` = -9223372036854775808 | clamp MIN |
| 4 | `big *\| big` | 3037000500² ≈ 9.22337e18 > MAX | `e1` = 9223372036854775807 | clamp MAX |
| 5 | `maxv *\| one` | MAX · 1 | `e1` = 9223372036854775807 | in range |
| 6 | `minv *\| one` | MIN · 1 | `e2` = -9223372036854775808 | in range |

All six cases MUST print `1`; any `0` means the i64 signed sat-mul emission
deviates from Zig semantics (signed clamp to 2^63-1 / -2^63).

## Gate recipe (per-module corpus convention)
```bash
mkdir -p /tmp/sat_i64_out
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/sat_i64_out main.zig   # dump rc=0
cd /tmp/sat_i64_out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c   # gcc rc=0
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/sat_i64_prog   # link rc=0
/tmp/sat_i64_prog   # run rc=0, prints `1 1 1 1 1 1`
```

## Guard summary
- dump rc=0, gcc rc=0, link rc=0, run rc=0, output `1 1 1 1 1 1`.
- Exercises the i64 signed sat-mul branch in `emitSatBinary`
  (`c89_emit.zig:3292-3356`) and the `binary` sat dispatch + `getTempTypeInfo`
  operand-type resolution (`c89_emit.zig:4833-4842`, `:3121`).
