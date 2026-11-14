# emission_orelse_block_xmod — RED fixture for orelse + plain-block RHS with a terminator

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the **orelse + plain-block RHS containing
a terminator** emission gap (A-ANALYZE §5.1 shape C, ORELSE-family residual): `var x = maybe(seed) orelse { return null; };`.
The orelse else-branch emits `assign join_temp = null_val` **unconditionally** before checking
`block_terminated`, so the join assignment references a temp that was never declared →
`'zT_7' undeclared … did you mean 'zT_9'?`. Byte-identical class to probe `po4`.

## Fixture (verbatim)

`mod_a.zig` (the optional-returning callee — `maybe(seed)` yields null for `seed <= 0`):
```zig
pub fn maybe(seed: i32) ?i32 {
    if (seed > 0) return seed;
    return null;
}
```

`mod_b.zig` (THE emission site — a plain block `{ return null; }` as the orelse RHS):
```zig
const mod_a = @import("mod_a.zig");

pub fn useRet(prefix: []const u8, seed: i32) ?i32 {
    _ = prefix;
    var x = mod_a.maybe(seed) orelse { return null; };
    return x;
}
```

`main.zig` (graph filler — consumes `useRet` so it lowers):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var r = mod_b.useRet("pre", 0);
    var t = r orelse 0;
    std.io.printInt(t);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.
`zig1` accepts the program with **rc=0 and no diagnostics**.

## RED evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ rm -rf /tmp/aadd/emission_orelse_block_xmod && mkdir -p /tmp/aadd/emission_orelse_block_xmod
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/emission_orelse_block_xmod \
    repro/mi_matrix/emission_orelse_block_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/aadd/emission_orelse_block_xmod && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc error (single, clean — byte-identical class text to probe `po4`):
```
mod_b_CCD1F4C5.c: In function 'zF_BF163D33_useRet':
mod_b_CCD1F4C5.c:22:12: error: 'zT_7' undeclared (first use in this function); did you mean 'zT_9'?
   22 |     zT_6 = zT_7;
      |            ^~~~
      |            zT_9
mod_b_CCD1F4C5.c:22:12: note: each undeclared identifier is reported only once for each function it appears in
```

Emitted C (null path):
```
    int zT_6;
    int zT_9;                <- only zT_9 declared
    ...
    zT_6 = zT_7;             <- THE BUG: zT_7 never declared (block RHS yielded a void temp)
    ...
    zT_9 = zT_4.value;
    zT_6 = zT_9;
    x = zT_6;
```

## Root-cause pin

The orelse else-branch emits `assign join_temp = null_val` **unconditionally** (`lower.zig:3584`)
before checking `block_terminated` (`:3586`); a terminated plain-block RHS yields a void temp, so the
join assignment references an undeclared temp. (The catch arm does the opposite — it checks
`block_terminated` *before* the join assign at `:3536-3541` — which is why the `catch return null` /
`catch continue` probes `po2`/`po3` are GREEN; the orelse arm is the one missing the guard.)
(A-ANALYZE §5.1 shape C.)

## Expected post-fix result

After the shape-general F-ORELSE guard fix (emit the join assignment only when the block RHS is not
terminated), `zT_6 = zT_7;` disappears, no undeclared temp is referenced, and `gcc -c` rc=0. This
fixture flips to a GREEN control.
