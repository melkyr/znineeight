// typealias_mptr_xmod — RED->GREEN (A9F-a). A many-pointer alias
// (`const T = [*]u8`) initialized from `&array`. Before the fix BOTH the
// inferred-length array literal AND the ptr-to-array→many-pointer assignment
// emitted spurious `warning[3000]`s.
// Fix (A9F-a): annotation element-type derivation + array→array and
// pointer-to-array→many-pointer structural branches.
// Contract: compile-clean, run prints 15\n.
const std = @import("std");

const T = [*]u8;

pub fn main() void {
    var b: [2]u8 = [_]u8{ 7, 8 };
    var p: T = &b;
    std.io.printInt(@intCast(i32, p[0] + p[1]));
    std.io.writeByte('\n');
}
