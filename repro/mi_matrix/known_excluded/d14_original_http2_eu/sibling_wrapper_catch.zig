// d14_original_http2_eu sibling: imported CATCH wrapper around the await.
//
// The imported value wait is bound with `catch |e| return e;` instead of
// `try`. Compile-only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn valueWait(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn wrapper(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    const v = valueWait(c, id) catch |e| return e;
    return v;
}

pub fn main() void {
    std.io.write("d14 original http2 eu catch wrapper compile-only\n");
}
