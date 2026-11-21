// d14_original_http2_eu sibling: mixed VOID then VALUE imported waits.
//
// `h2.http2Wait` returns `h2.Http2Error!void` (no parent-result slot); the
// following imported value wait reserves the first kind-7 slot. Compile-only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn valueWait(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn wrapper(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    var v = try valueWait(c, id);
    return v;
}

pub fn main() void {
    std.io.write("d14 original http2 eu mixed void,value compile-only\n");
}
