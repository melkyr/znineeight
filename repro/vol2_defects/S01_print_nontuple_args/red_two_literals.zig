// S1 shape: two non-tuple literal print calls in one module reject, but the
// error[3013] is attributed to the FIRST call (wrong span), not the offending
// second call.
const std = @import("std");

pub fn main() void {
    std.io.print("one={}\n", 1);
    std.io.print("two={}\n", 2);
}
