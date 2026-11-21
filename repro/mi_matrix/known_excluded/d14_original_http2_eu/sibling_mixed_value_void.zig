// d14_original_http2_eu sibling: mixed VALUE then VOID imported waits.
//
// The value wait reserves kind-7 slot 0 first; the trailing void wait reserves
// no slot and must not advance `k`. Compile-only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn valueWait(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn wrapper(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    var v = try valueWait(c, id);
    try h2.http2Wait(c, id);
    return v;
}

pub fn main() void {
    std.io.write("d14 original http2 eu mixed value,void compile-only\n");
}
