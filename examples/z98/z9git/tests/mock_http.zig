// mock_http.zig -- scripted smart-HTTP clone harness (Task 8).
//
// usage: mock_http <url> <dest> <max_down_bps> <info_refs_body> <upload_body> <reqlog> [post_status] [chunked]
//
// Injects a std_http.HttpTransport factory into httpgit.httpCloneOver: the
// first opened connection serves the supplied info/refs body, the second
// serves the supplied upload-pack body (NAK pkt-line followed by the raw PACK).
// The transport hands back at most 7 bytes per read so pkt-line/pack parsing
// crosses arbitrary read boundaries. The optional post_status (default 200)
// scripts a non-200 upload-pack response for error-classification tests. Both
// request byte streams are written to <reqlog> separated by a fixed marker.
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
const MAX_CONNS: usize = 20;
const MARKER: []const u8 = "\n---POST---\n";

var g_arena_buf: [ARENA_BYTES]u8 = undefined;
var g_open_count: usize = 0;
var g_info_resp: []const u8 = undefined;
var g_upload_resp: [MAX_CONNS][]const u8 = undefined;
var g_upload_count: usize = 0;
var g_reuse_last: bool = false;


const Mock = struct {
    resp: []const u8,
    pos: usize,
    req: [REQ_BYTES]u8,
    req_len: usize,
    closed: bool,
};

var g_mocks: [MAX_CONNS]Mock = undefined;


fn endsWith(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        if (s[s.len - suffix.len + i] != suffix[i]) return false;
    }
    return true;
}

fn eqStr(a: []const u8, b: []const u8) bool {
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

fn buildResponse(arena: *arena_mod.Arena, status: u16, body: []const u8, content_type: []const u8) ![]u8 {
    const total = body.len + content_type.len + 128;
    const raw = arena_mod.alloc(arena, total) catch return error.OutOfMemory;
    const out = raw[0..total];
    const prefix: []const u8 = "HTTP/1.1 ";
    const mid1: []const u8 = " Status\r\nContent-Type: ";
    const mid2: []const u8 = "\r\nContent-Length: ";
    var pos: usize = 0;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        out[pos] = prefix[i];
        pos += 1;
    }
    appendDec(out, &pos, @intCast(usize, status));
    i = 0;
    while (i < mid1.len) : (i += 1) {
        out[pos] = mid1[i];
        pos += 1;
    }
    i = 0;
    while (i < content_type.len) : (i += 1) {
        out[pos] = content_type[i];
        pos += 1;
    }
    i = 0;
    while (i < mid2.len) : (i += 1) {
        out[pos] = mid2[i];
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

fn appendHex(out: []u8, pos: *usize, value: usize) void {
    var tmp: [16]u8 = undefined;
    var n: usize = 0;
    var v = value;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (v != 0) {
            const d: u8 = @intCast(u8, v % 16);
            tmp[n] = if (d < 10) '0' + d else 'a' + (d - 10);
            n += 1;
            v = v / 16;
        }
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[pos.*] = tmp[n - 1 - i];
        pos.* += 1;
    }
}

fn buildChunkedResponse(arena: *arena_mod.Arena, status: u16, body: []const u8, content_type: []const u8) ![]u8 {
    const chunk: usize = 4096;
    const chunks = (body.len + chunk - 1) / chunk;
    const total = body.len + chunks * 16 + content_type.len + 192;
    const raw = arena_mod.alloc(arena, total) catch return error.OutOfMemory;
    const out = raw[0..total];
    var pos: usize = 0;
    const prefix: []const u8 = "HTTP/1.1 ";
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        out[pos] = prefix[i];
        pos += 1;
    }
    appendDec(out, &pos, @intCast(usize, status));
    const mid1: []const u8 = " Status\r\nContent-Type: ";
    i = 0;
    while (i < mid1.len) : (i += 1) {
        out[pos] = mid1[i];
        pos += 1;
    }
    i = 0;
    while (i < content_type.len) : (i += 1) {
        out[pos] = content_type[i];
        pos += 1;
    }
    const hdr_end: []const u8 = "\r\nTransfer-Encoding: chunked\r\n\r\n";
    i = 0;
    while (i < hdr_end.len) : (i += 1) {
        out[pos] = hdr_end[i];
        pos += 1;
    }
    var off: usize = 0;
    while (off < body.len) {
        var n = body.len - off;
        if (n > chunk) n = chunk;
        appendHex(out, &pos, n);
        out[pos] = '\r';
        pos += 1;
        out[pos] = '\n';
        pos += 1;
        i = 0;
        while (i < n) : (i += 1) out[pos + i] = body[off + i];
        pos += n;
        out[pos] = '\r';
        pos += 1;
        out[pos] = '\n';
        pos += 1;
        off += n;
    }
    const trailer: []const u8 = "0\r\n\r\n";
    i = 0;
    while (i < trailer.len) : (i += 1) {
        out[pos] = trailer[i];
        pos += 1;
    }
    return out[0..pos];
}

fn buildChunkedResponseOr(arena: *arena_mod.Arena, status: u16, body: []const u8, content_type: []const u8, out: *[]const u8) bool {
    const r = buildChunkedResponse(arena, status, body, content_type) catch return false;
    out.* = r;
    return true;
}

