// mock_http.zig -- scripted smart-HTTP clone harness (Task 8).
//
// usage: mock_http <url> <dest> <max_down_bps> <info_refs_body> <upload_body> <reqlog>
//
// Injects a std_http.HttpTransport factory into httpgit.httpCloneOver: the
// first opened connection serves the supplied info/refs body, the second
// serves the supplied upload-pack body (NAK pkt-line followed by the raw PACK).
// The transport hands back at most 7 bytes per read so pkt-line/pack parsing
// crosses arbitrary read boundaries. Both request byte streams are written to
// <reqlog> separated by a fixed marker.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -o "$OUT" examples/z98/z9git/tests/mock_http.zig
//   sh "$OUT/build_target.sh" linux "$OUT/mock_http"

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const io = @import("std_io");
const os = @import("std_os");
const http = @import("std_http.zig");
const httpgit = @import("../httpgit.zig");

const ARENA_BYTES: usize = 32 * 1024 * 1024;
const REQ_BYTES: usize = 16384;
const MARKER: []const u8 = "\n---POST---\n";

var g_arena_buf: [ARENA_BYTES]u8 = undefined;
var g_open_count: usize = 0;
var g_info_resp: []const u8 = undefined;
var g_upload_resp: []const u8 = undefined;

const Mock = struct {
    resp: []const u8,
    pos: usize,
    req: [REQ_BYTES]u8,
    req_len: usize,
    closed: bool,
};

var g_mocks: [2]Mock = undefined;

fn strEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn parseU32(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > 4294967295) return null;
    }
    return @intCast(u32, v);
}

fn appendDec(out: []u8, pos: *usize, value: usize) void {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var v = value;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (v != 0) {
            tmp[n] = @intCast(u8, v % 10) + '0';
            n += 1;
            v = v / 10;
        }
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[pos.*] = tmp[n - 1 - i];
        pos.* += 1;
    }
}

fn buildResponse(arena: *arena_mod.Arena, body: []const u8, content_type: []const u8) ![]u8 {
    const total = body.len + content_type.len + 128;
    const raw = arena_mod.alloc(arena, total) catch return error.OutOfMemory;
    const out = raw[0..total];
    const prefix: []const u8 = "HTTP/1.1 200 OK\r\nContent-Type: ";
    const mid: []const u8 = "\r\nContent-Length: ";
    var pos: usize = 0;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        out[pos] = prefix[i];
        pos += 1;
    }
    i = 0;
    while (i < content_type.len) : (i += 1) {
        out[pos] = content_type[i];
        pos += 1;
    }
    i = 0;
    while (i < mid.len) : (i += 1) {
        out[pos] = mid[i];
        pos += 1;
    }
    appendDec(out, &pos, body.len);
    out[pos] = '\r';
    pos += 1;
    out[pos] = '\n';
    pos += 1;
    out[pos] = '\r';
    pos += 1;
    out[pos] = '\n';
    pos += 1;
    i = 0;
    while (i < body.len) : (i += 1) {
        out[pos] = body[i];
        pos += 1;
    }
    return out[0..pos];
}

