# emission_no_member_xmod — RED fixture for the 194-closeout `has no member` class (R4, 8 errors)

Task R4 (2026-08-22). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(HEAD 9bb771df; R1-R3 did not rebuild it). Build recipe identical to R1-R3: emit with
`--dump-c89`, compile emitted C with `gcc -m32 -std=c89`.

## Purpose

Full-graph (3-module) reproducer of the self-compile residual class
**`'<TypeName>' has no member named '<field>'`** (8 errors), e.g.
`type_resolver_7446D285.c:1500:16: error: 'zT_457ECFEE_EnumPayload' has no member
named 'payload'`, matching `zT_301 = ep.payload;`.

Two sub-shapes exist in the self-compile output (grep `/tmp/emit_errs_e2down.txt`):

1. **`.payload` shape** (5 errors, type_resolver `EnumPayload has no member 'payload'`;
   plus a 6th in c89_emit on a `Slice_...` type): field access `.payload` emitted
   against a C declaration of a *different* (non-payload) type.
2. **`.f_2` shape** (2 errors, c89_emit `anon_... has no member named 'f_2'`, from the
   `.float_const => |fc|` / `.int_const => |ic|` arms at c89_emit.zig:2741-2757): a
   `load_field` carries `field_id=2` where the payload anon struct only has 2 fields
   (`{ value, result }`), so the named-field path falls back to `.f_2`
   (c89_emit.zig:4680).

This fixture reproduces shape (1) byte-for-byte, including the identical mangled type
name `zT_457ECFEE_EnumPayload` and the two auxiliary `incompatible types` errors that
accompany it in the self-compile log (type_resolver_7446D285.c:1495-1496). Shape (2)
was probed but NOT reproduced in this task (see "f_2 shape: not reproduced").

## Trigger design (minimal, spec-valid, full-graph)

Mirrors `computeTypeLayout`-style if/else over `ty.kind` in `sf/src/type_resolver.zig`
(lines 157-223):

```zig
if (ty.kind == TypeKind.enum_type) {
    var ep = self.registry.en_items[@intCast(usize, ty.payload_idx)];  // EnumPayload
    var bt = self.registry.types_items[@intCast(usize, ep.backing_type)];
    return bt.size;
} else if (ty.kind == TypeKind.error_union_type) {
    var ep = self.registry.eu_items[@intCast(usize, ty.payload_idx)];  // EUPayload
    var pt = self.registry.types_items[@intCast(usize, ep.payload)];   // ep.payload
    return pt.size + ep.payload;
}
```

Two **same-named locals `ep` of different types in disjoint if/else-branch scopes**:
first `EnumPayload` (enum_type branch), later `EUPayload` (error_union_type branch,
struct with a `payload: u32` field). Legal Zig shadowing (disjoint block scopes);
`zig1` accepts the program rc=0 with no diagnostics. Full-graph: 3 modules
(`main → mod_a`, `main → mod_b → mod_a`) + bare `@import("std")`.

## Fixture (verbatim)

`mod_a.zig` — the type model (mirrors `TypeKind` / `EnumPayload` / `EUPayload` / `Type`
/ a `Registry`):
```zig
const std = @import("std");

pub const TypeKind = enum(u32) {
    enum_type,
    error_union_type,
};

pub const EnumPayload = struct { backing_type: u32 };
pub const EUPayload = struct { payload: u32 };
pub const Type = struct { kind: TypeKind, payload_idx: u32 };
pub const Registry = struct { enum_payload: EnumPayload, eu_payload: EUPayload };
```
`mod_b.zig` — the emission site (`computeTypeLayout`, the two `ep` locals):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const Type = mod_a.Type;
const TypeKind = mod_a.TypeKind;
const Registry = mod_a.Registry;

pub fn computeTypeLayout(reg: *Registry, ty: *Type) u32 {
    if (ty.kind == TypeKind.enum_type) {
        var ep = reg.enum_payload;
        var bt = ep.backing_type;
        return bt;
    } else if (ty.kind == TypeKind.error_union_type) {
        var ep = reg.eu_payload;
        var pt = ep.payload;
        return pt;
    }
    return 0;
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var reg = mod_a.Registry{
        .enum_payload = mod_a.EnumPayload{ .backing_type = 2 },
        .eu_payload = mod_a.EUPayload{ .payload = 3 },
    };
    var ty = mod_a.Type{ .kind = mod_a.TypeKind.error_union_type, .payload_idx = 0 };
    var r = mod_b.computeTypeLayout(&reg, &ty);
    std.io.printInt(@intCast(i32, r));
}
```

An earlier variant used array-indexed registry fields (`eu_items[...]`,
`types_items[...]`, mirroring the self-compile source verbatim) and reproduced the
conflation identically in `mod_b.c`, but the array-literal initialization in
`main.zig` triggered a *separate* pre-existing bug class (the R2 zT-undeclared array
fill `zT_1.enum_items[_j] = 0;`), polluting the full-graph RED. The committed variant
avoids arrays to keep the full-graph gcc compile producing ONLY the has-no-member
class (see "concerns").

## RED evidence (measured 2026-08-22, /tmp/fx_subfolder/zig1 @ 9bb771df)

```
$ rm -rf /tmp/r4_194/out; mkdir -p /tmp/r4_194/out; \
  timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r4_194/out \
  repro/mi_matrix/emission_no_member_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/r4_194/out && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
  -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class `'<TypeName>' has no member named '<field>'`, in
