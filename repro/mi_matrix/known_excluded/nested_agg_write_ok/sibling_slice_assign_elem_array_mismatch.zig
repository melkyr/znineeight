// D7.3 sibling probe: a direct slice assignment whose element types are both
// fixed arrays but of different lengths (`[2][4]u8` destination from `[2][5]u8`
// source). The array-element reject must run before the element-type equality
// return, so this is a clean level-0 reject instead of the unsupported
// assignment-l-value ICE.
// REJECT contract: rc 2, an `error[3000]` array-element diagnostic, 0 emitted `.c`.
const std = @import("std");

pub fn main() void {
    var a: [2][4]u8 = undefined;
    var b: [2][5]u8 = undefined;
    a[0..] = b[0..];
    std.io.printInt(@intCast(i32, a[0][0]));
    std.io.writeByte('\n');
}
