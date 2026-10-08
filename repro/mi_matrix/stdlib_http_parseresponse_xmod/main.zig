// stdlib_http_parseresponse_xmod — STDLIB std_http (M0 §4.3) parseResponse.
//
// Parses a full raw `HTTP/1.1 200 OK` response with a Content-Length header
// and a 3-byte body. Prints the status, the first header (name=value) and the
// body, byte-exactly.
//
// GREEN: deterministic byte-exact stdout (rc 0).
const std = @import("std");
const http = @import("std_http.zig");
const io = @import("std_io.zig");

pub fn main() void {
    var ar_storage: [4096]u8 = undefined;
    var ar = std.arena.init(ar_storage[0..]);

    var raw: []const u8 = "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc";
    const r = http.parseResponse(&ar, raw) catch @panic("parse");

    io.write("status ");
    io.printInt(@intCast(i32, r.status));
    io.write("\n");

    io.write("header ");
    io.write(r.headers[0].name);
    io.write("=");
    io.write(r.headers[0].value);
    io.write("\n");

    io.write("body ");
    io.write(r.body);
    io.write("\n");
}
