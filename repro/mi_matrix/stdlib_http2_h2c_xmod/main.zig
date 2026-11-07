// stdlib_http2_h2c_xmod — local HTTP/2 cleartext (h2c) integration (Phase 3.3).
//
// Server-dependent fixture: takes `<url> [mode]`, connects to the ephemeral
// Node `http2.createServer` started by scripts/stdlib/run_http2.sh, opens an
// h2c prior-knowledge connection with `http2OpenTcp`, and drives it from a
// `std.async` scheduler while the main loop selects read AND write readiness
// with a bounded timeout and a per-stream stall watchdog.
//
// Modes:
//   mux      (default) two concurrent buffered GETs (/a and /b); prints both
//            statuses and bodies.
//   flow     one buffered GET /large (256 KiB); asserts the full body arrived.
//   echo     POST /echo; asserts the request body round-trips.
//   goaway   GET /goaway; asserts error.GoAway.
//   rst      GET /rst; asserts error.StreamReset.
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
const net = @import("std_net.zig");
const os = @import("std_os.zig");
const time = @import("std_time.zig");

const usage_line = "usage: stdlib_http2_h2c_xmod <url> [mode]\n";
const CONNECT_TIMEOUT_MS: u32 = 15000;
const STALL_MS: u32 = 15000;
const MAX_ITERS: usize = 200000;
const LARGE_LEN: usize = 256 * 1024;

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

var g_h2_arena_buf: [4 * 1024 * 1024]u8 = undefined;
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
    if (!eqBytes(scheme, "http")) return false;
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

fn errName2(e: h2.Http2Error) []const u8 {
    if (e == error.NotHttp2) return "not_http2";
    if (e == error.BadConfig) return "bad_config";
    if (e == error.TooLarge) return "too_large";
    if (e == error.Protocol) return "protocol";
    if (e == error.Corrupt) return "corrupt";
    if (e == error.Closed) return "closed";
    if (e == error.Io) return "io";
    if (e == error.OutOfMemory) return "oom";
    if (e == error.StreamClosed) return "stream_closed";
    if (e == error.StreamReset) return "stream_reset";
    if (e == error.GoAway) return "goaway";
    if (e == error.NoStream) return "no_stream";
    if (e == error.Busy) return "busy";
    return "other";
}

fn failExit(msg: []const u8) void {
    out(msg);
    out("\n");
    os.exit(1);
}

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
        const status = h2.http2Pump(g_conn) catch |e| {
            out("pump=");
            out(errName2(e));
            out("\n");
            return false;
        };
        std.async.tick(sched) catch {
            out("sched=oom\n");
            return false;
        };
        if (a.done and (!two or b.done)) return true;
        if (status == h2.PumpStatus.closed) {
            std.async.tick(sched) catch {
                out("sched=oom\n");
                return false;
            };
            return a.done and (!two or b.done);
        }
        const now = time.ticksMs();
        if (now - start > STALL_MS) {
            out("drive=timeout\n");
            return false;
        }
        if (!a.done and now - a.started_ms > STALL_MS) {
            out("drive=stall_a\n");
            return false;
        }
        if (two and !b.done and now - b.started_ms > STALL_MS) {
            out("drive=stall_b\n");
            return false;
        }
        waitSock(g_sock, h2.http2PendingOutput(g_conn) > 0);
    }
    out("drive=iters\n");
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
    g_req_a.out.body = g_body_echo[0..];
    g_req_a.started_ms = time.ticksMs();
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

fn setupTcp(host: []const u8, port: u16) bool {
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
    return true;
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
        !eqBytes(mode, "goaway") and !eqBytes(mode, "rst")) {
        out(usage_line);
        os.exit(2);
    }

    var host: []const u8 = "";
    var port: u16 = 0;
    if (!parseBase(url, &host, &port)) {
        out(usage_line);
        os.exit(2);
    }

    if (!setupTcp(host, port)) failExit("connect=failed");

    var ar = std.arena.init(g_h2_arena_buf[0..]);
    var cfg = h2.http2DefaultConfig();
    g_conn = h2.http2OpenTcp(&ar, g_sock, cfg) catch {
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

    h2.http2Close(g_conn);
    net.cleanup();
    os.exit(0);
}
