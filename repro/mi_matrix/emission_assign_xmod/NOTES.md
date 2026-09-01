# emission_assign_xmod — RED fixture for residual assign class (86 `incompatible types when assigning`)

Task R1 (2026-08-22). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Full-graph (3-module) reproducer of the dominant self-compile residual class:
`incompatible types when assigning` (86 errors — lower.c 59, semantic 8,
type_resolver 6, c89_emit/import_resolver/module_registry/pal/parser the rest).
The mechanism under test is **local-decl NAME-KEYED CONFLATION**: `emitHoistedDecls`
+ the `emitFunctionBody` hoist pass (`c89_emit.zig:6155-6216`) dedup hoisted local
declarations by source `name_id` (`dedup_names`). Two `var <same-name>` of
**different types** in one function collapse to a single C local declared with the
**first-seen** type; a later assignment of the second type to the same C name fails
in gcc with `incompatible types when assigning`.

## Fixture (verbatim)
`mod_a.zig` (defines the two colliding types + factories):
```zig
pub const Type = struct {
    id: u32,
    kind: u32,
};

pub const CoercionKind = enum(u8) {
    none,
    wrap_optional,
    wrap_error,
    int_widen,
};

pub fn makeType() Type {
    return .{ .id = 0, .kind = 0 };
}

pub fn makeCoercion() CoercionKind {
    return .int_widen;
}
```
`mod_b.zig` (the conflation site — same-named local `ck` in two sibling blocks):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const Type = mod_a.Type;
const CoercionKind = mod_a.CoercionKind;

pub fn run() void {
    {
        var ck: Type = mod_a.makeType();
        std.io.printInt(@intCast(i32, ck.id));
    }
    {
        var ck: CoercionKind = mod_a.makeCoercion();
        std.io.printInt(@intCast(i32, @enumToInt(ck)));
    }
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    mod_b.run();
}
```
Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 modules + std.

The fixture is deliberately shaped after the compiler's own `lower.zig`:
`Type` is a `struct { id, kind }` and `CoercionKind` is an `enum(u8)`. Because the
C type hashing follows the layout, the emitted C type names reproduce the
self-compile mangled names verbatim (`zT_D155D06D_Type`, `zT_0FB7FB13_CoercionKind`).

## RED baseline (measured 2026-08-22, /tmp/fx_subfolder/zig1 @ HEAD b5e3b7eb)
```
$ mkdir -p /tmp/r1_194
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1_194 \
    repro/mi_matrix/emission_assign_xmod/main.zig
rc=0
$ cd /tmp/r1_194 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class assign, 2 hits):
```
mod_b_126BD0B0.c:22:10: error: incompatible types when assigning to type 'zT_D155D06D_Type' from type 'zT_0FB7FB13_CoercionKind' {aka 'unsigned char'}
   22 |     ck = zT_6;
mod_b_126BD0B0.c:23:10: error: incompatible types when assigning to type 'zT_D155D06D_Type' from type 'zT_0FB7FB13_CoercionKind' {aka 'unsigned char'}
   23 |     ck = zT_6;
```
Byte-for-byte identical to self-compile lines (e.g. `lower_1EB7D337.c:40682/40683`):
`incompatible types when assigning to type 'zT_D155D06D_Type' from type
'zT_0FB7FB13_CoercionKind' {aka 'unsigned char'}` — same message, same mangled type
names, same error text.

Emitting C — the conflation signature:
```
zT_D155D06D_Type ck;              // ← hoisted ONCE, with the FIRST block's type (Type)
z_bb_0:
zT_1 = zF_B0830F77_makeType();
ck = zT_1;                        // block 1: Type = Type — fine
...
zT_6 = zF_146F113F_makeCoercion();
ck = zT_6;                        // ← block 2: CoercionKind into Type-typed ck → gcc error
ck = zT_6;                        // ← same (store_local + assign both keyed on name)
```
The second sibling block's `var ck: CoercionKind = ...` emits a `decl_local` with the
same `name_id` as block 1's `var ck: Type`. The hoist dedup (`dedup_names`,
`c89_emit.zig:6155-6180`) skips it, so no second C declaration appears; the block's
`store_local`/`assign` (both carrying `name_id = ck`, `c89_emit.zig:4272`,
`:4441-4448`) resolve to the single C local `ck`, which is still typed `Type` →
`unsigned char` `CoercionKind` value assigned into a `Type` struct → incompatible.

## Probable mechanism (HYPOTHESIS — I may overturn this)
`sf/src/c89_emit.zig` local-decl hoisting keys solely on `name_id`
(`emitHoistedDecls` `local_name_ids` dedup at `:2667-2690`; `emitFunctionBody`
`dedup_names` pass at `:6155-6180`, decl emitted at `:6196-6205`). Sibling-block
shadowing of the same source name reuses one `name_id` (only *captures* are
disambiguated, `lower.zig:4895-4914`), so the C local is declared with the first
type and every later assignment to the same-named C variable must satisfy the first
type. That yields the self-compile assign class. An alternative reading — that the
defect is a `store_local`/`assign` type mismatch (dst temp typed wrong) — is not
supported by the emitted C here: the failing statement is the C-level assignment
into the `Type`-typed `ck`, i.e. the hoisted declaration carried the first-seen type.
Fix candidates (untested): disambiguate same-named locals across sibling blocks like
captures are; or make the hoist dedup type-aware (redeclare when the type differs);
or emit the second declaration with its own C name.

## Expected post-fix result
After the fix, block 2's `ck` (CoercionKind) either gets its own declaration/name or
the type is preserved per-scope; `gcc -c` rc=0 and the binary prints the struct id
then the enum index.
