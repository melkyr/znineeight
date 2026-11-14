// stdlib_http2_tls_xmod — local HTTP/2 over TLS integration (Phase 3.3).
//
// Server-dependent fixture: takes `<url> [mode]`, connects to the ephemeral
// Node `http2.createSecureServer` started by scripts/stdlib/run_http2.sh
// (committed localhost certificate), negotiates ALPN with
// `alpn_h2 = true, prefer_chacha20 = true`, asserts `tlsAlpnSelected == .h2`,
// opens `http2OpenTls`, and drives the connection from a `std.async`
// scheduler while the main loop selects read AND write readiness with a
// bounded timeout and a per-stream stall watchdog.
//
// Modes:
//   mux      (default) two concurrent buffered GETs (/a and /b); prints both
//            statuses and bodies.
//   flow     one buffered GET /large (256 KiB); asserts the full body arrived
//            (connection/stream WINDOW_UPDATE flow control).
//   echo     POST /echo; asserts the request body round-trips.
//   goaway   GET /goaway; asserts error.GoAway.
//   rst      GET /rst; asserts error.StreamReset.
//   alpn11   server selects http/1.1; asserts `http2OpenTls` returns
//            error.NotHttp2 (prints fallback=not_http2).
//
// Each buffered GET supplies a caller `out.body` capacity buffer and an
// `id_out`, calls the convenience function (which waits internally), reads
// headers/body, then calls `http2Release`.
//
// The argless run prints one usage line to stdout and exits 2 (pinned golden).
//
// GREEN (contract): deterministic stdout for each mode, exit 0.
const std = @import("std");
const h2 = @import("std_http2.zig");
const http = @import("std_http.zig");
const tls = @import("std_tls.zig");
const tio = @import("std_tls_io.zig");
const net = @import("std_net.zig");
const os = @import("std_os.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");
const time = @import("std_time.zig");

const usage_line = "usage: stdlib_http2_tls_xmod <url> [mode]\n";
const now_unix: i64 = 1893456000; // 2030-01-01, inside the committed cert window
const seed: u64 = 0x0123456789abcdef;
const CONNECT_TIMEOUT_MS: u32 = 15000;
const STALL_MS: u32 = 15000;
const MAX_ITERS: usize = 200000;
const LARGE_LEN: usize = 256 * 1024;

