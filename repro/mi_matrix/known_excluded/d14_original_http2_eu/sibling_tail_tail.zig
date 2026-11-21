// d14_original_http2_eu sibling: imported NESTED TAIL/TAIL.
//
// A value-returning imported wait is tail-returned through two wrapper levels
// (`return submitTail(...)` from `http2GetTail`). Compile-only.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn waitVal(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn submitTail(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    return waitVal(c, id);
}

fn http2GetTail(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    return submitTail(c, id);
}

pub fn main() void {
    std.io.write("d14 original http2 eu nested tail/tail compile-only\n");
}
