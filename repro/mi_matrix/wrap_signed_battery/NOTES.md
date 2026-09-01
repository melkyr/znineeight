# wrap_signed_battery — GREEN: signed wrapping emission battery (i8/i16/i32)

## What it tests
The signed wrapping operators `+% -% *%` and prefix `-%` on **signed** integer
widths i8/i16/i32 at boundary values, exercising the SIGNED wrap emission in
`c89_emit.zig` (the `binary` wrap dispatch `:4843-4876` casts both operands
through the unsigned-width type then casts back to the signed result —
two's-complement wrapping — and the unary `-%` arm `:4927-4951` emits
`(signed)(0u - (unsigned)operand)`). The u8-only R1 fixture and the u8/u32
corpus gates give the signed wrap emission **zero committed regression
coverage**. Fixture is self-contained: bare `@import("std")` +
`std.io.printInt(x)` + `std.io.writeByte(@intCast(u8, ' '))` separators.

Added as part of the F1 fix wave for the self-compile-gaps plan final review
(operator ruling: signed wrap/sat emission needs committed regression coverage).

## Status: GREEN — RED baseline NO LONGER EXISTS

The operator family parses GREEN since F1 (`9cb844b4` wrap). There is NO RED
baseline for this fixture; it is a **regression-coverage** probe for the signed
wrap paths.

## Expected printed output (verified against Zig semantics: signed wrap = two's-complement; `-%a` of INT_MIN = INT_MIN)

```
-2147483648 -2147483648 2147483647 -2 -2147483648 2147483646 -128 -128 127 -32768 -32768 32767
```

| # | Expression | math (mod 2^width) | Expected | Zig semantics |
|---|-----------|--------------------|----------|---------------|
| 1 | `-%minv` (i32) | -(-2147483648) = 2^31 | -2147483648 | wraps to INT_MIN (langref `-%@as(i8,-128) == -128`) |
| 2 | `maxv +% one` (i32) | 2147483647 + 1 = 2^31 | -2147483648 | wrap overflow |
| 3 | `minv -% one` (i32) | -2147483648 - 1 = 2^31-1 | 2147483647 | wrap underflow |
| 4 | `maxv *% twov` (i32) | 2^31-1 · 2 = 2^32-2 | -2 | wrap product |
| 5 | `minv *% negone` (i32) | 2^31 · (2^32-1) mod 2^32 = 2^31 | -2147483648 | wraps to INT_MIN |
| 6 | `maxv +% negone` (i32) | 2147483647 - 1 | 2147483646 | in range |
| 7 | `-%n8` (i8) | -(-128) = 128 mod 256 | -128 | wraps to INT8_MIN |
| 8 | `m8 +% o8` (i8) | 127 + 1 = 128 mod 256 | -128 | wrap overflow (i8) |
| 9 | `m8 *% o8` (i8) | 127 · 1 | 127 | in range (i8) |
| 10 | `-%n16` (i16) | -(-32768) = 2^15 | -32768 | wraps to INT16_MIN |
| 11 | `m16 +% o16` (i16) | 32767 + 1 = 2^15 | -32768 | wrap overflow (i16) |
| 12 | `m16 *% o16` (i16) | 32767 · 1 | 32767 | in range (i16) |

The boundary values are held in typed `var`s so the lowerer/emitter see
concrete signed temps (bare big literals resolve to the integer-literal type —
a separate pre-existing literal-typing gap, NOT the path this battery guards).

## Gate recipe (per-module corpus convention)
```bash
mkdir -p /tmp/wrap_signed_out
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/wrap_signed_out main.zig   # dump rc=0
cd /tmp/wrap_signed_out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c   # gcc rc=0
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/wrap_signed_prog   # link rc=0
/tmp/wrap_signed_prog   # run rc=0, prints the expected line above
```

## Guard summary
- dump rc=0, gcc rc=0, link rc=0, run rc=0, output == expected line above.
- Exercises the SIGNED i8/i16/i32 wrap emission in the `binary` wrap dispatch
  (`c89_emit.zig:4833-4876`) and the unary `-%` arm (`c89_emit.zig:4927-4951`),
  plus `getTempTypeInfo` operand-type resolution (`c89_emit.zig:3121`).
