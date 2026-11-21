# emission_type_storage_extern_xmod — RED fixture for residual A₂ (type-storage global: multi-module definition + missing extern propagation)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Full-graph reproducer of **residual A₂** from the self-compile-residual-closeout
spec (`docs/superpowers/specs/2026-08-20-self-compile-residual-closeout-design.md`):
type-storage globals (e.g. `zG_8143F551_AstKind`) are **defined** in multiple
modules but the `extern` declaration lives only in the owner's header. A
referencing module whose emitted include chain does NOT reach the owner header
references the storage global with no declaration visible → gcc
`'zG_<hash>_<Name>' undeclared`.

The F-A mangling-collision fix (`c98590b7` + follow-ups) makes every module
mangle the storage global to the **same** name, but leaves
**definition multiplicity + missing extern propagation** — the A₂ residual
(182 self-compile errors at HEAD `8d9af49d`).

## Fixture (verbatim)
`mod_a.zig` (type owner — mirrors `ast.zig` owning `AstKind`; a plain type_alias
never yields a `global_decls` entry, so it emits no definition):
```zig
pub const Color = enum(u8) {
    Red,
    Green,
    Blue,
};
```
`mod_b.zig` (ident-base field-access alias — registers `Color` as a
*global-kind* symbol whose init base is an identifier, so the storage-kill does
not fire and a `global_decls` entry → **definition** `zG_E5B43CF8_Color` +
`extern` in `mod_b.h`. Mirrors `main_9472B9CB.c:18` / `front_resolution_D5E9117C.c:5`):
```zig
const mod_a = @import("mod_a.zig");

pub const Color = mod_a.Color;

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}
```
`mod_c.zig` (import-base alias + value-use — *reference-only*; does NOT import
`mod_b`, so its header chain reaches only `mod_a.h`, which has NO extern.
Mirrors `analyzer_2FA863C8.c`):
```zig
const Color = @import("mod_a.zig").Color;

pub fn kind() i32 {
    return switch (Color.Red) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
```
`main.zig` (ident-base alias `const Color = mod_b.Color;` also emits a
definition — reproducing the **definition multiplicity** of the self-compile
shape, where `main_9472B9CB.c:18`, `front_resolution_D5E9117C.c:5` and
`analyzer_2FA863C8.c` all define the same storage global):
```zig
const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const Color = mod_b.Color;

pub fn main() void {
    std.io.printInt(mod_c.kind() + mod_b.name(Color.Blue));
}
```
Import graph: `main → mod_b → mod_a`, `main → mod_c → mod_a`. 4 modules + std.

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rA2 main.zig
rc=0
$ cd /tmp/rA2 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc error (class A₂, `'zG_<hash>_<Name>' undeclared`):
```
mod_c_3984AE8D.c:13:12: error: 'zG_E5B43CF8_Color' undeclared (first use in this function); did you mean 'zT_E5B43CF8_Color'?
   13 |     zT_0 = zG_E5B43CF8_Color;
```
Emitting C — **definition multiplicity + missing extern**:
```
main_3DF5832C.c:2:  zT_E5B43CF8_Color zG_E5B43CF8_Color;        // def #1
main_3DF5832C.h:15: extern zT_E5B43CF8_Color zG_E5B43CF8_Color;  // extern
mod_b_1718E5AA.c:2:  zT_E5B43CF8_Color zG_E5B43CF8_Color;        // def #2
mod_b_1718E5AA.h:13: extern zT_E5B43CF8_Color zG_E5B43CF8_Color;  // extern
mod_c_3984AE8D.c:13: zT_0 = zG_E5B43CF8_Color;                   // ref, NO extern in chain
```
`mod_c.h` includes only `zig_compat.h`, `zig_special_types.h`, `mod_a.h` — the
`mod_a.h` "Storage globals (extern decls)" section is EMPTY (type_alias emits no
extern), and `mod_b.h` (which holds the extern) is not in mod_c's include chain.
So the reference at `mod_c.c:13` has no visible declaration → the exact
self-compile error shape (`analyzer_2FA863C8.c:92/:303/:340`).

## Root cause pinned
`sf/src/c89_emit.zig` — where the type-storage global definition is emitted
(`emitGlobalDecls` `:2441` def / `:2336` extern) and to whom the `extern` is
propagated. Each ident-base aliasing module (`main`, `mod_b`) emits its own
definition, and the extern is only emitted into the defining module's header,
not propagated to every referencing module's include chain. A₂ of the spec.

## Expected post-fix result
After the A₂ fix (single-owner definition in the type's owner module + `extern`
propagated into every referencing module's header chain, keyed by the
`types_items[type_id].name_id == name_id` discriminator already used in
`nameManglerMangleGlobal`): `mod_c.h`'s include chain reaches an extern for
`zG_E5B43CF8_Color`, so `gcc -c` rc=0. The binary should print the value of
`mod_c.kind() + mod_b.name(Color.Blue)` (`1 + 2 = 3`).
