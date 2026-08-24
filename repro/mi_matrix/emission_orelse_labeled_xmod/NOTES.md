# emission_orelse_labeled_xmod — RED fixture for orelse + labeled-statement RHS (R-ORELSE residual)

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the **orelse + labeled-statement RHS**
emission gap (A-ANALYZE §5.1 shape B, ORELSE-family residual): `var x = maybe(seed) orelse blk: { return null; };`
in a fn whose first param is `prefix: []const u8`. The orelse-null path assigns the **first function
parameter** into the join temp (`zT_6 = prefix;`), producing the `incompatible types when assigning to
type 'int' from type 'zT_…Slice…'` gcc class — byte-identical to the solved `emission_orelse_xmod`
fixture's class.

## Fixture (verbatim)

`mod_a.zig` (the optional-returning callee — `maybe(seed)` yields null for `seed <= 0`):
```zig
pub fn maybe(seed: i32) ?i32 {
    if (seed > 0) return seed;
    return null;
}
```

`mod_b.zig` (THE emission site — a labeled-statement `blk: { return null; }` as the orelse RHS;
`prefix: []const u8` first param whose C type (Slice) clashes with the optional payload `i32`):
```zig
const mod_a = @import("mod_a.zig");

pub fn useRet(prefix: []const u8, seed: i32) ?i32 {
    _ = prefix;
    var x = mod_a.maybe(seed) orelse blk: { return null; };
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
$ rm -rf /tmp/aadd/emission_orelse_labeled_xmod && mkdir -p /tmp/aadd/emission_orelse_labeled_xmod
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/emission_orelse_labeled_xmod \
    repro/mi_matrix/emission_orelse_labeled_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/aadd/emission_orelse_labeled_xmod && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc error (single, clean — byte-identical class text to probe `po1` and the solved
`emission_orelse_xmod` fixture's `useReturn` error):
```
mod_b_5B4EEA2F.c: In function 'zF_BF163D33_useRet':
mod_b_5B4EEA2F.c:19:12: error: incompatible types when assigning to type 'int' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   19 |     zT_6 = prefix;
      |            ^~~~~~
```

Emitted C (null path):
```
    int zT_6;
    int zT_7;
    ...
    zT_6 = prefix;          <- THE BUG: orelse labeled-RHS "return null" should jump away
    ...
    zT_7 = zT_4.value;
    zT_6 = zT_7;
    x = zT_6;
```

## Root-cause pin

The F-ORELSE guard (`lower.zig:3575`) only special-cases a **direct** `return_stmt`/`break_stmt`/
`continue_stmt` RHS. A **labeled-statement** RHS (`blk: { return null; }`) is none of those, so
`lowerExpr(child_1)` falls through to its tail `else` (`lower.zig:4296-4297`) and returns **temp 0**
(= the first function parameter — `lowerFn` allocates param temps first and resets the counter after),
which is then materialized and assigned to the join (`:3583-3584`) → `zT_6 = prefix;`. (A-ANALYZE
§5.1 shape B.)

## Expected post-fix result

After the shape-general F-ORELSE guard extension (treat labeled/block RHS containing a terminator as
terminated — no join assignment, control flow preserved), `zT_6 = prefix;` disappears and `gcc -c`
rc=0. This fixture flips to a GREEN control.