`mod_b_240036B5.c`):
```
mod_b_240036B5.c:55:10: error: incompatible types when assigning to type 'zT_457ECFEE_EnumPayload' from type 'zT_42C2D6BF_EUPayload'
   55 |     ep = zT_17;
      |          ^~~~~
mod_b_240036B5.c:56:10: error: incompatible types when assigning to type 'zT_457ECFEE_EnumPayload' from type 'zT_42C2D6BF_EUPayload'
   56 |     ep = zT_17;
      |          ^~~~~
mod_b_240036B5.c:58:15: error: 'zT_457ECFEE_EnumPayload' has no member named 'payload'
   58 |     zT_19 = ep.payload;
      |               ^
gcc_rc=1
```
Byte-for-byte identical to the self-compile text:
```
type_resolver_7446D285.c:1495:10: error: incompatible types when assigning to type 'zT_457ECFEE_EnumPayload' from type 'zT_42C2D6BF_EUPayload'
type_resolver_7446D285.c:1500:16: error: 'zT_457ECFEE_EnumPayload' has no member named 'payload'
```
— same message strings, and the mangled type names match exactly
(`zT_457ECFEE_EnumPayload`, `zT_42C2D6BF_EUPayload`).

Emitted C (the conflation signature, `mod_b_240036B5.c`):
```
    zT_457ECFEE_EnumPayload ep;   // hoisted decl — FIRST-seen type (EnumPayload)
    unsigned int bt;
    unsigned int pt;
    ...
    z_bb_1:                        // enum_type branch
    ep = zT_8;                     // EnumPayload value — OK
    zT_10 = ep.backing_type;
    ...
    z_bb_4:                        // error_union_type branch
    zT_17 = reg->eu_payload;
    ep = zT_17;                    // EUPayload value into EnumPayload decl — incompatible
    zT_19 = ep.payload;            // has no member 'payload'
```

## Probable mechanism (HYPOTHESIS — I may overturn this)

Same name-keyed-conflation family as R1/R2/R3. `emitHoistedDecls`
(`sf/src/c89_emit.zig:2642-2699`) collects `decl_local` temps by `name_id` into
`local_name_ids[]`; a later `decl_local` with a **duplicate `name_id`** is skipped
(`ldup`, c89_emit.zig:2669-2673) and the C declaration keeps the **first-seen type**.
Here both if-branches declare `var ep` (different types, disjoint scopes → same
`name_id`), so only one C local `ep` is emitted, typed `EnumPayload` (first-seen at
the enum_type branch). The later `load_field` instructions for `ep.payload` (the
error_union branch) carry the capture/local's `name_id`; emission writes `ep.payload`
(c89_emit.zig:4662-4680, struct_type named-field path) against the EnumPayload-typed
C local → gcc `'EnumPayload' has no member named 'payload'`. The two intermediate
`ep = zT_17;` stores produce the matching `incompatible types ... from 'EUPayload'`
errors seen in the self-compile log at 1495/1496.

This is the R3 `request for member` mechanism with the stale first-seen type being an
**aggregate** (struct) instead of a scalar, which changes gcc's wording from
`request for member ... in something not a structure or union` (scalar base) to
`'<TypeName>' has no member named '<field>'` (struct base). Same root cause.

Fix candidates (untested, same as R3): scope-correct local identity instead of flat
`name_id` dedup in `emitHoistedDecls`; disambiguate same-named locals/captures that
have different types; or lower with distinct name_ids when a same-named local already
exists.

## `f_2` shape: NOT reproduced (recorded honestly)

Probed with three spec-valid mirrors of the self-compile shape (a LirInst-like
`union(enum)` with `int_const {value:u64,result:u32}` / `float_const {value:f64,
result:u32}` payloads; switch captures `|ic|`/`|fc|` accessing `.result`; including a
container-indexed `while (i < insts.len)` over `[]const LirInst` with
`written_type[]/written_flag[]` marker writes mirroring c89_emit.zig:2704-2757). All
three compiled and emitted correct named-field accesses (`.result` / `.f_1`-style),
never `.f_2`. The self-compile `.f_2` requires the lowering `field_id` for `fc.result`
(=1) to be computed as 2 — the `typeRegistryGetStructFields` scan (lower.zig:2586-2590)
must find `result` at index 2 in the capture's resolved anon payload, i.e. the payload
anon type must be a 3+ field struct at lowering time. Probable trigger is an anon
payload type registration/collision that this fixture family did not reproduce;
recording as an unresolved sub-shape. If the `.f_2` class must also be covered, the
next step is to hunt the anon-payload identity collision (same anon type id reused for
two payload structs, or a payload struct with an extra leading field) in the type
registry.

## Expected post-fix result

After the fix, the `ep` in the error_union_type branch gets its own EUPayload-typed C
declaration (or a disambiguated name), so `ep.payload` compiles; `gcc -c` rc=0 and the
binary prints the resolveTempName-style sum.

## Concerns

- Array-indexed registry variant (closer to self-compile source) reproduced the
  conflation in `mod_b.c` identically but pulled in the unrelated R2 zT-undeclared
  class via main.zig's array-literal init, so the committed fixture avoids arrays. If
  a purist full-source mirror is wanted, that variant (documented above) is the
  alternative.
- `f_2` sub-shape not reproduced; documented as an open sub-shape.
