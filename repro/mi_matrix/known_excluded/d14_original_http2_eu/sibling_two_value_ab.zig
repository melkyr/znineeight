// d14_original_http2_eu sibling: two value-returning imported waits, A then B.
//
// Both waits return `h2.Http2Error!u32`; the second uses `id + 1` so the
// returned sum is order-sensitive (42 + 43 = 85). Compile-only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn valueWait(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn wrapper(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    var a = try valueWait(c, id);
    var b = try valueWait(c, id + 1);
    return a + b;
}

pub fn main() void {
    std.io.write("d14 original http2 eu two-value A,B compile-only\n");
}
