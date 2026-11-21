# emission_void_call_control_xmod — GREEN control for the D void-fn-ptr-call family

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **Status: GREEN control (NOT a RED fixture).** Expected-GREEN per A-ANALYZE §5.2 D row.

## Purpose

Regression gate for the **D void-fn-ptr-call guard** family (fixture `emission_void_call_xmod`): a
**void fn-ptr called with args** (probe GREEN: `pvo2`). Guards the shape that used to produce
`void value not ignored as it ought to be` when the indirect `.call` arm emitted `f = f();` with no
void guard (vs the direct-call `call_direct` arm which has one).

## Fixture (verbatim)

`mod_a.zig` (the void callee, cross-module):
```zig
pub fn foo(x: i32) void {
    _ = x;
}
```

`mod_b.zig` (THE guarded shape — void fn-ptr assigned then called with an arg):
```zig
const mod_a = @import("mod_a.zig");

pub fn callVoid() void {
    var f: fn (i32) void = mod_a.foo;
    f(3);
}
```

`main.zig` (graph filler — consumes `callVoid` so it lowers):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    mod_b.callVoid();
    std.io.printInt(0);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.

## GREEN evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/diag_emission_void_call_control_xmod \
    repro/mi_matrix/emission_void_call_control_xmod/main.zig
zig_rc=0
$ cd <out> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0
```

Benign (documented, not a failure): the `var f: fn (i32) void = mod_a.foo;` fn-ptr init emits the same
`warning[3000]: type mismatch … source: function, target: pointer` that the existing
`emission_void_call_xmod` fixture documents — gcc rc=0 (GREEN), verdict unchanged.

## Root-cause pin / family guarded

D void-call family. The indirect `.call` arm's void guard (matching `call_direct`'s) suppresses the
bogus `f = f();` value-assignment on a void fn-ptr. **GREEN today because the fix is shape-general** —
the `.call` void guard is position-independent (works for call-as-statement and in any container,
single- or cross-module, with or without args).

## Expected post-fix result

Stays GREEN; this control catches a regression in the indirect void-call arm (call with args,
cross-module).
