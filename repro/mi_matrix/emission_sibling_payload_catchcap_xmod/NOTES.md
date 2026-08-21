# emission_sibling_payload_catchcap_xmod — RED fixture for residual C₂ (catch-capture + same-named local)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Variation of the C₂ base fixture (`emission_sibling_payload_scale_xmod`) on the **catch-capture path**:
`maybe() catch |e| { var e: []const u8 = "err"; ... }`. The error capture `|e|` is registered as a
local (`addLocalDecl(..., TYPE_I32, ...)` at `lower.zig:3414`), and the same-named `var e` local in the
catch body collides on name at the same effective scope → the local is declared with the capture's
type (`int`, the error code) → the string-slice assignments and read-back are `incompatible types
when assigning` (int vs Slice).

## Fixture (verbatim)
`mod_a.zig`:
```zig
pub fn maybe() !u32 {
    return 7;
}
```
`mod_b.zig` (the catch site — the conflation point):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");

pub fn run() u32 {
    var r = mod_a.maybe() catch |e| {
        var e: []const u8 = "err";
        std.io.write(e);
        0;
    };
    return r;
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    std.io.printInt(@intCast(i32, mod_b.run()));
}
```
Import graph: `main → mod_b → mod_a`. 3 modules + std.

## RED baseline (measured 2026-08-21, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rC2 main.zig
rc=0
$ cd /tmp/rC2 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class C₂, `incompatible types when assigning`):
```
mod_b_7E9D4C5D.c:28:9: error: incompatible types when assigning to type 'int' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   28 |     e = zT_7;
mod_b_7E9D4C5D.c:29:9: error: incompatible types when assigning to type 'int' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   29 |     e = zT_7;
mod_b_7E9D4C5D.c:31:12: error: incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'int'
   31 |     zT_9 = e;
```
Emitting C — the local `e` is declared with the catch-capture's type (`int`, the error code):
```
int e;                            // local `e` declared with the CATCH CAPTURE's type (int)
z_bb_0:
e = zT_1.data.err;                // catch-capture assignment (int — correct for the capture)
zT_7 = "err"; ... slice build ...
e = zT_7;                         // ← local `e` (slice) assigned → int vs Slice → incompatible
...
zT_9 = e;                         // ← read back → Slice vs int → incompatible
```

## Root cause pinned
Same C₂ mechanism on the catch path: the error capture is a local decl (`lower.zig:3414`,
`TYPE_I32`), and the same-named `var e` local in the catch body shadows it at equal scope — the `<`
shadow check (`lower.zig:4876`) misses it, the name-keyed dedup keeps the capture's `int` entry, and
the slice local is emitted with type `int`. AMENDMENT 7 Ruling 2 fix (`<` → `<=`) applies.

## Expected post-fix result
After the C₂ fix, the equal-scope local `e` gets its own slice-typed declaration; the catch body's
`std.io.write(e)` emits correctly; `gcc -c` rc=0.
