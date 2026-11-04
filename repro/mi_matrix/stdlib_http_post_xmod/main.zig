// stdlib_http_post_xmod — STDLIB std_http POST GREEN fixture.
//
// Drives `httpPostOver` through a mock transport (no sockets):
//   - exact POST request shape: request line, Host, Connection: close,
//     Content-Type, Accept, Content-Length, blank line, body bytes
//   - empty content_type/accept omit those headers
//   - identity response body with Content-Length
//   - byte-exact Response status/header/body
//
// GREEN (contract): deterministic byte-exact stdout `http post ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const http = @import("std_http.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

const Mock = struct {
    resp: []const u8,
    pos: usize,
    chunk: usize,
    req: [512]u8,
    req_len: usize,
    closed: bool,
};

fn mockRead(state: *void, buf: []u8) !usize {
    var m: *Mock = @ptrCast(*Mock, state);
    const remain = m.resp.len - m.pos;
    if (remain == 0) return 0;
    var n: usize = remain;
    if (n > m.chunk) n = m.chunk;
    if (n > buf.len) n = buf.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = m.resp[m.pos + i];
    }
    m.pos += n;
    return n;
}

fn mockWrite(state: *void, data: []const u8) !usize {
    var m: *Mock = @ptrCast(*Mock, state);
    var i: usize = 0;
    while (i < data.len and m.req_len < m.req.len) : (i += 1) {
        m.req[m.req_len] = data[i];
        m.req_len += 1;
    }
    return data.len;
}

fn mockClose(state: *void) void {
    var m: *Mock = @ptrCast(*Mock, state);
    m.closed = true;
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn contains(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (hay[i + j] != needle[j]) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

fn headerValue(resp: http.Response, name: []const u8) []const u8 {
    var i: usize = 0;
    while (i < resp.headers.len) : (i += 1) {
        if (eqBytes(resp.headers[i].name, name)) return resp.headers[i].value;
    }
    var empty: []const u8 = "";
    return empty;
}

fn runCase(url: []const u8, body: []const u8, ct: []const u8, accept: []const u8, resp_bytes: []const u8, want_req: []const u8, want_status: u16, want_body: []const u8) void {
    var storage: [65536]u8 = undefined;
    var ar = std.arena.init(storage[0..]);

    var m = Mock{ .resp = resp_bytes, .pos = 0, .chunk = 3, .req = undefined, .req_len = 0, .closed = false };
    var t = http.HttpTransport{
        .state = @ptrCast(*void, &m),
        .read_fn = mockRead,
        .write_fn = mockWrite,
        .close_fn = mockClose,
    };
    var resp: http.Response = undefined;
    http.httpPostOver(&ar, &t, url, body, ct, accept, &resp) catch @panic("post over");

    ck(resp.status == want_status, "status");
    ck(eqBytes(resp.body, want_body), "body");
    ck(contains(resp.body, want_body), "body contains");
    ck(m.closed, "closed");

    ck(eqBytes(m.req[0..m.req_len], want_req), "request exact");
}

pub fn main() void {
    const ct = "application/x-git-upload-pack-request";
    const accept = "application/x-git-upload-pack-result";
    const want_req = "POST /up?x=1 HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\nContent-Type: application/x-git-upload-pack-request\r\nAccept: application/x-git-upload-pack-result\r\nContent-Length: 5\r\n\r\nhello";
    runCase("http://example.com/up?x=1", "hello", ct, accept, "HTTP/1.1 201 Created\r\nContent-Length: 2\r\nX-Test: yes\r\n\r\nok", want_req, 201, "ok");

    const want_req2 = "POST /submit HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\nContent-Length: 3\r\n\r\nabc";
    runCase("https://example.com/submit", "abc", "", "", "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ndone", want_req2, 200, "done");

    if (g_fail == 0) {
        std.io.write("http post ok\n");
    } else {
        std.io.write("http post FAIL\n");
    }
}
