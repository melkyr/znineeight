# emission_orelse_control_xmod — GREEN control for the ORELSE terminator family

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **Status: GREEN control (NOT a RED fixture).** Expected-GREEN per A-ANALYZE §5.2 ORELSE row.

## Purpose

Regression gate for the **ORELSE terminator** family (fixture `emission_orelse_xmod`): an **orelse
`return null` inside a switch arm** (probe GREEN: `por1`). Guards the orelse-in-container shape that,
for a direct `return`/`continue` RHS, used to produce `incompatible types when assigning …`
(`zT_N = <first-param>;` on the orelse-null path) before the F-ORELSE guard.

## Fixture (verbatim)

`mod_a.zig` (the optional-returning callee + the switch tag type):
```zig
pub const K = enum(u8) { a, b };

pub fn maybe(seed: i32) ?i32 {
    if (seed > 0) return seed;
    return null;
}
```

`mod_b.zig` (THE guarded shape — `orelse return null` as the value of a switch arm):
```zig
const mod_a = @import("mod_a.zig");
const K = mod_a.K;

pub fn useSw(prefix: []const u8, seed: i32, k: K) ?i32 {
    _ = prefix;
    switch (k) {
        .a => return mod_a.maybe(seed) orelse return null,
        .b => return null,
    }
}
```

`main.zig` (graph filler — consumes `useSw` so it lowers):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var r = mod_b.useSw("pre", 0, .a);
    var t = r orelse 0;
    std.io.printInt(t);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.

## GREEN evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/diag_emission_orelse_control_xmod \
    repro/mi_matrix/emission_orelse_control_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd <out> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0
```

## Root-cause pin / family guarded

ORELSE terminator family. The F-ORELSE guard (`lower.zig:3575`) special-cases a **direct**
`return_stmt`/`break_stmt`/`continue_stmt` orelse RHS so no `zT_N = <first-param>` join assignment is
emitted — control flow jumps away instead. **GREEN today because the fix is shape-general** — the
guard is position-independent (works for orelse inside a switch arm or if-branch, not just at the top
of a fn body). A value-block RHS (`orelse { <value> }`) with a non-terminated block lowers through the
same value path and is GREEN by construction.

## Expected post-fix result

Stays GREEN; this control catches a regression in the orelse-terminator guard (direct `return` RHS
inside a container). The still-RED variants of this family (labeled-statement RHS, plain-block RHS with
a terminator) are the separate fixtures `emission_orelse_labeled_xmod` and
`emission_orelse_block_xmod`.
