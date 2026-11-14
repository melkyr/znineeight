// stdlib_http_parseresponse_chunked_reject_xmod — STDLIB std_http (M0 §4.3).
//
// Documents the chunked deferral: a response carrying
// `Transfer-Encoding: chunked` MUST be rejected with BadResponse rather than
// mis-parsed as a close-delimited body.
//
// GREEN: deterministic byte-exact stdout `chunked rejected\n` (rc 0).
const std = @import("std");
const http = @import("std_http.zig");
const io = @import("std_io.zig");

pub fn main() void {
    var ar_storage: [4096]u8 = undefined;
    var ar = std.arena.init(ar_storage[0..]);

    var raw: []const u8 = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n";
    _ = http.parseResponse(&ar, raw) catch |e| {
        if (e != error.BadResponse) @panic("wrong error");
        io.write("chunked rejected\n");
        return;
    };
    @panic("chunked accepted");
}
