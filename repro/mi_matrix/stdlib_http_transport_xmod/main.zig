// stdlib_http_transport_xmod — STDLIB std_http HttpTransport GREEN fixture.
//
// Drives `httpGetOver` through a mock transport (no sockets):
//   - identity body with Content-Length, request line + Host + Connection
//   - chunked body (RFC 7230 §4.1) incl. a chunk extension, force fragmented
//     reads (3-byte chunks) so the transport reader must buffer
//   - close-delimited identity body (no Content-Length)
//   - byte-exact Response status/header/body
//   - malformed chunk size -> error.BadResponse; close_fn called
//
// GREEN (contract): deterministic byte-exact stdout `http transport ok\n`
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
        if (resp.headers[i].name.len == name.len and contains(resp.headers[i].name, name)) {
            return resp.headers[i].value;
        }
    }
    var empty: []const u8 = "";
    return empty;
}

fn runCase(url: []const u8, resp_bytes: []const u8, chunk: usize, want_body: []const u8, what: []const u8, want_hdr: []const u8, want_hdr_val: []const u8) void {
    var storage: [65536]u8 = undefined;
    var ar = std.arena.init(storage[0..]);

    var m = Mock{ .resp = resp_bytes, .pos = 0, .chunk = chunk, .req = undefined, .req_len = 0, .closed = false };
    var t = http.HttpTransport{
        .state = @ptrCast(*void, &m),
        .read_fn = mockRead,
        .write_fn = mockWrite,
        .close_fn = mockClose,
    };
    var resp: http.Response = undefined;
    http.httpGetOver(&ar, &t, url, &resp) catch @panic(what);

    ck(resp.status == 200, what);
    ck(resp.body.len == want_body.len, what);
    var i: usize = 0;
    while (i < want_body.len) : (i += 1) {
        ck(resp.body[i] == want_body[i], what);
    }

    ck(m.req_len > 0, what);
    ck(contains(m.req[0..m.req_len], "GET /x?y=1 HTTP/1.1\r\n"), what);
    ck(contains(m.req[0..m.req_len], "Host: example.com\r\n"), what);
    ck(contains(m.req[0..m.req_len], "Connection: close\r\n\r\n"), what);
    ck(m.closed, what);

    if (want_hdr.len > 0) {
        const v = headerValue(resp, want_hdr);
        ck(v.len == want_hdr_val.len, what);
        var k: usize = 0;
        while (k < want_hdr_val.len) : (k += 1) {
            ck(v[k] == want_hdr_val[k], what);
        }
    }
}

pub fn main() void {
    runCase("https://example.com/x?y=1", "HTTP/1.1 200 OK\r\nContent-Length: 11\r\nX-Test: yes\r\n\r\nhello world", 3, "hello world", "identity fragmented", "X-Test", "yes");
    runCase("http://example.com/x?y=1", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n", 3, "hello world", "chunked fragmented", "", "");
    runCase("http://example.com/x?y=1", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5;foo=bar\r\nhello\r\n6\r\n world\r\n0\r\nX-Trailer: t\r\n\r\n", 64, "hello world", "chunked extension", "", "");
    runCase("http://example.com/x?y=1", "HTTP/1.1 200 OK\r\n\r\nclose body", 2, "close body", "close delimited", "", "");

    var storage: [65536]u8 = undefined;
    var ar = std.arena.init(storage[0..]);
    var m = Mock{ .resp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nZZ\r\nbad\r\n0\r\n\r\n", .pos = 0, .chunk = 5, .req = undefined, .req_len = 0, .closed = false };
    var t = http.HttpTransport{
        .state = @ptrCast(*void, &m),
        .read_fn = mockRead,
        .write_fn = mockWrite,
        .close_fn = mockClose,
    };
    var resp: http.Response = undefined;
    var saw: bool = false;
    http.httpGetOver(&ar, &t, "http://example.com/", &resp) catch |e| {
        ck(e == error.BadResponse, "bad chunk");
        saw = true;
    };
    ck(saw, "bad chunk");

    if (g_fail == 0) {
        std.io.write("http transport ok\n");
    } else {
        std.io.write("http transport FAIL\n");
    }
}
