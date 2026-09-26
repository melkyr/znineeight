// S1 shape: the spec explicitly allows a tuple VARIABLE as the argument
// container ("tuple literal ... or a tuple variable"), but a tuple variable is
// rejected with error[3013]. Clean reject (not the D7 silent no-op).
const std = @import("std");

pub fn main() void {
    const t = .{ 7, 8 };
    std.io.print("tuple-var={} {}\n", t);
}
