// D7.3 sibling probe: a slice assignment whose element type is itself a fixed
// array (`[2][4]u8` slices). The element-copy lowering supports scalar/struct
// elements only; this shape must reject cleanly, not hit the unsupported
// assignment-l-value ICE.
// REJECT contract: rc 2, one level-0 "array elements" diagnostic, 0 emitted `.c`.
const std = @import("std");

pub fn main() void {
    var a: [2][4]u8 = undefined;
    var b: [2][4]u8 = undefined;
    a[0..] = b[0..];
    std.io.printInt(@intCast(i32, a[0][0]));
    std.io.writeByte('\n');
}