// Trust anchor: examples/z98/demo/tls_demo/tests/certs/store.bin (Z98 M4 Test
// Root), embedded so the fixture is independent of the run CWD.
const store_bin = [_]u8{
    0x5a, 0x39, 0x38, 0x43, 0x41, 0x31, 0x30, 0x30, 0x01, 0x00, 0x00, 0x00,
    0x5f, 0x01, 0x00, 0x00, 0x1d, 0x00, 0x26, 0x01, 0x17, 0x7f, 0xda, 0x6a,
    0x17, 0x85, 0x72, 0x90, 0x30, 0x1b, 0x31, 0x19, 0x30, 0x17, 0x06, 0x03,
    0x55, 0x04, 0x03, 0x0c, 0x10, 0x5a, 0x39, 0x38, 0x20, 0x4d, 0x34, 0x20,
    0x54, 0x65, 0x73, 0x74, 0x20, 0x52, 0x6f, 0x6f, 0x74, 0x30, 0x82, 0x01,
    0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01,
    0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01,
    0x0a, 0x02, 0x82, 0x01, 0x01, 0x00, 0xa5, 0xc8, 0x62, 0xce, 0x1c, 0x5b,
    0xc1, 0xcf, 0x9f, 0x11, 0x41, 0x87, 0xde, 0xc0, 0x0e, 0xe2, 0xef, 0xe5,
    0x2a, 0x99, 0xa1, 0xe6, 0x0b, 0xc5, 0x1b, 0x98, 0x6c, 0xf2, 0x28, 0x83,
    0xc7, 0x7d, 0xfe, 0x29, 0x15, 0xe0, 0xa9, 0xd1, 0x9c, 0x2a, 0xa0, 0xd8,
    0x5a, 0x67, 0xcb, 0xe6, 0x0f, 0x5a, 0xa4, 0x84, 0xca, 0x0b, 0x5d, 0x90,
    0xc1, 0xdf, 0x01, 0x71, 0xa6, 0x5a, 0x1e, 0x1c, 0x4a, 0x2d, 0x94, 0xbb,
    0x38, 0xc7, 0xf1, 0x64, 0x11, 0xb3, 0xec, 0xc1, 0x52, 0xa7, 0xc1, 0x87,
    0x0b, 0xc8, 0xd3, 0x4c, 0xd8, 0x7a, 0x47, 0x17, 0x11, 0x09, 0x7a, 0x45,
    0x44, 0x59, 0x0c, 0xc8, 0xad, 0xd5, 0x0d, 0xfb, 0x12, 0xc1, 0x4c, 0x27,
    0xf2, 0x00, 0xa6, 0xc9, 0x3b, 0x2b, 0x52, 0xe9, 0x05, 0x59, 0xfc, 0xc2,
    0xab, 0x62, 0x1f, 0x12, 0xd7, 0x02, 0xa9, 0x21, 0x06, 0x39, 0x1b, 0x59,
    0x7d, 0x5e, 0x02, 0x2e, 0x9f, 0x1e, 0x0f, 0x44, 0xec, 0x66, 0x6c, 0xce,
    0xba, 0x68, 0x4a, 0x39, 0x98, 0xe7, 0x2a, 0x63, 0x82, 0xfb, 0xe5, 0xf2,
    0x53, 0xae, 0x7f, 0x61, 0x0a, 0x19, 0xcf, 0xd7, 0xae, 0x7a, 0x11, 0xce,
    0xf8, 0x45, 0x06, 0x8c, 0x60, 0x5a, 0xcf, 0x2e, 0x74, 0x60, 0x08, 0x90,
    0x0f, 0x24, 0x4d, 0x59, 0xd8, 0x77, 0xcd, 0x2e, 0xcc, 0x64, 0x6c, 0x62,
    0xfa, 0x3a, 0x68, 0xcc, 0xcc, 0xf1, 0x82, 0xb2, 0xff, 0xd3, 0x65, 0x4d,
    0x1f, 0xce, 0x16, 0x4b, 0xf2, 0x88, 0x85, 0x57, 0x22, 0x4b, 0x0a, 0x0e,
    0x57, 0x2b, 0x21, 0x23, 0x0e, 0x6f, 0xdf, 0xb5, 0xba, 0xc5, 0x14, 0x96,
    0xde, 0x18, 0x4c, 0x1f, 0xd1, 0xe0, 0x7b, 0x3a, 0xcc, 0x11, 0x8e, 0x7c,
    0x33, 0xd2, 0xc1, 0x93, 0x26, 0x6b, 0x4f, 0xf1, 0x75, 0xe9, 0xc8, 0x3c,
    0xfc, 0x46, 0x72, 0xe6, 0xee, 0xb1, 0xbe, 0x07, 0x74, 0x05, 0x02, 0x03,
    0x01, 0x00, 0x01,
};

const ErrKind = enum(u8) { none = 0, goaway = 1, stream_reset = 2, not_http2 = 3, other = 4 };

const Req = struct {
    url: []const u8,
    out: http.Response,
    id: u32,
    body_buf: []u8,
    body_len: usize,
    status: u16,
    done: bool,
    failed: bool,
    err: ErrKind,
    started_ms: u32,
};

const Args = struct { req: *Req };

var g_store_arena_buf: [32768]u8 = undefined;
var g_store_arena: std.arena.Arena = undefined;
var g_store: x509.TrustStore = undefined;
var g_rng: rand.Xoshiro256 = undefined;
var g_h2_arena_buf: [4 * 1024 * 1024]u8 = undefined;
var g_session: tls.TlsSession = undefined;
var g_io: tio.TlsIo = undefined;
var g_conn: *h2.Http2Conn = undefined;
var g_sock: net.Socket = -1;

var g_req_a: Req = undefined;
var g_req_b: Req = undefined;
var g_body_a: [256]u8 = undefined;
var g_body_b: [256]u8 = undefined;
var g_body_echo: [256]u8 = undefined;
var g_body_large: [LARGE_LEN]u8 = undefined;
var g_url_a: [512]u8 = undefined;
var g_url_b: [512]u8 = undefined;
var g_empty_headers: [1]http.Header = undefined;
var g_empty_body: [1]u8 = undefined;

