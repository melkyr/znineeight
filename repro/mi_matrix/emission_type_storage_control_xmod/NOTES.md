# emission_type_storage_control_xmod — GREEN control for the A/A₂ type-storage family

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **Status: GREEN control (NOT a RED fixture).** Expected-GREEN per A-ANALYZE §5.2 A/A₂ row.

## Purpose

Regression gate for the **A mangler-collision** and **A₂ type-storage extern** families (fixtures
`emission_mangler_collision_xmod`, `emission_type_storage_extern_xmod`,
`emission_type_storage_extern_struct_xmod`, `emission_type_storage_extern_threealias_xmod`): a
**union-type storage global** with an import-base / type-as-value alias in a **ref-only module**
(probe GREEN: `pt1`). Guards the shape that used to produce `'zG_<hash>_<Name>' undeclared …
did you mean …` (mangler re-mangle / missing extern in the header chain).

## Fixture (verbatim)

`mod_a.zig` (type owner):
```zig
pub const Value = union(enum) { i32: i32, f64: f64, none: void };
```

`mod_b.zig` (import-base alias + a switch over the union):
```zig
const mod_a = @import("mod_a.zig");

pub const Value = mod_a.Value;

pub fn typeOf(v: Value) i32 {
    return switch (v) { .i32 => |x| @intCast(i32, x), .f64 => |x| @intCast(i32, x), .none => 0 };
}
```

`mod_c.zig` (ref-only module — import-base alias with a type-as-value hop `const V = Value;`):
```zig
const Value = @import("mod_a.zig").Value;
const V = Value;

pub fn probe() i32 {
    var v: V = V{ .i32 = 3 };
    return v.i32;
}
```

`main.zig` (consumes both aliasing modules so the storage global is referenced from several places):
```zig
const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const Value = mod_b.Value;

pub fn main() void {
    std.io.printInt(mod_c.probe() + mod_b.typeOf(Value{ .none = {} }));
}
```

Import graph: `main → mod_b → mod_a`, `main → mod_c → mod_a`. 4 fixture modules + std.

## GREEN evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/diag_emission_type_storage_control_xmod \
    repro/mi_matrix/emission_type_storage_control_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd <out> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0
```

## Root-cause pin / family guarded

A (mangler collision) + A₂ (type-storage def/extern). The storage global `zG_<hash>_Value` is emitted
once with the correct extern propagation into the header chain (`nameManglerMangle` cache / extern
propagation fixes); the ref-only module's type-as-value alias resolves to the same storage global
without a suffix collision. **GREEN today because the fixes are shape-general** — they cover enum/struct/
union storage globals across any number of aliasing modules (single-file mode is GREEN by C89
tentative-def merge).

## Expected post-fix result

Stays GREEN; this control catches a regression in union-type storage global handling (mangler
collision or extern-chain drop).
