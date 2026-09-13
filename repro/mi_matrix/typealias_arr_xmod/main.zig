// typealias_arr_xmod — RED->GREEN (A9F-a). An annotated array alias
// (`const T = [3]i32`) initialized from an inferred-length literal `[_]i32{...}`.
//
// RED baseline (A9I fixed point `7a9a9081`): the `[_]T` element type is
// hardcoded to u32, so source `[3]u32` vs target `[3]i32` emits a spurious
// `warning[3000]: type mismatch in variable declaration` (not alias-specific:
// `var b: [2]u8 = [_]u8{...}` warns identically).
// GREEN: element type derived from the annotation → silent; run prints 6\n.
// Fix (A9F-a): sema `semanticAnalyzerResolveArrayInit` resolves the inferred
// length annotation's element type; `typeRegistryIsAssignable`/`classifyCoercion`
// gain structural array→array.
const std = @import("std");

const T = [3]i32;

pub fn main() void {
    var a: T = [_]i32{ 1, 2, 3 };
    std.io.printInt(a[0] + a[1] + a[2]);
    std.io.writeByte('\n');
}
