// w3000fp_tuple_array_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// `var a: [3]u32 = .{ 1, 2, 3 };` — an anonymous list literal `.{...}` coerces to
// an array when the element count matches and each element coerces to the
// element type. `semanticAnalyzerResolveTupleLiteral` (`sf/src/
// semantic_analyzer.zig:3186-3200`) always builds a `tuple_type` and ignores the
// expected array type; `typeRegistryIsAssignable` has no tuple->array arm
// (`sf/src/type_registry.zig:1151-1304`), so the var-decl warns
// `source: tuple / target: array`.
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file.
//
// Runtime (today): prints `13`; the initializer list is emitted correctly.
const std = @import("std");

pub fn main() void {
    var a: [3]u32 = .{ 1, 2, 3 };
    var b: [4]u8 = .{ 4, 5, 6, 7 };
    std.io.printInt(@intCast(i32, a[0] + a[1] + a[2] + @intCast(u32, b[3])));
    std.io.writeByte('\n');
}
