# emission_type_storage_extern_struct_xmod — RED fixture for residual A₂ (struct-type storage global)

Task R-VAR (2026-08-21, AMENDMENT 7 Ruling 4). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Variation of the A₂ base fixture (`emission_type_storage_extern_xmod`), which only tests an **enum**
type storage global (`zG_<hash>_Color`). This fixture proves the same A₂ residual for a
**struct-type** storage global (`zG_<hash>_Point`): the type storage global is defined in multiple
modules (main + mod_b ident-base aliases), and a reference-only module (mod_c) references it via its
const-type-alias init with NO `extern` in its include chain → gcc `'zG_<hash>_<Name>' undeclared`.
Structs need the extra `const P = Point;` hop (a struct has no enum-member access to load its storage
global; see iteration log) — a type-as-value alias init loads it.

## Fixture (verbatim)
`mod_a.zig` (type owner):
```zig
pub const Point = struct {
    x: u32,
    y: u32,
};
```
`mod_b.zig` (ident-base alias — registers `Point` as a global-kind symbol → storage-global **def**):
```zig
const mod_a = @import("mod_a.zig");

pub const Point = mod_a.Point;

pub fn sum(p: Point) u32 {
    return p.x + p.y;
}
```
`mod_c.zig` (reference-only: import-base alias + `const P = Point;` whose storage-global init loads
`zG_<hash>_Point`; mod_c's header chain reaches only mod_a.h, which has NO extern):
```zig
const Point = @import("mod_a.zig").Point;
const P = Point;

pub fn norm() u32 {
    var p: P = P{ .x = 1, .y = 2 };
    return p.x + p.y;
}
```
`main.zig` (ident-base alias — second **def**):
```zig
const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const Point = mod_b.Point;

pub fn main() void {
    var p = Point{ .x = 1, .y = 2 };
    std.io.printInt(@intCast(i32, mod_c.norm() + mod_b.sum(p)));
}
```
Import graph: `main → mod_b → mod_a`, `main → mod_c → mod_a`. 4 modules + std.

## RED baseline (measured 2026-08-21, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rA1 main.zig
rc=0
$ cd /tmp/rA1 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc error (class A₂, `'zG_<hash>_<Name>' undeclared`):
```
mod_c_8EA8DE60.c:33:12: error: 'zG_EAA8EF31_Point' undeclared (first use in this function); did you mean 'zT_EAA8EF31_Point'?
   33 |     zT_0 = zG_EAA8EF31_Point;
```
Emitting C — **definition multiplicity + missing extern** (mirrors the base enum shape):
```
main_*.c:2:   zT_EAA8EF31_Point zG_EAA8EF31_Point;   // def #1 (main ident-base alias)
mod_b_*.c:2:  zT_EAA8EF31_Point zG_EAA8EF31_Point;   // def #2 (mod_b ident-base alias)
mod_c_*.c:2:  zT_EAA8EF31_Point zG_D50C118F_P;      // mod_c's own const-P storage global
mod_c_*.c:33: zT_0 = zG_EAA8EF31_Point;             // ← ref, NO extern in mod_c's chain
mod_c_*.c:34: zG_D50C118F_P = zG_EAA8EF31_Point;    // const-P init loads the type storage
```
`mod_c.h` includes only `zig_compat.h`, `zig_special_types.h`, `mod_a.h` — mod_a's "Storage globals
(extern decls)" section is EMPTY (plain type_alias emits no extern), and mod_b.h (which holds the
extern for `zG_EAA8EF31_Point`) is not in mod_c's include chain.

## Iteration log (how the struct shape was found)
1. Ref-only mod_c using `Point` only as a param/return type: GREEN — no storage-global load.
2. Struct literals (`Point{...}` / `var p: Point = ...`) do NOT load the type storage global
   (they lower to field stores on a stack temp). Only the enum's member-access loads its storage
   global, so the base enum shape has no struct analog.
3. The trigger is a **type-as-value** alias `const P = Point;` in the ref-only module: lowering the
   const's storage-global init emits `zG_<hash>_P = zG_<hash>_Point;` → loads the struct type's
   storage global → undeclared (no extern in chain). This mirrors how self-compile storage-global
   init chains reference each other.

## Root cause pinned
Same A₂ as the base fixture: `emitGlobalDecls` (`c89_emit.zig:2441`/`:2448-2464`) emits a type-storage
global definition in every ident-base aliasing module, and the `extern` (`:2336`/`:2344-2360`) is only
propagated to the defining module's header — never into the reference-only module's include chain.

## Expected post-fix result
After the A₂ fix (single-owner definition in the type's owner module + extern propagated to every
referencing module's header chain): mod_c.h's chain reaches an extern for `zG_EAA8EF31_Point`, the
`const P = Point` init compiles, `gcc -c` rc=0, and the binary prints `mod_c.norm() + mod_b.sum(p)`
(`3 + 3 = 6`).
