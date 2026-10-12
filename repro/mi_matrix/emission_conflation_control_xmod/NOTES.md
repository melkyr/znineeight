# emission_conflation_control_xmod — GREEN control for the CONFLATION family (F-B disambiguation)

Task A-ADD (2026-08-24), R2/R1 self-compile closeout plan (AMENDMENT 1). Compiler under test:
`/tmp/fx_subfolder/zig1` (current; no rebuild since HEAD `5267f5e6`). Build recipe identical to the
other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **Status: GREEN control (NOT a RED fixture).** Expected-GREEN per A-ANALYZE §5.2 CONFLATION row.

## Purpose

Regression gate for the **CONFLATION** family (fixtures `emission_assign_xmod`,
`emission_no_member_xmod`, `emission_request_member_xmod`, `emission_zT_undeclared_xmod`):
same-named locals/captures of different types are now scope- and type-aware renamed in
`lower.zig:5012/5017`. Guards the **if-EXPR / switch-EXPR** container shapes (probe GREEN:
`pa1c`/`pa2c`), the same-name diff-type locals pattern that used to produce
`incompatible types when assigning to type '<first-seen>' from type '<second>'` /
`request for member … in something not a structure or union` / `'<T>' has no member named '<f>'`.

## Fixture (verbatim)

`mod_a.zig` (types + constructors, cross-module):
```zig
pub const Kind = enum(u8) { a, b };
pub const Type = struct { id: u32, kind: u32 };
pub const CoercionKind = enum(u8) { none, int_widen };

pub fn makeType() Type {
    return .{ .id = 0, .kind = 0 };
}

pub fn makeCoercion() CoercionKind {
    return .int_widen;
}
```

`mod_b.zig` (THE guarded shapes — same-name diff-type locals `ck` in if-EXPR and switch-EXPR plain
block arms):
```zig
const mod_a = @import("mod_a.zig");
const Kind = mod_a.Kind;
const Type = mod_a.Type;
const CoercionKind = mod_a.CoercionKind;

pub fn ifExpr() i32 {
    return if (true)
        { var ck: Type = mod_a.makeType(); @intCast(i32, ck.id); }
    else
        { var ck: CoercionKind = mod_a.makeCoercion(); @intCast(i32, @enumToInt(ck)); };
}

pub fn switchExpr(k: Kind) i32 {
    return switch (k) {
        .a => { var ck: Type = mod_a.makeType(); @intCast(i32, ck.id); },
        .b => { var ck: CoercionKind = mod_a.makeCoercion(); @intCast(i32, @enumToInt(ck)); },
        else => 0,
    };
}
```

`main.zig` (graph filler — consumes both fns so they lower):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var k: mod_a.Kind = .a;
    var r = mod_b.ifExpr() + mod_b.switchExpr(k);
    std.io.printInt(r);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.

## GREEN evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/aadd/diag_emission_conflation_control_xmod \
    repro/mi_matrix/emission_conflation_control_xmod/main.zig
zig_rc=0
$ cd <out> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=0
```

Benign (documented, not a failure): the `var k: mod_a.Kind = .a;` enum-literal init in main emits the
known `warning[3000]: type mismatch … source: void, target: enum` (the enum-literal void-degradation
probe in `emission_void_temp_enum_xmod` NOTES — the literal temp degrades to `int` and compiles).

## Root-cause pin / family guarded

CONFLATION family. The F-B fix (`lower.zig:5012/5017`) disambiguates same-named diff-type locals
scope/type-aware, so the emitted C names (`ck` / `ck_1`) are distinct per type. **GREEN today because
the fix is shape-general** — it applies to every container (if/switch/while/for), expression or
statement position, single- or cross-module.

## Expected post-fix result

Stays GREEN under the shape-general F-B disambiguation; this control catches a regression in the
if-expr/switch-expr containers.
