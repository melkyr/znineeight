# emission_mangler_collision_xmod — RED fixture for root cause A (type storage-global name-mangling collision)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Minimal reproducer of **root cause A** from the Task D discovery report
(`.superpowers/sdd/task-D-emission-report.md`): `nameManglerMangle`
(`sf/src/c89_emit.zig:400-476`) builds its cache key from `(module_id, kind,
name_id)` at `:404`, but the collision maps `collision_mod`/`collision_name`
are keyed **only by the mangled string** (`:472-473`). A named type's storage
global (e.g. `zG_<hash>_Color`) is re-mangled once per referencing module;
each re-mangle is mis-detected as a name collision and gets a `_1…_N`
suffix. Only the owning module emits the unsuffixed definition
(`emitGlobalDecls`, `c89_emit.zig:2433-2449`), so every other module
references a never-defined suffixed name → gcc class-1 error.

## Fixture (verbatim)
`tmod.zig`:
```zig
pub const Color = enum(u8) {
    Red,
    Green,
    Blue,
};

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}
```
`cmod1.zig`:
```zig
const Color = @import("tmod.zig").Color;
pub fn kind1() i32 {
    return switch (Color.Red) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
```
`cmod2.zig`:
```zig
const Color = @import("tmod.zig").Color;
pub fn kind2() i32 {
    return switch (Color.Blue) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
```
`main.zig`:
```zig
const std = @import("std");
const m1 = @import("cmod1.zig");
const m2 = @import("cmod2.zig");
const Color = @import("tmod.zig").Color;

pub fn main() void {
    std.io.printInt(m1.kind1() + m2.kind2());
}
```

The `const Color = @import("tmod.zig").Color;` alias in each importing module
registers `Color` as a *global* symbol (symbol_registrator's
`registerDecl`, `symbol_registrator.zig:224-294`), so referencing `Color.Red`
/ `Color.Blue` lowers to a `load_global` of the type-storage global, which
`load_global` (`c89_emit.zig:4384-4428`) mangles with the *referencing*
module id at `:4385`.

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx main.zig
rc=0
$ cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class 1, `zG_ undeclared` + mangling-collision suffix):
```
cmod1_F84B6A15.c:13:12: error: 'zG_E5B43CF8_Color' undeclared (first use in this function); did you mean 'zT_E5B43CF8_Color'?
cmod2_051C6598.c:13:12: error: 'zG_E5B43CF8_Color_1' undeclared (first use in this function); did you mean 'zT_E5B43CF8_Color'?
```
Emitted C (the collision signature):
```
cmod1_F84B6A15.c:13:    zT_0 = zG_E5B43CF8_Color;      // referencing module 1 → unsuffixed (owner-name)
cmod2_051C6598.c:13:    zT_0 = zG_E5B43CF8_Color_1;    // referencing module 2 → "_1" suffixed, never defined
```
`grep 'zG_E5B43CF8_Color' *.c` → only the two references; no definition
anywhere, matching the D-report class-1 signature `zG_8143F551_AstKind_1`
(`parser_61A67AF1.c:1530`).

## Root cause pinned
`sf/src/c89_emit.zig:404` (mangler cache key includes `module_id`),
`:431-473` (collision detection keyed only by mangled string), `:4385`
(`load_global` mangles with referencing module), `:2438` (`emitGlobalDecls`
defines only the owner's unsuffixed name). Root cause A of the D report.

## Expected post-fix result
After fixing `nameManglerMangle` (collision maps keyed by `(name_id,kind)`
or per-name mangling that ignores `module_id` for type storage globals), all
modules reference the same defined `zG_<hash>_Color`; gcc `-c` rc=0 and the
binary prints `3` (`1 + 2`).
