# voiddecl_struct_xmod_r1 — sanity baseline: cross-module struct return at 2 modules  [R1, 2026-08-18]

## Purpose
First rung of the self-compile silent-drop plan (docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md).
Establishes the GREEN sanity floor at small scale: a 2-module cross-module
struct-return program that compiles cleanly. Small scale does NOT trip the
"modules 1-4 silently dropped" bug (213x error[3000] during self-compile) —
this rung confirms the fixture machinery (bare `@import("std")`,
`std.io.printInt`, struct return across modules) works end-to-end on the
existing `/tmp/fx_subfolder/zig1` before the VOID-decl ladder scales up.

## Fixture sources (verbatim from brief)

main.zig:
```zig
const std = @import("std");
const mod = @import("mod.zig");
pub fn main() void {
    var x = mod.make();
    std.io.printInt(x.v);
}
```

mod.zig:
```zig
pub const Foo = struct {
    v: u32,
};

pub fn make() Foo {
    var f = Foo{ .v = 42 };
    return f;
}
```

## Measured result (2026-08-18, /tmp/fx_subfolder/zig1, run FROM fixture dir)
- dump: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` → **rc=0**, emits `/tmp/r1.c`.
- gcc: `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include /tmp/r1.c /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/r1` → **rc=0**.
- run: `timeout 30 /tmp/r1` → prints **`42`**, **rc=0**.
- (sf include paths used absolute — repo-root-relative `sf/src/include` does not
  resolve from the fixture dir; matches corpus convention in `extern_runtime_symbol_xmod/NOTES.md`.)

## Baseline claim
**GREEN**: cross-module struct return works at 2 modules on the current zig1.
This is the sanity floor for the VOID-decl silent-drop ladder; the small-scale
fixture does not trip the silent-drop bug under investigation.
