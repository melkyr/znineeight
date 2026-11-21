# emission_global_alias_xmod — live load_global alias temps (W2-1)

## Purpose
Guard for the W2-1 dead-result-temp suppression (commit `c45f7333`,
`fix: emit (void) for discarded expression results`). W2-1 made `load_global`
result stores no longer be emitted: a load_global result temp is aliased
straight to the mangled global name via `temp_global_map`
(`sf/src/c89_emit.zig` `resolveTempName`), so neither a stack decl nor a dead
snapshot copy is emitted for it. The operator ruled to KEEP that live-alias
behavior (runtime proven identical across the corpus). This fixture exercises
the load_global -> live-temp -> use-after-call path so a regression that makes
a load_global temp see a post-write value (or drops a live temp entirely) shows
up as a wrong print.

The discriminating sequence: read the global `counter` into local `a`, call
`bump()` which WRITES `counter`, then print `a` (must be the ORIGINAL snapshot
value) and print `counter` (must be the NEW value). Under the current emission
`a = zG_9CACDE23_counter;` (snapshot copy into the named local, then
`zF_623C0FB5_bump();`) while `printInt(counter)` reads the global name live
(`zG_9CACDE23_counter`). A wrong live-alias (temp resolving to the global name
instead of the local) would print the post-write `6` for `a` and FAIL.
Also exercises: a `u32` global + a small global array (`grid`), global array
elements used as function arguments (`addPair(grid[0], grid[1])`,
`scale(grid[2])`), and pure-temp aliasing inside `bump`
(`zT_2 = zG_9CACDE23_counter + zT_1;` - the read temp resolves directly to the
global name, no intermediate copy). All printed values are single-digit so the
fixture stays byte-identical under the self-compiled zig1_5 (avoids the
documented R-1 printInt digit-reversal / chain-misparse gap,
see emission_assoc_chain_xmod).

## Fixture (verbatim)
```zig
const std = @import("std");

var counter: u32 = 5;
var grid: [4]u32 = [4]u32{ 1, 2, 3, 4 };

fn bump() void {
    counter = counter + 1;
}

fn addPair(x: u32, y: u32) u32 {
    return x + y;
}

fn scale(v: u32) u32 {
    return v * 2;
}

pub fn main() void {
    var a = counter;
    bump();
    std.io.printInt(@intCast(i32, a));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, counter));
    std.io.writeByte('\n');
    var t = a - 1;
    std.io.printInt(@intCast(i32, t));
    std.io.writeByte('\n');
    var u = addPair(grid[0], grid[1]);
    std.io.printInt(@intCast(i32, u));
    std.io.writeByte('\n');
    var v = scale(grid[2]);
    std.io.printInt(@intCast(i32, v));
    std.io.writeByte('\n');
    var w = t + u;
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte('\n');
    var x = counter - a;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
```

Values: `a`=5 (snapshot before bump), `counter`=6 (after bump), `t`=5-1=4,
`u`=1+2=3, `v`=3*2=6, `w`=4+3=7, `x`=6-5=1. `a` and `t` both survive the
interleaved calls (`bump()`, `addPair`, `scale`).

## Expected output
```
5
6
4
3
6
7
1
```
Line 1 `5` = ORIGINAL snapshot of `counter` (read into `a` BEFORE `bump()`);
line 2 `6` = NEW value (post-write). If the load_global alias were wrong, line 1
would print `6` (post-write value).

## Compile+run evidence (2026-08-27, both compilers)
Recipe (from fixture dir): `timeout 120 <compiler> --dump-c89 --output-dir OUT main.zig`
-> `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`
(in OUT) -> link with `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c` -> run.

| compiler | dump rc | gcc rc | link rc | run rc | output |
|----------|---------|--------|---------|--------|--------|
| reference `/tmp/fx_subfolder/zig1` (c45f7333) | 0 | 0 | 0 | 0 | `5\n6\n4\n3\n6\n7\n1\n` |
| self-compiled `/tmp/zig1_5/zig1_5_clean` | 0 | 0 | 0 | 0 | `5\n6\n4\n3\n6\n7\n1\n` |

Both compilers byte-identical (verified `cmp`). Reference emission spot-check:
`a = zG_9CACDE23_counter;` then `zF_623C0FB5_bump();`, then
`zT_8 = __bootstrap_i32_from_u32(zG_9CACDE23_counter);` (live global read) for
`printInt(counter)`; array base aliases the global name directly
(`zT_23 = zG_AF871A91_grid[zT_22];`); `bump` reads via the pure-temp alias
(`zT_2 = zG_9CACDE23_counter + zT_1;`) with no intermediate snapshot.