fn out(s: []const u8) void {
    std.io.write(s);
}

fn outNum(v: u32) void {
    std.io.printInt(@intCast(i32, v));
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn findFrom(hay: []const u8, needle: []const u8, from: usize) usize {
    if (needle.len == 0) return from;
    if (from > hay.len) return hay.len;
    var i: usize = from;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (hay[i + j] != needle[j]) break;
        }
        if (j == needle.len) return i;
    }
    return hay.len;
}

fn makeUrl(base: []const u8, suffix: []const u8, dst: []u8) []const u8 {
    if (base.len + suffix.len > dst.len) return dst[0..0];
    var i: usize = 0;
    while (i < base.len) : (i += 1) dst[i] = base[i];
    i = 0;
    while (i < suffix.len) : (i += 1) dst[base.len + i] = suffix[i];
    return dst[0 .. base.len + suffix.len];
}

fn parsePort(s: []const u8, out_port: *u16) bool {
    if (s.len == 0 or s.len > 5) return false;
    var v: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return false;
        v = v * 10 + @intCast(u32, s[i] - '0');
    }
    if (v == 0 or v > 65535) return false;
    out_port.* = @intCast(u16, v);
    return true;
}

fn parseBase(url: []const u8, host_out: *[]const u8, port_out: *u16) bool {
    const sep = findFrom(url, "://", 0);
    if (sep >= url.len) return false;
    const scheme = url[0..sep];
    if (!eqBytes(scheme, "https")) return false;
    const auth_start = sep + 3;
    var auth_end: usize = auth_start;
    while (auth_end < url.len and url[auth_end] != '/' and url[auth_end] != '?' and url[auth_end] != '#') : (auth_end += 1) {}
    if (auth_end == auth_start) return false;
    const authority = url[auth_start..auth_end];
    var i: usize = authority.len;
    while (i > 0) {
        i -= 1;
        if (authority[i] == ':') {
            if (i == 0) return false;
            host_out.* = authority[0..i];
            return parsePort(authority[i + 1 ..], port_out);
        }
    }
    return false;
}

fn classify(e: h2.Http2Error) ErrKind {
    if (e == error.GoAway) return ErrKind.goaway;
    if (e == error.StreamReset) return ErrKind.stream_reset;
    if (e == error.NotHttp2) return ErrKind.not_http2;
    return ErrKind.other;
}

fn failExit(msg: []const u8) void {
    out(msg);
    out("\n");
    os.exit(1);
}

// Bounded readiness wait. `want_write` is set whenever wire bytes are still
// pending so a read-only select cannot stall the preface/SETTINGS/DATA.
fn waitSock(fd: net.Socket, want_write: bool) void {
    var rf: net.fd_set = undefined;
    var wf: net.fd_set = undefined;
    net.fdZero(@ptrCast(*u8, &rf));
    net.fdZero(@ptrCast(*u8, &wf));
    net.fdSet(fd, @ptrCast(*u8, &rf));
    if (want_write) {
        net.fdSet(fd, @ptrCast(*u8, &wf));
        _ = net.select(fd + 1, @ptrCast(*u8, &rf), @ptrCast(*u8, &wf), null, 20);
    } else {
        _ = net.select(fd + 1, @ptrCast(*u8, &rf), null, null, 20);
    }
}

fn worker(r: *Req) void {
    r.started_ms = time.ticksMs();
    r.out.body = r.body_buf;
    h2.http2Get(g_conn, r.url, &r.out, &r.id) catch |e| {
        r.failed = true;
        r.err = classify(e);
        if (r.id != 0) {
            _ = h2.http2Release(g_conn, r.id) catch {};
        }
        r.done = true;
        return;
    };
    r.status = r.out.status;
    r.body_len = r.out.body.len;
    _ = h2.http2Release(g_conn, r.id) catch {};
    r.done = true;
}

fn driveLoop(sched: *std.async.Scheduler, a: *Req, b: *Req, two: bool) bool {
    const start = time.ticksMs();
    var it: usize = 0;
    while (it < MAX_ITERS) : (it += 1) {
        const status = h2.http2Pump(g_conn) catch {
            return false;
        };
        std.async.tick(sched) catch {
            return false;
        };
        if (a.done and (!two or b.done)) return true;
        if (status == h2.PumpStatus.closed) {
            std.async.tick(sched) catch {
                return false;
            };
            return a.done and (!two or b.done);
        }
        const now = time.ticksMs();
        if (now - start > STALL_MS) return false;
        if (!a.done and now - a.started_ms > STALL_MS) return false;
        if (two and !b.done and now - b.started_ms > STALL_MS) return false;
        waitSock(g_sock, h2.http2PendingOutput(g_conn) > 0);
    }
    return false;
}

