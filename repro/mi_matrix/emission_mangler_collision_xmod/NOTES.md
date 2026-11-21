# emission_mangler_collision_xmod — RED fixture for root cause A (type storage-global name-mangling collision)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

**Updated 2026-08-20 (post-fix definability fix):** the owner module now emits
the type's storage-global definition, mirroring the self-compile
(`main_9472B9CB.c:18`). The reviewer finding that motivated this change:
the original fixture had NO value-use of `Color` in the owner, so no
`global_decls` entry existed and `zG_E5B43CF8_Color` was *never* defined
anywhere — a correct mangler fix alone could not flip the fixture GREEN.

## Purpose
Minimal reproducer of **root cause A** from the Task D discovery report
(`.superpowers/sdd/task-D-emission-report.md`): `nameManglerMangle`
(`sf/src/c89_emit.zig:400-476`) builds its cache key from `(module_id, kind,
name_id)` at `:404`, but the collision maps `collision_mod`/`collision_name`
are keyed **only by the mangled string** (`:472-473`). A named type's storage
global (e.g. `zG_<hash>_Color`) is re-mangled once per referencing module;
each re-mangle is mis-detected as a name collision and gets a `_1…_N`
suffix. Only the module with a *global-kind* symbol of that name emits a
definition (`emitGlobalDecls`, `c89_emit.zig:2433-2449`), so every other
module references a never-defined suffixed name → gcc class-1 error.

## Fixture (verbatim, post-fix-definability layout)
`color.zig` (owns the `Color` enum type — mirrors `ast.zig` owning `AstKind`):
```zig
pub const Color = enum(u8) {
    Red,
    Green,
    Blue,
};
```
`tmod.zig` (imports + aliases `Color` with an *ident-base* field access, so
`Color` registers as `SymbolKind.global` and gets a `global_decls` entry —
mirrors `main.zig`'s `const AstKind = ast_mod.AstKind;`, which emits
`zG_8143F551_AstKind` in `main_9472B9CB.c:18`):
```zig
const color = @import("color.zig");

pub const Color = color.Color;

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}
```
`cmod1.zig` / `cmod2.zig` (import `tmod` for the post-fix header chain — see
below — and alias `Color` directly from `color.zig` with an *import-base*
field access, so their `Color` is `SymbolKind.global` with
`gv_is_storage = 0` → reference-only, no definition emitted):
```zig
const tmod = @import("tmod.zig");
const Color = @import("color.zig").Color;
pub fn kind1() i32 {
    return switch (Color.Red) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
```
(`cmod2.zig` identical except `kind2()` switches on `Color.Blue`.)
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

The `const Color = @import("...").Color;` alias in each importing module
registers `Color` as a *global* symbol (symbol_registrator's `registerDecl`,
`symbol_registrator.zig:224-294`), so referencing `Color.Red` / `Color.Blue`
lowers to a `load_global` of the type-storage global, which `load_global`
(`c89_emit.zig:4384-4428`) mangles with the *referencing* module id at
`:4385`.

**Why tmod (not a plain value-use) emits the definition:** the reviewer's
suggested value-use (`pub const color_val = Color.Red;`) only registers a
`global_decls` entry named `color_val` (emits `zG_76C4DEBC_color_val`) — it
does **not** emit the `zG_E5B43CF8_Color` type-storage definition, so the
collision target stays undefined and the fixture cannot go GREEN. The actual
self-compile mechanism is the ident-base field-access alias: `main.zig`'s
`const AstKind = ast_mod.AstKind;` (`sf/src/main.zig:46`) registers a
*global-kind* symbol named `AstKind` whose init base is an identifier (not an
`import_expr`), so `main.zig:604-606`'s storage-kill does not fire →
`global_decls` entry → definition emitted. The fixture reproduces that exactly
with tmod aliasing `color.Color`. A type_alias (`pub const Color = enum{...}`)
never yields such an entry, which is why the original fixture emitted no
definition. (`cmod1/cmod2` resolve `Color` from `color.zig` directly rather
than through tmod's global-kind symbol, which keeps the enum-constant lowering
concrete; they still import tmod so their headers include `tmod.h` for the
post-fix extern.)

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
cmod1_EF4E2CAD.c:13:12: error: 'zG_E5B43CF8_Color' undeclared (first use in this function); did you mean 'zT_E5B43CF8_Color'?
cmod2_7EC77050.c:13:12: error: 'zG_E5B43CF8_Color_1' undeclared (first use in this function); did you mean 'zG_E5B43CF8_Color_2'?
```
Emitted C (the collision signature) — the **owner's definition is now present**
(gcc's `zG_E5B43CF8_Color_2` suggestion for cmod2 is that definition):
```
tmod_6233D119.c:2:     zT_E5B43CF8_Color zG_E5B43CF8_Color_2;   // owner def, _2-suffixed by the bug
tmod_6233D119.h:13:    extern zT_E5B43CF8_Color zG_E5B43CF8_Color_2;
cmod1_EF4E2CAD.c:13:    zT_0 = zG_E5B43CF8_Color;                // referencing module 1 → unsuffixed
cmod2_7EC77050.c:13:    zT_0 = zG_E5B43CF8_Color_1;            // referencing module 2 → "_1", undefined
```
`grep 'zG_E5B43CF8_Color' *.c *.h` → two refs (`_Color`, `_Color_1`) plus the
owner's definition (`_Color_2`) and its extern. The owner's definition being
suffixed too mirrors the self-compile's `symbol_registrator_757C4BC5.c:3:
zT_33EF6BFB_TypeKind zG_33EF6BFB_TypeKind_2;` (D-report line 44/51): tmod
mangles after cmod1/cmod2 (module emission order), so the collision map
mis-suffixes the owner's own definition.

## Root cause pinned
`sf/src/c89_emit.zig:404` (mangler cache key includes `module_id`),
`:431-473` (collision detection keyed only by mangled string), `:4385`
(`load_global` mangles with referencing module), `:2438` (`emitGlobalDecls`
defines only the owner's unsuffixed name). Root cause A of the D report.

## Expected post-fix result (corrected)
After fixing `nameManglerMangle` (collision maps keyed by `(name_id,kind)` or
per-name mangling that ignores `module_id` for type storage globals), all
modules mangle `Color`'s storage global to the **same** `zG_E5B43CF8_Color`:
cmod1/cmod2 both reference `zG_E5B43CF8_Color`, tmod's definition and its
`tmod.h` extern become the unsuffixed `zG_E5B43CF8_Color`, and because
`cmod1.h`/`cmod2.h` both include `tmod.h`, the extern is visible in every
referencing TU → `gcc -c` rc=0 and the binary prints `4` (`kind1() + kind2()` =
`1 + 3`; `kind1()` switches on `Color.Red` → 1, `kind2()` switches on
`Color.Blue` → 3 — the documented `3 (1 + 2)` in an earlier revision was a DOC
ERROR). The emitted `case 0/1/2` switch resolution is correct post-fix.
(Verified: renaming the emitted `_1`/`_2` suffixes to the unsuffixed name —
the post-fix mangler simulation — makes `gcc -c` rc=0.)
