# emission_sibling_payload_scale_xmod — RED fixture for residual C₂ (sibling-variant payload conflation at scale)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Full-graph reproducer of **residual C₂** from the self-compile-residual-closeout
spec: sibling-variant payload conflation persists **at scale** in multi-variant
tagged unions. The prior fixture (`emission_sibling_payload_xmod`) triggered the
conflation through the 64-slot `addLocalDecl` cap; F-C (`3abb0b50`) grew the
arrays and added capture disambiguation, so that fixture is now GREEN. C₂ is the
remaining payload-*type* conflation: a switch-arm capture whose name collides
with a same-named local **declared inside the same arm** — the local-decl dedup
collides on the shared name, and the local (here a `[]const u8` slice) gets
declared with the **capture's** payload struct type → gcc
`incompatible types when assigning` (anon payload struct vs slice). This mirrors
the dominant self-compile C₂ error
`incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
from type 'zT_FDF20207_anon_39517'` (`c89_emit_7CEF756E.c` emitInst `.store`
arm, where `|s|` capture and `var s: []const u8 = " = *";` collide).

(48 assign + 9 no-member self-compile errors at HEAD `8d9af49d`.)

## Fixture (verbatim)
`mod_a.zig` (defines the union + a fn returning it):
```zig
pub const Inst = union(enum) {
    store: struct { ptr: u32, value: u32 },
    load: struct { ptr: u32, result: u32 },
};

pub fn makeInst() Inst {
    return .{ .store = .{ .ptr = 0, .value = 0 } };
}
```
`mod_b.zig` (the switch/field-access module — the conflation site):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;

pub fn emit(inst: Inst) void {
    switch (inst) {
        .store => |s| {
            var s: []const u8 = " = *";
            std.io.write(s);
        },
        .load => |l| {
            std.io.printInt(@intCast(i32, l.result));
        },
    }
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    mod_b.emit(mod_a.makeInst());
}
```
Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 modules + std.

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rC2 main.zig
rc=0
$ cd /tmp/rC2 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class C₂, `incompatible types when assigning`):
```
mod_b_1718E5AA.c:30:9: error: incompatible types when assigning to type 'zT_00895F76_anon_60' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   30 |     s = zT_5;
mod_b_1718E5AA.c:31:9: error: incompatible types when assigning to type 'zT_00895F76_anon_60' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   31 |     s = zT_5;
```
Emitting C (the conflation signature, mirroring the D-report's `zT_1096 = ic`):
```
zT_00895F76_anon_60 s;      // local `s` declared with the CAPTURE's payload type
z_bb_1:
s = inst.payload.store._0;  // capture assignment (anon_60 = store payload — correct for the capture)
zT_4 = " = *";
zT_6 = 4;
zT_5.ptr = zT_4;
zT_5.len = zT_6;
s = zT_5;                   // ← local `s` (Slice) assigned → anon_60 vs Slice → incompatible
```
The `var s: []const u8` local shares `name_id` with the `.store` capture `|s|`;
`addLocalDecl`'s name-keyed dedup keeps the capture's entry
(`zT_00895F76_anon_60`, the store payload struct), so the Slice local is never
declared with its own type — the string-literal slice `zT_5` is then assigned to
the capture-typed `s`.

## Root cause pinned
`sf/src/lower.zig` local-decl handling (`addLocalDecl` + name-keyed dedup /
`maybeDisambiguateCapture`): a same-named local inside a switch arm collides
with the arm's capture entry. C₂ of the spec.

## Expected post-fix result
After the C₂ fix (sibling-payload type conflation: the same-named local gets its
own declaration / the capture disambiguation is keyed to also cover shadowing
locals), `s` is declared `zT_8F083A69_Slice_zT_0B42B2F8_u`, the store-arm
`std.io.printStr(s)` emits correctly, and `gcc -c` rc=0.
