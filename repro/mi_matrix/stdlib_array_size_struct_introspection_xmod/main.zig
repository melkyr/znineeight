// stdlib_array_size_struct_introspection_xmod — Task 11H regression: struct
// aggregate introspection folds in array-size positions.
//
// DEFECT (before the fix): `evalConstU32Full` (sf/src/type_resolver.zig) runs
// inside `typeResolverResolveNames`, BEFORE `typeResolverResolve` computes
// aggregate layout and sets `state == 2`, and `evalConstScalarKind` excluded
// the aggregate kinds — so `[@sizeOf(S)]` / `[@alignOf(S)]` / `[@bitSizeOf(S)]`
// of a struct hard-errored `error[3050]` at module scope, in an aggregate
// field, and in a function local. Removing the `state == 2` gate instead
// produced a silently WRONG `[1]` for the aggregate-field position (true 16),
// because that field's array type is resolved exactly once, pre-layout, and is
// never re-resolved.
//
// FIX (Task 11H, Option B — AMENDMENT 10): ONE shared, order-independent
// `layoutEnsure` completes the referenced struct on demand by walking every
// direct dependency first (deferring on `0`/`TYPE_UNDEFINED`/`TYPE_VOID`
// placeholders and on the depth cap) and only then running the existing layout
// math; the fold runs only from `state == 2`. The normal topological pass uses
// the same function, so there is exactly one layout implementation and one
// dependency walk. `evalConstScalarKind` stays the integer whitelist, so
// tuple/slice/union/enum and forward/cyclic aggregates stay `error[3050]`
// (never silently wrong).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   mod-size=16
//   field-size=16
//   local-size=16
//   align=8
//   bits=128
//   packed=1
//   done
const std = @import("std");

const S = struct { a: u32, b: u64 };
const P = packed struct { a: u4, b: u4 };

// module-scope array sized by struct introspection
var g_mod: [@sizeOf(S)]u8 = undefined;
var g_align: [@alignOf(S)]u8 = undefined;
var g_bits: [@bitSizeOf(S)]u8 = undefined;
// packed struct: @sizeOf = 1 (never the naive-struct 2)
var g_packed: [@sizeOf(P)]u8 = undefined;

// aggregate-field array sized by struct introspection (the wrong-[1] hazard)
const T = struct { data: [@sizeOf(S)]u8 };

pub fn main() void {
    if (g_mod.len != 16) { @panic("array_size_struct_introspection: mod size"); }
    std.io.print("mod-size=");
    std.io.printInt(@intCast(i32, g_mod.len));
    std.io.print("\n");

    var t: T = undefined;
    if (t.data.len != 16) { @panic("array_size_struct_introspection: field size"); }
    std.io.print("field-size=");
    std.io.printInt(@intCast(i32, t.data.len));
    std.io.print("\n");

    var g_loc: [@sizeOf(S)]u8 = undefined;
    if (g_loc.len != 16) { @panic("array_size_struct_introspection: local size"); }
    std.io.print("local-size=");
    std.io.printInt(@intCast(i32, g_loc.len));
    std.io.print("\n");

    if (g_align.len != 8) { @panic("array_size_struct_introspection: align"); }
    std.io.print("align=");
    std.io.printInt(@intCast(i32, g_align.len));
    std.io.print("\n");

    if (g_bits.len != 128) { @panic("array_size_struct_introspection: bits"); }
    std.io.print("bits=");
    std.io.printInt(@intCast(i32, g_bits.len));
    std.io.print("\n");

    if (g_packed.len != 1) { @panic("array_size_struct_introspection: packed"); }
    std.io.print("packed=");
    std.io.printInt(@intCast(i32, g_packed.len));
    std.io.print("\n");

    std.io.print("done\n");
}
