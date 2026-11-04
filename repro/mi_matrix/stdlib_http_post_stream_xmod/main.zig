// stdlib_http_post_stream_xmod — STDLIB std_http POST streaming GREEN fixture.
//
// Drives `httpPostStreamOver` through a mock transport (no sockets):
//   - chunked response fed ONE BYTE per read_fn call, so every chunk-size
//     line and every chunk-data/CRLF boundary lands across reads
//   - terminal 0\r\n\r\n chunk
//   - the de-chunked body reaches ResponseSink.write_fn byte-exactly
//   - out_head carries status/headers with an EMPTY body
//
// GREEN (contract): deterministic byte-exact stdout `http post stream ok\n`
// (RUNRC=0). A mismatch increments g_fail and calls @panic.
const std = @import("std");
const http = @import("std_http.zig");

var g_fail: u32 = 0;
var g_storage: [2097152]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

const Mock = struct {
    resp: []const u8,
    pos: usize,
    req: [512]u8,
    req_len: usize,
    reads: u32,
    closes: u32,
};

fn mockReadOne(state: *void, buf: []u8) !usize {
    var m: *Mock = @ptrCast(*Mock, state);
    m.reads += 1;
    if (m.pos >= m.resp.len) return 0;
    if (buf.len == 0) return 0;
    buf[0] = m.resp[m.pos];
    m.pos += 1;
    return 1;
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
    m.closes += 1;
}

const SinkState = struct {
    buf: [4096]u8,
    len: usize,
    calls: u32,
    head: *http.Response,
    first_status: u16,
    first_ct_len: usize,
};

fn sinkWrite(state: *void, data: []const u8) http.HttpError!void {
    var s: *SinkState = @ptrCast(*SinkState, state);
    if (s.calls == 0) {
        s.first_status = s.head.status;
        s.first_ct_len = headerValue(s.head.*, "Content-Type").len;
    }
    s.calls += 1;
    if (s.len + data.len > s.buf.len) return error.TooLarge;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        s.buf[s.len + i] = data[i];
    }
    s.len += data.len;
    return;
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

fn endsWith(hay: []const u8, needle: []const u8) bool {
    if (needle.len > hay.len) return false;
    const off: usize = hay.len - needle.len;
    var i: usize = 0;
    while (i < needle.len) : (i += 1) {
        if (hay[off + i] != needle[i]) return false;
    }
    return true;
}

fn headerValue(resp: http.Response, name: []const u8) []const u8 {
    var i: usize = 0;
    while (i < resp.headers.len) : (i += 1) {
        if (eqBytes(resp.headers[i].name, name)) return resp.headers[i].value;
    }
    var empty: []const u8 = "";
    return empty;
}

fn streamErrorClosesOnce(url: []const u8, ct: []const u8, accept: []const u8, want_bad_url: bool) void {
    var storage: [65536]u8 = undefined;
    var ar = std.arena.init(storage[0..]);

    var m = Mock{ .resp = "", .pos = 0, .req = undefined, .req_len = 0, .reads = 0, .closes = 0 };
    var t = http.HttpTransport{
        .state = @ptrCast(*void, &m),
        .read_fn = mockReadOne,
        .write_fn = mockWrite,
        .close_fn = mockClose,
    };
    var head: http.Response = undefined;
    var ss = SinkState{ .buf = undefined, .len = 0, .calls = 0, .head = &head, .first_status = 0, .first_ct_len = 0 };
    var sink = http.ResponseSink{
        .state = @ptrCast(*void, &ss),
        .write_fn = sinkWrite,
    };
    var saw: bool = false;
    http.httpPostStreamOver(&ar, &t, url, "x", ct, accept, &sink, &head) catch |e| {
        if (want_bad_url) {
            ck(e == error.BadUrl, "stream bad url");
        } else {
            ck(e == error.BadHeader, "stream bad header");
        }
        saw = true;
    };
    ck(saw, "stream error seen");
    ck(m.req_len == 0, "no write on stream error");
    ck(m.closes == 1, "stream close exactly once on error");
}

pub fn main() void {
    const resp_bytes = "HTTP/1.1 200 OK\r\nContent-Type: application/x-git-upload-pack-result\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\nX-Trailer: v\r\n\r\n";
    const want_body = "hello world";
    const want_req_body = "cmd=ls-refs";

    var ar = std.arena.init(g_storage[0..]);

    var m = Mock{ .resp = resp_bytes, .pos = 0, .req = undefined, .req_len = 0, .reads = 0, .closes = 0 };
    var t = http.HttpTransport{
        .state = @ptrCast(*void, &m),
        .read_fn = mockReadOne,
        .write_fn = mockWrite,
        .close_fn = mockClose,
    };
    var no_headers: [1]http.Header = undefined;
    var no_body: [1]u8 = undefined;
    var head = http.Response{ .status = 0, .headers = no_headers[0..0], .body = no_body[0..0] };
    var s = SinkState{ .buf = undefined, .len = 0, .calls = 0, .head = &head, .first_status = 0, .first_ct_len = 0 };
    var sink = http.ResponseSink{
        .state = @ptrCast(*void, &s),
        .write_fn = sinkWrite,
    };
    http.httpPostStreamOver(&ar, &t, "http://example.com/git-upload-pack", want_req_body, "application/x-git-upload-pack-request", "application/x-git-upload-pack-result", &sink, &head) catch @panic("post stream");

    ck(s.first_status == 200, "out_head ready at first sink call");
    ck(s.first_ct_len > 0, "out_head header at first sink call");
    ck(head.status == 200, "status");
    ck(head.body.len == 0, "head body empty");
    ck(m.closes == 1, "closed exactly once");

    ck(s.calls >= 1, "sink calls");
    ck(eqBytes(s.buf[0..s.len], want_body), "sink body exact");
    ck(!contains(s.buf[0..s.len], "X-Trailer"), "trailer skipped");
    ck(m.reads > 20, "one byte per read");

    ck(contains(m.req[0..m.req_len], "POST /git-upload-pack HTTP/1.1\r\n"), "request line");
    ck(contains(m.req[0..m.req_len], "Content-Type: application/x-git-upload-pack-request\r\n"), "content-type");
    ck(contains(m.req[0..m.req_len], "Accept: application/x-git-upload-pack-result\r\n"), "accept");
    ck(contains(m.req[0..m.req_len], "Content-Length: 11\r\n"), "content-length");
    ck(contains(m.req[0..m.req_len], "Connection: close\r\n"), "connection");
    ck(endsWith(m.req[0..m.req_len], want_req_body), "request body exact");
    ck(contains(m.req[0..m.req_len], "\r\n\r\ncmd=ls-refs"), "request body after blank line");

    const hct = headerValue(head, "Content-Type");
    ck(contains(hct, "application/x-git-upload-pack-result"), "head content-type");
    const hte = headerValue(head, "Transfer-Encoding");
    ck(contains(hte, "chunked"), "head transfer-encoding");

    streamErrorClosesOnce("ftp://example.com/x", "", "", true);
    streamErrorClosesOnce("http://example.com/x", "text/plain\r\nX: y", "", false);

    if (g_fail == 0) {
        std.io.write("http post stream ok\n");
    } else {
        std.io.write("http post stream FAIL\n");
    }
}
