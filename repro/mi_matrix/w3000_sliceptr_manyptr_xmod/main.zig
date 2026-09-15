// w3000_sliceptr_manyptr_xmod — Task 0k warning[3000] pin (VALID Z98 -> (a)).
//
// Reproduces the compiler's own `sf/src/main.zig:992`
// (`emitter.global_decls = gd_slice.ptr;`): reading `.ptr` from a slice yields a
// many-item pointer (`Language_Spec_Z98.md:67-68`: "`slice.ptr` returns a
// many-item pointer (`[*]T` or `[*]const T`)"), but the checker types the field
// access as a single-item `pointer`, so assigning it to a `[*]T` target warns
// `source: pointer / target: many-pointer`.
//
// Classification (Task 0k): (a) valid Z98, fix = type-checker accuracy
// (slice `.ptr` must resolve to `[*]T`, not `*T`).
//
// Runtime (today): prints `7`; the pointer value is carried through unchanged.
const std = @import("std");

pub fn main() void {
    var a: [3]u8 = [3]u8{ 7, 8, 9 };
    var s: []u8 = a[0..];
    var p: [*]u8 = s.ptr;
    if (p[0] != 7) { @panic("w3000_sliceptr_manyptr_xmod: p[0] != 7"); }
    std.io.printInt(@intCast(i32, p[0]));
    std.io.writeByte('\n');
}
