# emission_capture_control_xmod — GREEN control for the C₂ capture family

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **Status: GREEN control (NOT a RED fixture).** Expected-GREEN per A-ANALYZE §5.2 C₂ row.

## Purpose

Regression gate for the **C₂ capture/local equal-scope conflation** family (fixtures
`emission_sibling_payload_scale_xmod`, `emission_sibling_payload_ifcap_xmod`,
`emission_sibling_payload_catchcap_xmod`, `emission_sibling_payload_nestedarm_xmod`,
`emission_sibling_payload_xmod`): a **for-capture** `|s|` plus a same-named local `var s` in the same
scope. Guards the for-slice capture shape (probe GREEN: `pb1`) that used to produce
`incompatible types when assigning … '<capture-payload>' … Slice`.

## Fixture (verbatim)

`mod_a.zig` (cross-module sink so the chain is 3+):
```zig
const std = @import("std");

pub fn writeStr(s: []const u8) void {
    std.io.write(s);
}
```

`mod_b.zig` (THE guarded shape — for-slice capture `|s|` + same-name local `var s`):
```zig
const mod_a = @import("mod_a.zig");

pub fn capture() void {
    var arr: [3]u32 = .{ 1, 2, 3 };
    for (arr) |s| {
        var s: []const u8 = "x";
        mod_a.writeStr(s);
    }
}
```

`main.zig` (graph filler — consumes `capture` so it lowers):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    mod_b.capture();
    std.io.printInt(0);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.

## GREEN evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/diag_emission_capture_control_xmod \
    repro/mi_matrix/emission_capture_control_xmod/main.zig
zig_rc=0
$ cd <out> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0
```

Benign (documented, not a failure): the `var arr: [3]u32 = .{ 1, 2, 3 };` init emits the known
`warning[3000]: type mismatch … source: tuple, target: array` (tuple-literal array init degrades; gcc
still rc=0).

## Root-cause pin / family guarded

C₂ sibling-payload family. The fix (`maybeDisambiguateCapture`/`IfTypeDiffers`, `lower.zig:743`, plus
the `<=` equal-scope shadow rename at `lower.zig:5012`) renames the same-scope capture `|s|` vs local
`var s` distinctly, so the capture's payload C type and the local's Slice C type no longer collide.
**GREEN today because the fix is shape-general** — capture disambiguation applies to for/if/switch/catch
captures across all containers.

## Expected post-fix result

Stays GREEN under the shape-general C₂ disambiguation; this control catches a regression in the
for-slice capture shape.
