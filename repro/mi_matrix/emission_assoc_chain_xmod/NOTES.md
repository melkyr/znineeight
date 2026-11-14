# emission_assoc_chain_xmod — left-associative chain misparse [R-1, 2026-08-26]

## Purpose
RED fixture for the R-1 self-emission fidelity gap: the self-compiled `zig1_5`
(compiled by zig1 compiling its own source) mis-parses same-precedence
left-associative operator chains (`a-b-c` → `a-(b-c)`), while the reference
compiler `/tmp/fx_subfolder/zig1` (built by zig0) parses them correctly.
In printInt's digit reversal this breaks `tmp[len - 1 - k]`, producing the
observed fib symptom `5\0` vs `55`. Part of the 2026-08-26 assoc-misparse plan
(docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md),
task R-ASSOC (fixture only — no root-cause trace, that is Task I-ASSOC).

## Fixture (verbatim)
```zig
const std = @import("std");

fn subChain(a: i32, b: i32, c: i32) i32 {
    return a - b - c;
}

fn divChain(a: i32, b: i32, c: i32) i32 {
    return a / b / c;
}

fn addSubChain(a: i32, b: i32, c: i32) i32 {
    return a + b - c;
}

fn addChain(a: i32, b: i32, c: i32) i32 {
    return a + b + c;
}

fn mulChain(a: i32, b: i32, c: i32) i32 {
    return a * b * c;
}

fn revDigits(n: i32) void {
    var tmp: [12]u8 = undefined;
    var len: usize = 0;
    var v: i32 = n;
    if (v == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        while (v > 0) {
            tmp[len] = '0' + @intCast(u8, v % 10);
            len += 1;
            v = v / 10;
        }
    }
    var k: usize = 0;
    while (k < len) : (k += 1) {
        std.io.writeByte(tmp[len - 1 - k]);
    }
    std.io.writeByte('\n');
}

pub fn main() void {
    std.io.printInt(subChain(10, 4, 3));
    std.io.writeByte('\n');
    std.io.printInt(divChain(100, 10, 2));
    std.io.writeByte('\n');
    std.io.printInt(addSubChain(1, 2, 3));
    std.io.writeByte('\n');
    std.io.printInt(addChain(1, 2, 3));
    std.io.writeByte('\n');
    std.io.printInt(mulChain(2, 3, 4));
    std.io.writeByte('\n');
    revDigits(55);
    revDigits(321);
}
```

Chains under test (values forced through function params so they evaluate at
runtime, not comptime-folded): `10 - 4 - 3` = 3 (left) vs 9 (right);
`100 / 10 / 2` = 5 vs 20; `1 + 2 - 3` = 0 (either way — mixed additive chain);
controls `1 + 2 + 3` = 6 and `2 * 3 * 4` = 24 (same either way).
`revDigits` mirrors `std_io.zig:printInt`'s `tmp[len - 1 - k]` reversal chain.

## RED evidence (2026-08-26, both rc=0)
Recipe (reference and self-compiled identical): `timeout 120 <compiler> --dump-c89
--output-dir <out> main.zig` (run FROM fixture dir) → `gcc -m32 -std=c89
-Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`
(in `<out>`) → link `<out>/*.c` + `sf/src/include/zig_runtime.c` +
`sf/src/include/zig_pal.c` → run.

| compiler | dump rc | gcc rc | link rc | run output (bytes) | run rc |
|----------|---------|--------|---------|--------------------|--------|
| reference `/tmp/fx_subfolder/zig1` (zig0-built) | 0 | 0 | 0 | `3\n5\n0\n6\n24\n55\n321\n` | 0 |
| self-compiled `/tmp/zig1_5/zig1_5_clean` | 0 | 0 | 0 | `9\n2\0\n0\n6\n2\0\n5\0\n3\0\0\n` | 0 |

Reference prints the LEFT-assoc values `3 5 0 6 24 55 321` (GREEN).
Self-compiled prints `9 2\0 0 6 2\0 5\0 3\0\0` (RED): `10-4-3` → 9 (right-nested),
and the self-emitted `printInt`/`revDigits` digit reversal is itself broken
(`tmp[len-1-k]` right-nested → stray `\0` bytes, the exact R-1 `5\0` vs `55`
symptom).

## Root-cause status
Self-emission fidelity gap (residual R-1), confirmed present in the pre-existing
self-compiled binary `/tmp/zig1_5/zig1_5_clean` (no rebuild performed). Root cause
NOT yet traced — Task I-ASSOC (diff self-emitted `gen/parser_*.c` vs reference
`/tmp/fx_subfolder/parser.c` / `/tmp/ref_zig1.c`).

## Expected post-fix
Self-compiled zig1_5 parses `10-4-3` = 3, `100/10/2` = 5, and the
printInt/revDigits digit reversal correct: output matches the reference
`3\n5\n0\n6\n24\n55\n321\n` byte-for-byte.
