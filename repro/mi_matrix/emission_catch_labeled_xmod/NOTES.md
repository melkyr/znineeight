# emission_catch_labeled_xmod — RED fixture for catch + labeled-statement RHS

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the **catch + labeled-statement RHS**
emission gap (A-ANALYZE §5.1 shape D, ORELSE-family residual): `var x = maybeErr() catch blk: { return null; };`
in a fn with a first param. The catch error path assigns the **first function parameter** into the
join temp (`zT_4 = prefix;`), producing the `incompatible types when assigning to type 'int' from type
'zT_…Slice…'` gcc class — the catch-path twin of shape B. Byte-identical class to probe `pco1`.

## Fixture (verbatim)

`mod_a.zig` (the error-union-returning callee):
```zig
pub fn maybeErr() !i32 {
    return 7;
}
```

`mod_b.zig` (THE emission site — a labeled-statement `blk: { return null; }` as the catch RHS;
`prefix: []const u8` first param whose C type (Slice) clashes with the catch payload `i32`):
```zig
const mod_a = @import("mod_a.zig");

pub fn useCatch(prefix: []const u8) ?i32 {
    _ = prefix;
    var x = mod_a.maybeErr() catch blk: { return null; };
    return x;
}
```

`main.zig` (graph filler — consumes `useCatch` so it lowers):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var r = mod_b.useCatch("pre");
    var t = r orelse 0;
    std.io.printInt(t);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.
`zig1` accepts the program with **rc=0 and no diagnostics**.

## RED evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ rm -rf /tmp/aadd/emission_catch_labeled_xmod && mkdir -p /tmp/aadd/emission_catch_labeled_xmod
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/emission_catch_labeled_xmod \
    repro/mi_matrix/emission_catch_labeled_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/aadd/emission_catch_labeled_xmod && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc error (single, clean — byte-identical class text to probe `pco1`):
```
mod_b_0ADC608E.c: In function 'zF_0637D08B_useCatch':
mod_b_0ADC608E.c:17:12: error: incompatible types when assigning to type 'int' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   17 |     zT_4 = prefix;
      |            ^~~~~~
```

Emitted C (error path):
```
    int zT_4;
    int zT_5;
    ...
    zT_4 = prefix;          <- THE BUG: catch labeled-RHS "return null" should jump away
    ...
    zT_5 = zT_2.data.payload;
    zT_4 = zT_5;
    x = zT_4;
```

## Root-cause pin

`catch_expr` (`lower.zig:3490`) calls `lowerExprOrBlock(child_1)`; a labeled-statement RHS is not
handled by it either, so the fallback yields **temp 0** (= the first function parameter) → temp 0 is
materialized and assigned to the join → `zT_4 = prefix;`. The catch arm's `block_terminated` guard
(`:3536-3541`) exists but temp 0 isn't flagged terminated, so the join assign still emits.
(A-ANALYZE §5.1 shape D.)

## Expected post-fix result

After the shape-general catch/orelse guard extension (treat labeled/block RHS containing a terminator
as terminated — no join assignment, control flow preserved), `zT_4 = prefix;` disappears and
`gcc -c` rc=0. This fixture flips to a GREEN control.
