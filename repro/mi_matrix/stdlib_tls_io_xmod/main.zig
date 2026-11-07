// stdlib_tls_io_xmod — STDLIB nonblocking TLS socket driver (Phase 3.3).
//
// Server-dependent fixture: takes `<host:port>` from argv, connects to a real
// Node TLS echo server started by scripts/stdlib/run_async_io.sh (committed
// localhost certificate), then drives the non-suspending TlsIo pumps from a
// `std.async` task while the main loop waits for socket readiness with select.
//
// Flow:
//   - tlsIoHandshakePump until established (WouldBlock suspends the task);
//   - tlsIoWritePump sends `ping`;
//   - tlsIoReadPump reads 4 bytes.
// Each WouldBlock is counted; the fixture prints `tlsio=<text>` and
// `wb>=1` only when the pumps actually yielded on socket readiness.
//
// The argless run prints one usage line to stdout and exits 2 (pinned golden).
//
// GREEN (contract): stdout `tlsio=ping` then `wb>=1`, exit 0.
const std = @import("std");
const tls = @import("std_tls.zig");
const tio = @import("std_tls_io.zig");
const net = @import("std_net.zig");
const os = @import("std_os.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");

const usage_line = "usage: stdlib_tls_io_xmod <host:port>\n";
const now_unix: i64 = 1893456000; // 2030-01-01, inside the committed cert window
const seed: u64 = 0x0123456789abcdef;
const CONNECT_TIMEOUT_MS: u32 = 15000;
const WANT: usize = 4;

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

const Run = struct {
    io: *tio.TlsIo,
    wb: usize,
    got: usize,
    done: bool,
    failed: bool,
    spins: u32,
    buf: [WANT]u8,
    drain: [1]u8,
};

var g_store_arena_buf: [32768]u8 = undefined;
var g_session: tls.TlsSession = undefined;
var g_io: tio.TlsIo = undefined;
var g_run: Run = undefined;

