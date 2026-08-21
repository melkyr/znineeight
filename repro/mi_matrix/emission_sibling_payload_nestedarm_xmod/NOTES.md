# emission_sibling_payload_nestedarm_xmod — RED fixture for residual C₂ (nested arm, two-level equal-scope)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Variation of the C₂ base fixture (`emission_sibling_payload_scale_xmod`) at **two levels of nesting**:
an outer switch arm and an inner (nested) switch arm, both capturing `|s|`, with a same-named local
`var s: []const u8` in the inner arm body. The inner capture is disambiguated to `s_1` by
`maybeDisambiguateCapture` (`lower.zig:688`), but the inner body's `var s` still collides through the
name-keyed local-decl map: the `std.io.write(s)` reference resolves to the **inner capture** temp
(anon payload struct) instead of the slice local → `incompatible types when assigning`. Proves the
C₂ conflation persists at two nesting levels (equal-scope shadowing), not just one.

## Fixture (verbatim)
`mod_a.zig` (unions + factories):
```zig
pub const Inst = union(enum) {
    store: struct { ptr: u32, value: u32 },
    load: struct { ptr: u32, result: u32 },
};

pub const Inst2 = union(enum) {
    tag: struct { n: u32 },
    data: struct { n: u32 },
};

pub fn makeInst() Inst {
    return .{ .store = .{ .ptr = 0, .value = 0 } };
}

pub fn makeInst2() Inst2 {
    return .{ .tag = .{ .n = 1 } };
}
```
`mod_b.zig` (the nested-arm site):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;
const Inst2 = mod_a.Inst2;

pub fn emit(inst: Inst) void {
    switch (inst) {
        .store => |s| {
            switch (mod_a.makeInst2()) {
                .tag => |s| {
                    var s: []const u8 = " = *";
                    std.io.write(s);
                },
                .data => |d| {
                    std.io.printInt(@intCast(i32, d.n));
                },
            }
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

## RED baseline (measured 2026-08-21, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rC3 main.zig
rc=0
$ cd /tmp/rC3 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc error (class C₂, `incompatible types when assigning`):
```
mod_b_2CB81479.c:64:13: error: incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'zT_16903DDD_anon_94'
   64 |     zT_10 = s_1;
```
Emitting C — the slice read-back `std.io.write(s)` resolves to the **inner capture** `s_1`
(`zT_16903DDD_anon_94` = the `tag` payload) while the write temp is a slice; the real slice local
`s_2` is orphaned:
```
zT_0E8DF2AE_anon_82 s;       // outer capture (store payload)
zT_16903DDD_anon_94 s_1;     // inner capture (tag payload) — disambiguated from the outer name
zT_8F083A69_Slice_zT_0B42B2F8_u s_2;   // inner local `var s` — declared with its own slice type
...
s_1 = zT_3.payload.tag._0;   // inner capture assignment
zT_8.ptr = zT_7; ... slice build ...
s_2 = zT_8;                  // local initialized correctly
...
zT_10 = s_1;                 // ← write(s) reads the CAPTURE (anon_94), not the slice local s_2
zF_BE269F5C_write(zT_10);    // → incompatible assign (Slice = anon_94)
```
The write's name lookup hits the capture entry (`s_1`) rather than the same-named slice local — the
two-level equal-scope shadowing the base fixture does not cover.

## Root cause pinned
Same C₂ family at two nesting levels: name-keyed local handling (`addLocalDecl` +
`maybeDisambiguateCapture` + the var-decl shadow check `lower.zig:4876`). At depth 2 the outer
capture name collides with the inner capture (renamed to `s_1`), and the inner local `var s` is
then emitted as `s_2` but references through the capture's name; the `<=` fix (Ruling 2) renames the
shadowing local consistently so references resolve to the slice.

## Expected post-fix result
After the C₂ fix, the inner `var s` (and its references) are renamed to their own slice-typed
declaration; the inner `std.io.write(s)` emits `s_2`; `gcc -c` rc=0.

## Related observation — param named same as a local (attempted, GREEN)
The brief's "param named same as a local inside a fn" variation does NOT reproduce C₂. Params are
registered at fn scope (scope 0, `lower.zig:5621`); a body local is at scope ≥ 1, so the `<` shadow
check (`lower.zig:4876`) always renames the local (emitted as `s_1`) — params are strictly-outer and
never equal-scope with a body local. Tested: `emit(s: Inst) { var s: []const u8 = "x"; write(s); }`
→ GREEN with local mangled `s_1`; a switch-arm local colliding with a param name (`emit(s: Inst)`
+ `var s` inside an arm) → GREEN, same mangling. The `<=` fix does not affect params (param scope <
local scope is still true under `<=`). Documented as a control; no fixture created.
