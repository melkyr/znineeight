// D14 sibling: real std_http2 tail-return wrapper shape.
//
// `waitId` performs the implicit await and returns a runtime payload; the
// outer wrapper tail-returns it. Pre-fix the emitted step ABI is
// GCC-incompatible (RED). Compile/build-only: a live server is required to
// run the suspension path.
const std = @import("std");
const h2 = @import("std_http2.zig");

fn waitId(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn waitWrapperTail(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    return waitId(c, id);
}

pub fn main() void {
    std.io.write("d14 http2 tail wrapper compile-only\n");
}