fn out(s: []const u8) void {
    std.io.write(s);
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

fn parseEndpoint(s: []const u8, host_out: *[]const u8, port_out: *u16) bool {
    var i: usize = s.len;
    while (i > 0) {
        i -= 1;
        if (s[i] == ':') {
            if (i == 0) return false;
            host_out.* = s[0..i];
            return parsePort(s[i + 1 ..], port_out);
        }
    }
    return false;
}

// Bounded readiness wait: writability while wire bytes are pending, otherwise
// readability (a socket is almost always writable, so selecting both busy-spins).
fn waitReady(io: *tio.TlsIo) void {
    var rf: net.fd_set = undefined;
    var wf: net.fd_set = undefined;
    net.fdZero(@ptrCast(*u8, &rf));
    net.fdZero(@ptrCast(*u8, &wf));
    if (io.out_off < io.out_len) {
        net.fdSet(io.sock, @ptrCast(*u8, &wf));
        _ = net.select(io.sock + 1, null, @ptrCast(*u8, &wf), null, 20);
    } else {
        net.fdSet(io.sock, @ptrCast(*u8, &rf));
        _ = net.select(io.sock + 1, @ptrCast(*u8, &rf), null, null, 20);
    }
}

// The coroutine parameter is copied positionally from this record by
// `@asyncInit` (the Track-3 ABI).
const Args = struct { run: *Run };

// Proves the driver closed the fd: a send on a closed descriptor must error.
fn sendProbeClosed(sock: net.Socket) bool {
    var s: net.Socket = sock;
    _ = net.sendNonBlocking(&s, "x") catch {
        return true;
    };
    return false;
}

fn worker(run: *Run) void {
    var established: bool = false;
    while (!established) {
        const est = tio.tlsIoHandshakePump(run.io) catch |e| {
            if (e == error.WouldBlock) {
                run.wb += 1;
                run.spins += 1;
                if (run.spins > 500) {
                    run.failed = true;
                    return;
                }
                waitReady(run.io);
                _ = @asyncSuspend(null);
                continue;
            }
            run.failed = true;
            return;
        };
        if (est) established = true;
    }

    const msg: []const u8 = "ping";
    var sent: usize = 0;
    while (sent < msg.len) {
        const n = tio.tlsIoWritePump(run.io, msg[sent..]) catch |e| {
            if (e == error.WouldBlock) {
                run.wb += 1;
                run.spins += 1;
                if (run.spins > 500) {
                    run.failed = true;
                    return;
                }
                waitReady(run.io);
                _ = @asyncSuspend(null);
                continue;
            }
            run.failed = true;
            return;
        };
        sent += n;
    }

    var total: usize = 0;
    while (total < WANT) {
        const n = tio.tlsIoReadPump(run.io, run.buf[total..WANT]) catch |e| {
            if (e == error.WouldBlock) {
                run.wb += 1;
                run.spins += 1;
                if (run.spins > 500) {
                    run.failed = true;
                    return;
                }
                waitReady(run.io);
                _ = @asyncSuspend(null);
                continue;
            }
            run.failed = true;
            return;
        };
        if (n == 0) break;
        total += n;
    }

    // Server closes after echoing: read through close_notify/FIN until 0.
    var eof: bool = false;
    while (!eof) {
        const n = tio.tlsIoReadPump(run.io, run.drain[0..]) catch |e| {
            if (e == error.WouldBlock) {
                run.wb += 1;
                run.spins += 1;
                if (run.spins > 500) {
                    run.failed = true;
                    return;
                }
                waitReady(run.io);
                _ = @asyncSuspend(null);
                continue;
            }
            run.failed = true;
            return;
        };
        if (n == 0) eof = true;
    }

    run.got = total;
    run.done = true;
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (os.argc() != 2) {
        out(usage_line);
        os.exit(2);
    }

    var host: []const u8 = "";
    var port: u16 = 0;
    if (!parseEndpoint(os.argv(1), &host, &port)) {
        out(usage_line);
        os.exit(2);
    }

    var arena = std.arena.init(g_store_arena_buf[0..]);
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&arena, store_bin[0..], &store) catch {
        out("tlsio=store-failed\n");
        os.exit(1);
    };

    var rng = rand.xoshiroInit(seed);
    var cfg = tls.TlsConfig{
        .hostname = host,
        .store = &store,
        .rng = &rng,
        .now_unix = now_unix,
        .min_version = tls.TLS_VERSION_13,
        .max_version = tls.TLS_VERSION_13,
        .alpn_h2 = false,
        .prefer_chacha20 = false,
    };
    tls.tlsInit(&g_session, &cfg);

    if (net.init() != 0) @panic("init");
    const ip = net.resolve(host) catch @panic("resolve");
    const sock = net.tcpSocket() catch @panic("tcpSocket");
    // connectToIp leaves the socket nonblocking (Plan C/D Model C contract).
    net.connectToIp(sock, ip, port, CONNECT_TIMEOUT_MS) catch @panic("connect");

    tio.tlsIoInit(&g_io, &g_session, sock);
    g_run = Run{
        .io = &g_io,
        .wb = 0,
        .got = 0,
        .done = false,
        .failed = false,
        .spins = 0,
        .buf = [WANT]u8{ 0, 0, 0, 0 },
        .drain = [1]u8{0},
    };
    var args = Args{ .run = &g_run };

    var pool: [128]u64 = undefined;
    var ctx = std.async.contextInit(@ptrCast([*]u8, &pool)[0..128 * 8]);
    var frame_store: [2048]u8 = undefined;
    var task: std.async.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), &frame_store, worker, @ptrCast(*const void, &args));
    task.ctx = ctx;
    task.arg = @ptrCast(*void, &args);
    task.result = @ptrCast(*void, &args);
    task.cancel_requested = false;
    task.waiting_on = &task;
    task.has_waiting_on = false;
    var pt: [1]*std.async.Task = undefined;
    pt[0] = &task;
    var sched = std.async.schedulerInit(pt[0..]);
    _ = std.async.addTask(&sched, &task);

    // The worker is a std.async task; each WouldBlock waits on socket
    // readiness (bounded) before yielding to the scheduler.
    std.async.waitAll(&sched) catch {
        g_run.failed = true;
    };

    tio.tlsIoClose(&g_io);
    const sock_closed = sendProbeClosed(g_io.sock);
    net.cleanup();

    if (g_run.failed or g_run.got != WANT) {
        out("tlsio=failed\n");
        os.exit(1);
    }
    out("tlsio=");
    out(g_run.buf[0..g_run.got]);
    out("\n");
    if (g_run.wb >= 1) {
        out("wb>=1\n");
    } else {
        out("wb=0\n");
    }
    if (sock_closed) {
        out("sock_closed=1\n");
    } else {
        out("sock_closed=0\n");
    }
    os.exit(0);
}