fn driveTwo(a: *Req, b: *Req) bool {
    var pool1: [4096]u64 = undefined;
    var pool2: [4096]u64 = undefined;
    var ctx1 = std.async.contextInit(@ptrCast([*]u8, &pool1)[0..4096 * 8]);
    var ctx2 = std.async.contextInit(@ptrCast([*]u8, &pool2)[0..4096 * 8]);
    var f1: [8192]u8 = undefined;
    var f2: [8192]u8 = undefined;
    var args1 = Args{ .req = a };
    var args2 = Args{ .req = b };
    var t1: std.async.Task = undefined;
    var t2: std.async.Task = undefined;
    t1.frame = @asyncInit(@ptrCast(*void, ctx1), &f1, worker, @ptrCast(*const void, &args1));
    t1.ctx = ctx1;
    t1.arg = @ptrCast(*void, &args1);
    t1.result = @ptrCast(*void, &args1);
    t1.cancel_requested = false;
    t1.waiting_on = &t1;
    t1.has_waiting_on = false;
    t2.frame = @asyncInit(@ptrCast(*void, ctx2), &f2, worker, @ptrCast(*const void, &args2));
    t2.ctx = ctx2;
    t2.arg = @ptrCast(*void, &args2);
    t2.result = @ptrCast(*void, &args2);
    t2.cancel_requested = false;
    t2.waiting_on = &t2;
    t2.has_waiting_on = false;
    var pt: [2]*std.async.Task = undefined;
    pt[0] = &t1;
    pt[1] = &t2;
    var sched = std.async.schedulerInit(pt[0..]);
    _ = std.async.addTask(&sched, &t1);
    _ = std.async.addTask(&sched, &t2);
    return driveLoop(&sched, a, b, true);
}

fn driveOne(a: *Req) bool {
    var pool: [4096]u64 = undefined;
    var ctx = std.async.contextInit(@ptrCast([*]u8, &pool)[0..4096 * 8]);
    var f: [8192]u8 = undefined;
    var args = Args{ .req = a };
    var t: std.async.Task = undefined;
    t.frame = @asyncInit(@ptrCast(*void, ctx), &f, worker, @ptrCast(*const void, &args));
    t.ctx = ctx;
    t.arg = @ptrCast(*void, &args);
    t.result = @ptrCast(*void, &args);
    t.cancel_requested = false;
    t.waiting_on = &t;
    t.has_waiting_on = false;
    var pt: [1]*std.async.Task = undefined;
    pt[0] = &t;
    var sched = std.async.schedulerInit(pt[0..]);
    _ = std.async.addTask(&sched, &t);
    g_req_b.done = true;
    return driveLoop(&sched, a, &g_req_b, false);
}

fn resetReq(r: *Req, url: []const u8, body: []u8) void {
    r.url = url;
    r.out = http.Response{ .status = 0, .headers = g_empty_headers[0..0], .body = body };
    r.id = 0;
    r.body_buf = body;
    r.body_len = 0;
    r.status = 0;
    r.done = false;
    r.failed = false;
    r.err = ErrKind.none;
    r.started_ms = time.ticksMs();
}

fn runMux(base: []const u8) void {
    const ua = makeUrl(base, "/a", g_url_a[0..]);
    const ub = makeUrl(base, "/b", g_url_b[0..]);
    if (ua.len == 0 or ub.len == 0) failExit("mux=url_failed");
    resetReq(&g_req_a, ua, g_body_a[0..]);
    resetReq(&g_req_b, ub, g_body_b[0..]);
    if (!driveTwo(&g_req_a, &g_req_b)) failExit("mux=drive_failed");
    if (g_req_a.failed or g_req_b.failed) failExit("mux=request_failed");
    if (g_req_a.status != 200 or g_req_b.status != 200) failExit("mux=status");
    out("a=");
    outNum(@intCast(u32, g_req_a.status));
    out(":");
    out(g_req_a.out.body);
    out("\n");
    out("b=");
    outNum(@intCast(u32, g_req_b.status));
    out(":");
    out(g_req_b.out.body);
    out("\n");
}

