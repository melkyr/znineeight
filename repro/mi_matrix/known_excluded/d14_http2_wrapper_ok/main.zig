// d14_http2_wrapper_ok — Phase 3.5 D14 exact std_http2 wrapper shapes.
//
// Non-tail forms of the real convenience API: a `http2Wait` wrapper that
// returns `Http2Error!u32` with a runtime id, and a `http2Get` wrapper that
// returns the submitted stream id. Both must lower to a GCC-compatible step
// ABI.
//
// Compile-only for the wrapper paths: driving them needs a live HTTP/2 peer,
// so this fixture only proves zig1 emission and the C build. The runnable
// main just prints the usage line.
const std = @import("std");
const h2 = @import("std_http2.zig");
const http = @import("std_http.zig");

fn waitWrapper(c: *h2.Http2Conn, id: u32) h2.Http2Error!u32 {
    try h2.http2Wait(c, id);
    return id;
}

fn getWrapper(c: *h2.Http2Conn, url: []const u8, out: *http.Response, id_out: *u32) h2.Http2Error!u32 {
    try h2.http2Get(c, url, out, id_out);
    return id_out.*;
}

pub fn main() void {
    std.io.write("d14 http2 wrapper compile-only\n");
}
