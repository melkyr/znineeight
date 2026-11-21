// d14_original_http2_eu sibling: imported IF wrapper around the await.
//
// The imported value wait is inside a conditional arm; the fallthrough returns
// the id without awaiting. Compile-only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn valueWait(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn wrapper(c: *h2.Http2Conn, id: u32, cond: bool) h2.Http2Error!u32 {
    if (cond) {
        var v = try valueWait(c, id);
        return v;
    }
    return id;
}

pub fn main() void {
    std.io.write("d14 original http2 eu if wrapper compile-only\n");
}