fn runFlow(base: []const u8) void {
    const u = makeUrl(base, "/large", g_url_a[0..]);
    if (u.len == 0) failExit("flow=url_failed");
    resetReq(&g_req_a, u, g_body_large[0..]);
    if (!driveOne(&g_req_a)) failExit("flow=drive_failed");
    if (g_req_a.failed) failExit("flow=request_failed");
    if (g_req_a.status != 200) failExit("flow=status");
    if (g_req_a.out.body.len != LARGE_LEN) failExit("flow=short");
    var i: usize = 0;
    while (i < LARGE_LEN) : (i += 1) {
        if (g_req_a.out.body[i] != @intCast(u8, i & 0xFF)) failExit("flow=corrupt");
    }
    out("large=");
    outNum(@intCast(u32, g_req_a.out.body.len));
    out("\n");
}

const PostArgs = struct { req: *Req, url: []const u8, body: []const u8 };

fn postWorker(req: *Req, url: []const u8, body: []const u8) void {
    req.started_ms = time.ticksMs();
    req.out.body = req.body_buf;
    h2.http2Post(g_conn, url, body, "text/plain", "*/*", &req.out, &req.id) catch |e| {
        req.failed = true;
        req.err = classify(e);
        if (req.id != 0) {
            _ = h2.http2Release(g_conn, req.id) catch {};
        }
        req.done = true;
        return;
    };
    req.status = req.out.status;
    req.body_len = req.out.body.len;
    _ = h2.http2Release(g_conn, req.id) catch {};
    req.done = true;
}

fn runEcho(base: []const u8) void {
    const u = makeUrl(base, "/echo", g_url_a[0..]);
    if (u.len == 0) failExit("echo=url_failed");
    resetReq(&g_req_a, u, g_body_echo[0..]);
    // Set the caller buffer before submit; http2Post keeps caller storage.
    g_req_a.out.body = g_body_echo[0..];

    g_req_a.started_ms = time.ticksMs();
    // Run the POST in a coroutine so http2Wait suspends and the loop pumps.
    var pool: [4096]u64 = undefined;
    var ctx = std.async.contextInit(@ptrCast([*]u8, &pool)[0..4096 * 8]);
    var f: [8192]u8 = undefined;
    const body = "ping/echo/body";
    var args = PostArgs{ .req = &g_req_a, .url = u, .body = body };
    var t: std.async.Task = undefined;
    t.frame = @asyncInit(@ptrCast(*void, ctx), &f, postWorker, @ptrCast(*const void, &args));
    t.ctx = ctx;
    t.arg = @ptrCast(*void, &args);
    t.result = @ptrCast(*void, &args);
    t.cancel_requested = false;
    t.waiting_on = &t;
    t.has_waiting_on = false;
    var pt: [1]*std.async.Task = undefined;
    pt[0] = &t;
    var sched = std.async.schedulerInit(pt[0..]);
    _ = std.async.addTask(&sched, &t);
    g_req_b.done = true;
    if (!driveLoop(&sched, &g_req_a, &g_req_b, false)) failExit("echo=drive_failed");
    if (g_req_a.failed) failExit("echo=request_failed");
    if (g_req_a.status != 200) failExit("echo=status");
    if (!eqBytes(g_req_a.out.body, body)) failExit("echo=mismatch");
    out("echo=");
    out(g_req_a.out.body);
    out("\n");
}


fn errName(k: ErrKind) []const u8 {
    if (k == ErrKind.goaway) return "goaway";
    if (k == ErrKind.stream_reset) return "stream_reset";
    if (k == ErrKind.not_http2) return "not_http2";
    if (k == ErrKind.other) return "other";
    return "none";
}

fn runError(base: []const u8, suffix: []const u8, want: ErrKind, label: []const u8) void {
    const u = makeUrl(base, suffix, g_url_a[0..]);
    if (u.len == 0) failExit("error=url_failed");
    resetReq(&g_req_a, u, g_body_a[0..]);
    if (!driveOne(&g_req_a)) failExit("error=drive_failed");
    if (!g_req_a.failed) {
        out(label);
        out("=none\n");
        os.exit(1);
    }
    out(label);
    out("=");
    out(errName(g_req_a.err));
    out("\n");
    if (g_req_a.err != want) os.exit(1);
}

