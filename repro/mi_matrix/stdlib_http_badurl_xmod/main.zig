// stdlib_http_badurl_xmod — STDLIB std_http (M0 §4.3) parseUrl rejections.
//
// Confirms three malformed inputs all return BadUrl: a non-http scheme
// (https://x), a missing scheme (://x) and the empty string.
//
// GREEN: deterministic byte-exact stdout `badurl ok\n` (rc 0).
const http = @import("std_http.zig");
const io = @import("std_io.zig");

fn expectBad(u: []const u8) void {
    _ = http.parseUrl(u) catch |e| {
        if (e != error.BadUrl) @panic("wrong error");
        return;
    };
    @panic("expected BadUrl");
}

pub fn main() void {
    var a: []const u8 = "https://x";
    var b: []const u8 = "://x";
    var c: []const u8 = "";
    expectBad(a);
    expectBad(b);
    expectBad(c);
    io.write("badurl ok\n");
}
