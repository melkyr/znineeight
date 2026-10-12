# sat_signed_battery — GREEN: signed saturating emission battery (i8/i16/i32)

## What it tests
The signed saturating operators `+| -| *| <<|` on **signed** integer widths
i8/i16/i32 at min/max boundaries, exercising the SIGNED emission paths in
`c89_emit.zig` `emitSatBinary` (i8/i16/i32 signed clamp ternaries via
`signed`-typed temps). This complements the u8-only R1 fixture
(`parsergap_wrap_arith_xmod`) and the u8/u32 corpus gates, which give the
signed emission **zero committed regression coverage**. Fixture is
self-contained: bare `@import("std")` (canonical lib at
`/tmp/fx_subfolder/lib/`) + `std.io.printInt(x)` (canonical print,
`std_io.zig`) with `std.io.writeByte(@intCast(u8, ' '))` separators.

Added as part of the F1 fix wave for the self-compile-gaps plan final review
(operator ruling: signed wrap/sat emission needs committed regression coverage —
the signed paths had already produced one real bug, fixed in `10ba14e9`).

## Status: GREEN — all operators now parse and emit (RED baseline NO LONGER EXISTS)

The operator family parses GREEN since F1 (`9cb844b4` wrap, `541092b4` sat,
`10ba14e9` i64 sat-mul). There is NO RED baseline for this fixture; it is a
**regression-coverage** probe for the signed emission paths.

## Expected printed output (verified against Zig semantics: sat = clamp to signed min/max)

```
2147483647 -2147483648 -2147483648 2147483647 2147483647 -2147483648 2147483647 -2147483648 2147483647 1073741824 -2147483648 127 -128 127 127 32767 -32768 32767 32767
```

| # | Expression | i32/i8/i16 math | Expected | Zig semantics |
|---|-----------|-----------------|----------|---------------|
| 1 | `maxv +\| one` | 2147483647 + 1 | 2147483647 | clamp MAX |
| 2 | `minv +\| negone` | -2147483648 + -1 | -2147483648 | clamp MIN |
| 3 | `minv -\| one` | -2147483648 - 1 | -2147483648 | clamp MIN |
| 4 | `maxv -\| negone` | 2147483647 - -1 | 2147483647 | clamp MAX |
| 5 | `a *\| b` | 46341² = 2147488281 | 2147483647 | clamp MAX |
| 6 | `c *\| b` | -46341·46341 = -2147488281 | -2147483648 | clamp MIN |
| 7 | `maxv *\| one` | 2147483647 · 1 | 2147483647 | in range |
| 8 | `minv *\| one` | -2147483648 · 1 | -2147483648 | in range |
| 9 | `one <<\| sh` | 1 << 31 | 2147483647 | clamp MAX |
| 10 | `one <<\| sh30` | 1 << 30 = 1073741824 | 1073741824 | in range |
| 11 | `negone <<\| sh` | -1 << 31 = INT_MIN (fits) | -2147483648 | no clamp |
| 12 | `m8 +\| o8` | 127 + 1 | 127 | clamp MAX (i8) |
| 13 | `n8 -\| o8` | -128 - 1 | -128 | clamp MIN (i8) |
| 14 | `m8 *\| o8` | 127 · 1 | 127 | in range (i8) |
| 15 | `o8 <<\| 7` | 1 << 7 = 128 | 127 | clamp MAX (i8) |
| 16 | `m16 +\| o16` | 32767 + 1 | 32767 | clamp MAX (i16) |
| 17 | `n16 -\| o16` | -32768 - 1 | -32768 | clamp MIN (i16) |
| 18 | `m16 *\| o16` | 32767 · 1 | 32767 | in range (i16) |
| 19 | `o16 <<\| 15` | 1 << 15 = 32768 | 32767 | clamp MAX (i16) |

The i32 boundary values are held in i32-typed `var`s so the lowerer/emitter see
concrete signed temps (a bare literal like `40000 *| 40000` resolves the result
temp to the integer-literal type and takes the unsigned 32-bit clamp path — a
separate pre-existing literal-typing gap, NOT the path this battery guards).

## Gate recipe (per-module corpus convention)
```bash
mkdir -p /tmp/sat_signed_out
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/sat_signed_out main.zig   # dump rc=0
cd /tmp/sat_signed_out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c   # gcc rc=0
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/sat_signed_prog   # link rc=0
/tmp/sat_signed_prog   # run rc=0, prints the expected line above
```

## Guard summary
- dump rc=0, gcc rc=0, link rc=0, run rc=0, output == expected line above.
- Exercises the SIGNED i8/i16/i32 sat-clamp ternaries in `emitSatBinary`
  (`c89_emit.zig:3168-3535`), the `binary` wrap/sat dispatch
  (`c89_emit.zig:4833-4876`) and `getTempTypeInfo` operand-type resolution
  (`c89_emit.zig:3121`).
