// S1 shape: a non-tuple variable print followed by a tuple-literal print
// rejects, and the error[3013] is attributed to the tuple call.
const std = @import("std");

pub fn main() void {
    var v: i32 = 5;
    std.io.print("bare-var={}\n", v);
    std.io.print("tuple={} {}\n", .{ 7, 8 });
}