fn mockRead(state: *void, buf: []u8) !usize {
    var m: *Mock = @ptrCast(*Mock, state);
    if (m.pos >= m.resp.len) return 0;
    if (buf.len == 0) return 0;
    var take: usize = m.resp.len - m.pos;
    if (take > 7) take = 7;
    if (take > buf.len) take = buf.len;
    var i: usize = 0;
    while (i < take) : (i += 1) buf[i] = m.resp[m.pos + i];
    m.pos += take;
    return take;
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

fn mockOpen(state: *void, url: []const u8) httpgit.OpenError!http.HttpTransport {
    _ = state;
    _ = url;
    const idx = g_open_count;
    g_open_count += 1;
    if (idx >= 2) return error.Transport;
    var m: *Mock = &g_mocks[idx];
    m.resp = if (idx == 0) g_info_resp else g_upload_resp;
    m.pos = 0;
    m.req_len = 0;
    m.closed = false;
    return http.HttpTransport{
        .state = @ptrCast(*void, m),
        .read_fn = mockRead,
        .write_fn = mockWrite,
        .close_fn = mockClose,
    };
}

fn fail(msg: []const u8) noreturn {
    io.write(msg);
    io.write("\n");
    os.exit(1);
}

fn readFileOr(arena: *arena_mod.Arena, path: []const u8, out: *[]u8) bool {
    const data = file_mod.readAll(arena, path) catch return false;
    out.* = data;
    return true;
}

fn allocOr(arena: *arena_mod.Arena, n: usize, out: *[]u8) bool {
    const data = arena_mod.alloc(arena, n) catch return false;
    out.* = data[0..n];
    return true;
}

fn buildResponseOr(arena: *arena_mod.Arena, body: []const u8, content_type: []const u8, out: *[]const u8) bool {
    const data = buildResponse(arena, body, content_type) catch return false;
    out.* = data;
    return true;
}

fn writeFileOr(path: []const u8, data: []const u8) bool {
    file_mod.writeAll(path, data) catch return false;
    return true;
}

pub fn main(arg_count: i32, arg_values: [*][*]u8) void {
    os.initArgs(arg_count, arg_values);
    const n = os.argc();
    if (n < 7) fail("usage: mock_http <url> <dest> <max_down_bps> <info_refs_body> <upload_body> <reqlog>");

    var arena = arena_mod.init(g_arena_buf[0..]);
    const url = os.argv(1);
    const dest = os.argv(2);
    var max_down: u32 = 0;
    if (parseU32(os.argv(3))) |v| {
        max_down = v;
    } else {
        fail("mock_http: bad max_down");
    }
    var info_body: []u8 = undefined;
    if (!readFileOr(&arena, os.argv(4), &info_body)) fail("mock_http: cannot read info/refs body");
    var upload_body: []u8 = undefined;
    if (!readFileOr(&arena, os.argv(5), &upload_body)) fail("mock_http: cannot read upload body");
    const reqlog = os.argv(6);

    if (!buildResponseOr(&arena, info_body, "application/x-git-upload-pack-advertisement", &g_info_resp)) {
        fail("mock_http: out of memory");
    }
    if (!buildResponseOr(&arena, upload_body, "application/x-git-upload-pack-result", &g_upload_resp)) {
        fail("mock_http: out of memory");
    }
    g_open_count = 0;

    var factory = httpgit.TransportFactory{
        .state = @ptrCast(*void, &g_open_count),
        .open_fn = mockOpen,
    };
    httpgit.httpCloneOver(&arena, url, dest, max_down, &factory) catch |e| {
        if (e == error.Transport) fail("mock_http: transport");
        if (e == error.Protocol) fail("mock_http: protocol");
        if (e == error.ObjectStore) fail("mock_http: object-store");
        if (e == error.Io) fail("mock_http: io");
        fail("mock_http: out of memory");
    };

    const get_len = g_mocks[0].req_len;
    const post_len = g_mocks[1].req_len;
    const total = get_len + MARKER.len + post_len;
    var raw: []u8 = undefined;
    if (!allocOr(&arena, total, &raw)) fail("mock_http: out of memory");
    var pos: usize = 0;
    var i: usize = 0;
    while (i < get_len) : (i += 1) {
        raw[pos] = g_mocks[0].req[i];
        pos += 1;
    }
    i = 0;
    while (i < MARKER.len) : (i += 1) {
        raw[pos] = MARKER[i];
        pos += 1;
    }
    i = 0;
    while (i < post_len) : (i += 1) {
        raw[pos] = g_mocks[1].req[i];
        pos += 1;
    }
    if (!writeFileOr(reqlog, raw[0..pos])) fail("mock_http: cannot write request log");
    io.write("mock http clone ok\n");
    os.exit(0);
}