// Declare more bytes than the mock actually serves: the client sees EOF in the
// middle of the pack, which is the mid-transfer abort the resume path handles.
fn buildAbortResponse(arena: *arena_mod.Arena, status: u16, body: []const u8, content_type: []const u8) ![]u8 {
    const total = body.len + content_type.len + 160;
    const raw = arena_mod.alloc(arena, total) catch return error.OutOfMemory;
    const out = raw[0..total];
    const prefix: []const u8 = "HTTP/1.1 ";
    const mid1: []const u8 = " Status\r\nContent-Type: ";
    const mid2: []const u8 = "\r\nContent-Length: ";
    var pos: usize = 0;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        out[pos] = prefix[i];
        pos += 1;
    }
    appendDec(out, &pos, @intCast(usize, status));
    i = 0;
    while (i < mid1.len) : (i += 1) {
        out[pos] = mid1[i];
        pos += 1;
    }
    i = 0;
    while (i < content_type.len) : (i += 1) {
        out[pos] = content_type[i];
        pos += 1;
    }
    i = 0;
    while (i < mid2.len) : (i += 1) {
        out[pos] = mid2[i];
        pos += 1;
    }
    appendDec(out, &pos, body.len + 4096);
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

fn buildAbortResponseOr(arena: *arena_mod.Arena, status: u16, body: []const u8, content_type: []const u8, out: *[]const u8) bool {
    const r = buildAbortResponse(arena, status, body, content_type) catch return false;
    out.* = r;
    return true;
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
    if (idx >= g_upload_count + 1) {
        if (!g_reuse_last or g_upload_count == 0) return error.Transport;
    }
    var m: *Mock = &g_mocks[idx];
    if (idx == 0) {
        m.resp = g_info_resp;
    } else if (idx <= g_upload_count) {
        m.resp = g_upload_resp[idx - 1];
    } else {
        m.resp = g_upload_resp[g_upload_count - 1];
    }
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

fn failCode(msg: []const u8, code: i32) noreturn {
    io.write(msg);
    io.write("\n");
    os.exit(code);
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

fn buildResponseOr(arena: *arena_mod.Arena, status: u16, body: []const u8, content_type: []const u8, out: *[]const u8) bool {
    const data = buildResponse(arena, status, body, content_type) catch return false;
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
    if (n < 7) fail("usage: mock_http <url> <dest> <max_down_bps> <info_refs_body> <upload_body> <reqlog> [post_status] [chunked]");

    var arena = arena_mod.init(g_arena_buf[0..]);
    const url = os.argv(1);
    const dest = os.argv(2);
    var max_down: u32 = 0;
    if (parseU32(os.argv(3))) |v| {
        max_down = v;
    } else {
        fail("mock_http: bad max_down");
    }
    var post_status: u16 = 200;
    if (n >= 8) {
        if (parseU32(os.argv(7))) |v| {
            if (v < 100 or v > 599) fail("mock_http: bad post_status");
            post_status = @intCast(u16, v);
        } else {
            fail("mock_http: bad post_status");
        }
    }
    var chunked = false;
    var clone_mode: u8 = 0;
    if (n >= 9) {
        if (eqStr(os.argv(8), "chunked")) {
            chunked = true;
        } else if (eqStr(os.argv(8), "identity")) {
            chunked = false;
        } else if (eqStr(os.argv(8), "partial")) {
            clone_mode = 1;
        } else if (eqStr(os.argv(8), "shallow")) {
            clone_mode = 2;
        } else if (eqStr(os.argv(8), "fetch1")) {
            clone_mode = 3;
        } else if (eqStr(os.argv(8), "fetch2")) {
            clone_mode = 4;

        } else {
            fail("mock_http: bad mode");
        }
    }
    var info_body: []u8 = undefined;
    if (!readFileOr(&arena, os.argv(4), &info_body)) fail("mock_http: cannot read info/refs body");
    const reqlog = os.argv(6);

    if (!buildResponseOr(&arena, 200, info_body, "application/x-git-upload-pack-advertisement", &g_info_resp)) {
        fail("mock_http: out of memory");
    }

    var upload_path = os.argv(5);
    var primary_abort = false;
    if (endsWith(upload_path, ":abort")) {
        upload_path = upload_path[0 .. upload_path.len - 6];
        primary_abort = true;
    }
    var upload_body: []u8 = undefined;
    if (!readFileOr(&arena, upload_path, &upload_body)) fail("mock_http: cannot read upload body");
    if (primary_abort) {
        if (!buildAbortResponseOr(&arena, post_status, upload_body, "application/x-git-upload-pack-result", &g_upload_resp[0])) {
            fail("mock_http: out of memory");
        }
    } else if (chunked) {
        if (!buildChunkedResponseOr(&arena, post_status, upload_body, "application/x-git-upload-pack-result", &g_upload_resp[0])) {
            fail("mock_http: out of memory");
        }
    } else {
        if (!buildResponseOr(&arena, post_status, upload_body, "application/x-git-upload-pack-result", &g_upload_resp[0])) {
            fail("mock_http: out of memory");
        }
    }
    g_upload_count = 1;

    var ai: usize = 9;
    while (ai < n) : (ai += 1) {
        if (g_upload_count >= MAX_CONNS) fail("mock_http: too many upload responses");
        var p = os.argv(ai);
        var extra_abort = false;
        if (endsWith(p, ":abort")) {
            p = p[0 .. p.len - 6];
            extra_abort = true;
        }
        var extra_body: []u8 = undefined;
        if (!readFileOr(&arena, p, &extra_body)) fail("mock_http: cannot read extra upload body");
        if (extra_abort) {
            if (!buildAbortResponseOr(&arena, post_status, extra_body, "application/x-git-upload-pack-result", &g_upload_resp[g_upload_count])) {
                fail("mock_http: out of memory");
            }
        } else {
            if (!buildResponseOr(&arena, post_status, extra_body, "application/x-git-upload-pack-result", &g_upload_resp[g_upload_count])) {
                fail("mock_http: out of memory");
            }
        }
        g_upload_count += 1;
    }
    g_open_count = 0;
    g_reuse_last = clone_mode == 1;


    var factory = httpgit.TransportFactory{
        .state = @ptrCast(*void, &g_open_count),
        .open_fn = mockOpen,
    };
    if (clone_mode == 0) {
        httpgit.httpCloneOver(&arena, url, dest, max_down, &factory) catch |e| {
            if (e == error.Transport) failCode("mock_http: transport", 2);
            if (e == error.Protocol) failCode("mock_http: protocol", 3);
            if (e == error.ObjectStore) failCode("mock_http: object-store", 4);
            if (e == error.DiskFull) failCode("mock_http: disk full", 5);
            if (e == error.Io) failCode("mock_http: io", 5);
            failCode("mock_http: out of memory", 5);
        };
    } else if (clone_mode == 1) {
        httpgit.httpCloneOverOpts(&arena, url, dest, max_down, 0, true, &factory) catch |e| {
            if (e == error.Transport) failCode("mock_http: transport", 2);
            if (e == error.Protocol) failCode("mock_http: protocol", 3);
            if (e == error.ObjectStore) failCode("mock_http: object-store", 4);
            if (e == error.DiskFull) failCode("mock_http: disk full", 5);
            if (e == error.Io) failCode("mock_http: io", 5);
            failCode("mock_http: out of memory", 5);
        };
    } else if (clone_mode == 2) {
        httpgit.httpCloneOverOpts(&arena, url, dest, max_down, 1, false, &factory) catch |e| {
            if (e == error.Transport) failCode("mock_http: transport", 2);
            if (e == error.Protocol) failCode("mock_http: protocol", 3);
            if (e == error.ObjectStore) failCode("mock_http: object-store", 4);
            if (e == error.DiskFull) failCode("mock_http: disk full", 5);
            if (e == error.Io) failCode("mock_http: io", 5);
            failCode("mock_http: out of memory", 5);
        };
    } else {
        const gd_raw = arena_mod.alloc(&arena, dest.len + 5) catch fail("mock_http: out of memory");
        var gd_i: usize = 0;
        while (gd_i < dest.len) : (gd_i += 1) gd_raw[gd_i] = dest[gd_i];
        const gd_suffix: []const u8 = "/.git";
        gd_i = 0;
        while (gd_i < gd_suffix.len) : (gd_i += 1) gd_raw[dest.len + gd_i] = gd_suffix[gd_i];
        const git_dir = gd_raw[0 .. dest.len + 5];
        const wire_deepen: u32 = if (clone_mode == 3) 1 else 2;
        httpgit.httpFetchOver(&arena, git_dir, wire_deepen, max_down, &factory) catch |e| {
            if (e == error.Usage) failCode("mock_http: usage", 1);
            if (e == error.Transport) failCode("mock_http: transport", 2);
            if (e == error.Protocol) failCode("mock_http: protocol", 3);
            if (e == error.ObjectStore) failCode("mock_http: object-store", 4);
            if (e == error.DiskFull) failCode("mock_http: disk full", 5);
            if (e == error.Io) failCode("mock_http: io", 5);
            failCode("mock_http: out of memory", 5);
        };
    }


    var total: usize = 0;
    var ci: usize = 0;
    while (ci < g_open_count) : (ci += 1) {
        total += g_mocks[ci].req_len + MARKER.len;
    }
    var raw: []u8 = undefined;
    if (!allocOr(&arena, total, &raw)) fail("mock_http: out of memory");
    var pos: usize = 0;
    ci = 0;
    while (ci < g_open_count) : (ci += 1) {
        var i: usize = 0;
        while (i < g_mocks[ci].req_len) : (i += 1) {
            raw[pos] = g_mocks[ci].req[i];
            pos += 1;
        }
        i = 0;
        while (i < MARKER.len) : (i += 1) {
            raw[pos] = MARKER[i];
            pos += 1;
        }
    }
    if (!writeFileOr(reqlog, raw[0..pos])) fail("mock_http: cannot write request log");
    io.write("mock http clone ok\n");
    os.exit(0);
}