fn openTlsIsNotHttp2(ar: *std.arena.Arena, cfg: h2.Http2Config) bool {
    const opened = h2.http2OpenTls(ar, &g_io, cfg) catch |e| {
        if (e == error.NotHttp2) return true;
        return false;
    };
    h2.http2CloseForce(opened);
    return false;
}

fn setupTls(host: []const u8, port: u16) bool {
    g_store_arena = std.arena.init(g_store_arena_buf[0..]);
    x509.trustStoreLoad(&g_store_arena, store_bin[0..], &g_store) catch {
        return false;
    };
    g_rng = rand.xoshiroInit(seed);
    var cfg = tls.TlsConfig{
        .hostname = host,
        .store = &g_store,
        .rng = &g_rng,
        .now_unix = now_unix,
        .min_version = tls.TLS_VERSION_13,
        .max_version = tls.TLS_VERSION_13,
        .alpn_h2 = true,
        .prefer_chacha20 = true,
    };
    tls.tlsInit(&g_session, &cfg);

    if (net.init() != 0) return false;
    const ip = net.resolve(host) catch {
        return false;
    };
    const sock = net.tcpSocket() catch {
        return false;
    };
    net.connectToIp(sock, ip, port, CONNECT_TIMEOUT_MS) catch {
        net.close(sock);
        return false;
    };
    g_sock = sock;
    tio.tlsIoInit(&g_io, &g_session, sock);
    return true;
}

fn handshake() bool {
    var it: usize = 0;
    while (it < MAX_ITERS) : (it += 1) {
        const est = tio.tlsIoHandshakePump(&g_io) catch |e| {
            if (e == error.WouldBlock) {
                waitSock(g_sock, g_io.out_off < g_io.out_len);
                continue;
            }
            return false;
        };
        if (est) return true;
    }
    return false;
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (os.argc() != 2 and os.argc() != 3) {
        out(usage_line);
        os.exit(2);
    }

    const url = os.argv(1);
    var mode: []const u8 = "mux";
    if (os.argc() == 3) mode = os.argv(2);
    if (!eqBytes(mode, "mux") and !eqBytes(mode, "flow") and !eqBytes(mode, "echo") and
        !eqBytes(mode, "goaway") and !eqBytes(mode, "rst") and !eqBytes(mode, "alpn11")) {
        out(usage_line);
        os.exit(2);
    }

    var host: []const u8 = "";
    var port: u16 = 0;
    if (!parseBase(url, &host, &port)) {
        out(usage_line);
        os.exit(2);
    }

    if (!setupTls(host, port)) failExit("connect=failed");
    if (!handshake()) failExit("handshake=failed");

    const selected = tls.tlsAlpnSelected(&g_session);
    if (eqBytes(mode, "alpn11")) {
        if (selected == tls.AlpnProtocol.h2) failExit("fallback=h2");
        var ar = std.arena.init(g_h2_arena_buf[0..]);
        var cfg = h2.http2DefaultConfig();
        if (!openTlsIsNotHttp2(&ar, cfg)) failExit("fallback=unexpected");
        out("fallback=not_http2\n");
        os.exit(0);
    }

    if (selected != tls.AlpnProtocol.h2) failExit("alpn=not_h2");

    var ar = std.arena.init(g_h2_arena_buf[0..]);
    var cfg = h2.http2DefaultConfig();
    g_conn = h2.http2OpenTls(&ar, &g_io, cfg) catch {
        failExit("open=failed");
        return;
    };

    if (eqBytes(mode, "mux")) {
        runMux(url);
    } else if (eqBytes(mode, "flow")) {
        runFlow(url);
    } else if (eqBytes(mode, "echo")) {
        runEcho(url);
    } else if (eqBytes(mode, "goaway")) {
        runError(url, "/goaway", ErrKind.goaway, "goaway");
    } else if (eqBytes(mode, "rst")) {
        runError(url, "/rst", ErrKind.stream_reset, "rst");
    }

    h2.http2CloseForce(g_conn);
    net.cleanup();
    os.exit(0);
}
