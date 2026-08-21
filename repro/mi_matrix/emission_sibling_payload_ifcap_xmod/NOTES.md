# emission_sibling_payload_ifcap_xmod — RED fixture for residual C₂ (if-capture + same-named local)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Variation of the C₂ base fixture (`emission_sibling_payload_scale_xmod`), which only exercises a
**switch-arm** capture. This fixture proves the same C₂ sibling-payload conflation on the **if-capture
path (E1)**: `if (inst.store) |s| { var s: []const u8 = " = *"; ... }`. The capture `|s|` and the
same-named local `var s` are registered at the same effective scope depth (capture at
`scope_depth + 1`, `lower.zig:1345`; body lowered at `scope_depth + 1`), so the var-decl shadow check
(`<` at `lower.zig:4876`) does NOT rename the local → the local-decl dedup keeps the capture's entry →
the local is declared with the capture's anon payload struct type → gcc `incompatible types when
assigning`.

## Fixture (verbatim)
`mod_a.zig` (union + factory):
```zig
pub const Inst = union(enum) {
    store: struct { ptr: u32, value: u32 },
    load: struct { ptr: u32, result: u32 },
};

pub fn makeInst() Inst {
    return .{ .store = .{ .ptr = 0, .value = 0 } };
}
```
`mod_b.zig` (the if-capture site — the conflation point):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;

pub fn emit(inst: Inst) void {
    if (inst.store) |s| {
        var s: []const u8 = " = *";
        std.io.write(s);
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
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rC1 main.zig
rc=0
$ cd /tmp/rC1 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class C₂, `incompatible types when assigning`):
```
mod_b_F90356C7.c:26:9: error: incompatible types when assigning to type 'zT_8C842BAC_anon_48' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   26 |     s = zT_7;
mod_b_F90356C7.c:27:9: error: incompatible types when assigning to type 'zT_8C842BAC_anon_48' from type 'zT_8F083A69_Slice_zT_0B42B2F8_u'
   27 |     s = zT_7;
mod_b_F90356C7.c:29:12: error: incompatible types when assigning to type 'zT_8F083A69_Slice_zT_0B42B2F8_u' from type 'zT_8C842BAC_anon_48'
   29 |     zT_9 = s;
```
Emitting C — the local `s` is declared with the if-capture's payload struct type
(`zT_8C842BAC_anon_48` = the `store` payload), so the string-slice assignments and the read-back all
mismatch:
```
zT_8C842BAC_anon_48 s;            // local `s` declared with the CAPTURE's payload type
z_bb_0:
s = inst.payload.store._0;        // capture assignment (anon_48 = store payload — correct for capture)
zT_7 = " = *";  ... slice build ...
s = zT_7;                         // ← local `s` (slice) assigned → anon_48 vs Slice → incompatible
...
zT_9 = s;                         // ← read back → Slice vs anon_48 → incompatible
```

## Root cause pinned
Same C₂ as the base fixture: the equal-scope capture/local name collision. The if-capture is
registered via `addLocalDecl` at `scope_depth + 1` (`lower.zig:1345`), and the body's same-named
`var s` is declared at the same depth — the `<` shadow check (`lower.zig:4876`) misses equal-scope
shadowing, the name-keyed dedup keeps the capture's entry, and the slice local is emitted with the
capture's anon payload type. AMENDMENT 7 Ruling 2 confirms the fix: `<` → `<=`.

## Expected post-fix result
After the C₂ fix, the equal-scope local is renamed (its own declaration, slice type preserved); the
if-body `std.io.write(s)` emits correctly; `gcc -c` rc=0.
