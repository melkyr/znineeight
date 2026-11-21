// stdlib_http_parseurl_xmod — STDLIB std_http (M0 §4.3) parseUrl contract.
//
// parseUrl splits scheme://host[:port]/path[?query]; the scheme must be http;
// default port 80; an empty path becomes "/". Prints each parsed field for a
// URL with an explicit port and query, then the no-port / empty-path defaults,
// then confirms https:// is rejected with BadUrl.
//
// GREEN: deterministic byte-exact stdout (rc 0).
const std = @import("std");
const http = @import("std_http.zig");
const io = @import("std_io.zig");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn show(u: http.Url) void {
    io.write("host=");
    io.write(u.host);
    io.write(" port=");
    io.printInt(@intCast(i32, u.port));
    io.write(" path=");
    io.write(u.path);
    io.write(" query=");
    io.write(u.query);
    io.write("\n");
}

pub fn main() void {
    var u1s: []const u8 = "http://example.com:8080/path/to?x=1&y=2";
    const u1 = http.parseUrl(u1s) catch @panic("parse1");
    ck(eq(u1.host, "example.com"), "host1");
    ck(u1.port == @intCast(u16, 8080), "port1");
    ck(eq(u1.path, "/path/to"), "path1");
    ck(eq(u1.query, "x=1&y=2"), "query1");
    show(u1);

    var u2s: []const u8 = "http://host";
    const u2 = http.parseUrl(u2s) catch @panic("parse2");
    ck(u2.host.len == 4, "host2");
    ck(u2.port == @intCast(u16, 80), "port2");
    ck(eq(u2.path, "/"), "path2");
    ck(u2.query.len == 0, "query2");
    show(u2);

    var u3s: []const u8 = "https://x/p";
    _ = http.parseUrl(u3s) catch {
        io.write("https BadUrl\n");
        return;
    };
    @panic("https accepted");
}
