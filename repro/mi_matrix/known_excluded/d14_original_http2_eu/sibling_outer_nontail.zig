// d14_original_http2_eu sibling: imported outer NON-TAIL.
//
// `submitUrl` is the non-tail inner (`try http2Wait; return id`); the outer
// `http2GetNonTail` binds with `var x = try submitUrl(...); return x;`.
// Compile-only (live HTTP/2 peer required to run).
const std = @import("std");
const h2 = @import("std_http2.zig");

fn submitUrl(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn http2GetNonTail(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    var x = try submitUrl(c, id);
    return x;
}

pub fn main() void {
    std.io.write("d14 original http2 eu outer non-tail compile-only\n");
}
