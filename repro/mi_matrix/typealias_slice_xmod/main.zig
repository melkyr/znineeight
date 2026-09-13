// typealias_slice_xmod — RED->GREEN (A9F-a). A slice alias (`const T = []i32`)
// initialized from an array; before the fix the array→array element mismatch
// produced a spurious `warning[3000]`.
// Fix (A9F-a): annotation element-type derivation + structural array→array.
// Contract: compile-clean, run prints 20\n.
const std = @import("std");

const T = []i32;

pub fn main() void {
    const b = [_]i32{ 10, 20, 30 };
    var s: T = b;
    std.io.printInt(s[1]);
    std.io.writeByte('\n');
}
