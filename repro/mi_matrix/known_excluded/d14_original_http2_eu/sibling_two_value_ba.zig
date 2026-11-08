// d14_original_http2_eu sibling: two value-returning imported waits, B then A.
//
// Same pair as `sibling_two_value_ab.zig` with the source order swapped. The
// sum is order-sensitive (43 + 42 = 85), but the reserved parent-result slot
// order is what P2/P4 must agree on. Compile-only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn valueWait(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn wrapper(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    var b = try valueWait(c, id + 1);
    var a = try valueWait(c, id);
    return b + a;
}

pub fn main() void {
    std.io.write("d14 original http2 eu two-value B,A compile-only\n");
}
