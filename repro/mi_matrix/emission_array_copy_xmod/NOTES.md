# emission_array_copy_xmod — RED fixture for the array-copy direct-assign emission gap (R-ACOPY)

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **R-ACOPY VERIFY DIR:** the R-ACOPY task re-verifies THIS exact directory. It must remain RED on
> `error: assignment to expression with array type` at the `fb = src;` line. If it ever goes GREEN,
> the array-copy emission gap is fixed (reclassify as a control), not a fixture defect.

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the **array-copy direct-assign** emission
gap (A-ANALYZE §5.1 shape A, misc-family residual): any `var dst: [N]u8; … dst = src;` array copy in a
container makes the emitter emit BOTH the bogus C89-forbidden direct assignment `fb = src;` AND the
correct element-copy loop `fb[_i] = src[_i];`. gcc rejects the direct assignment deterministically.

## Fixture (verbatim)

`mod_a.zig` (graph filler — cross-module function so the chain is 3+):
```zig
pub fn addOne(x: u32) u32 {
    return x + 1;
}
```

`mod_b.zig` (THE emission site — the array copy inside an `if (true)` container, mirroring probe
`pm1`; A-ANALYZE §8 verified RED in if-stmt `pm1`, while `pm2`, switch-stmt `pm5`):
```zig
const mod_a = @import("mod_a.zig");

pub fn copyArr() u32 {
    var fb: [16]u8 = undefined;
    var src: [16]u8 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        src[i] = @intCast(u8, i);
    }
    if (true) {
        fb = src;
    }
    return mod_a.addOne(@intCast(u32, fb[0]));
}
```

`main.zig` (graph filler — consumes `copyArr` so it lowers):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var t = mod_b.copyArr();
    t = mod_a.addOne(t);
    std.io.printInt(@intCast(i32, t));
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.
`zig1` accepts the program with **rc=0 and no diagnostics**.

## RED evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ rm -rf /tmp/aadd/array_copy && mkdir -p /tmp/aadd/array_copy
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/array_copy \
    repro/mi_matrix/emission_array_copy_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/aadd/array_copy && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc error (single, clean — the target class, byte-identical to probes pm1/pm2/pm5):
```
mod_b_C4786312.c: In function 'zF_359DD73F_copyArr':
mod_b_C4786312.c:78:8: error: assignment to expression with array type
   78 |     fb = src;
      |        ^
```

Emitted C (the bug, both forms present):
```
z_bb_5:
    fb = src;                <- THE BUG: C89 array assignment (6.3.16.1), unconditional
    {
    unsigned int _i = 0;
    while (_i < 16) {
        fb[_i] = src[_i];    <- the CORRECT element-copy loop (redundant, but valid)
        _i++;
    }
}
```

## Root-cause pin

The array-copy `.assign`/`.store_local` path (`c89_emit.zig` array-copy handler) emits BOTH the bogus
`dst = src;` direct-assign line AND the correct `dst[_i] = src[_i];` loop. The direct-assign line is
C89-invalid (an array is not an assignable expression, C89 6.3.16.1); the loop alone is valid, so the
bogus line is provably the defect. This is a *separate* emission gap from the (fixed) name-keyed
conflation of `emission_misc_xmod` — it fires even with a single, non-conflated `fb`/`src` pair (probe
`pm1`/`pm2`/`pm5` were single-module and clean). (A-ANALYZE §5.1 shape A.)

## Expected post-fix result

After R-ACOPY/F-ACOPY, the array-copy `.assign` path emits only the element-copy loop (or a
`memcpy`/loop equivalent), never the direct `fb = src;` line. `gcc -c` rc=0. This fixture flips to a
GREEN control.
