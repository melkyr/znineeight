// stdlib_net_async_xmod — STDLIB std_net coroutine socket helpers (Phase 3.3).
//
// Server-dependent fixture: takes `<host:port>` from argv, connects to a real
// Node TCP echo server started by scripts/stdlib/run_async_io.sh, switches the
// socket non-blocking (connectToIp already does), sends `hello` through
// sendAllAsync, receives 5 bytes through recvSomeAsync, and prints
// `async=<text>`.
//
// The transfers run in a `std.async` coroutine. Both helpers suspend via
// `@asyncSuspend(null)` on `WouldBlock` and retry on the next scheduler tick,
// so the scheduler (not a blocking recv/send) drives the socket to completion.
//
// The argless run prints one usage line to stdout and exits 2 (pinned golden).
//
// GREEN (contract): stdout `async=hello` and exit 0.
const std = @import("std");
const net = @import("std_net.zig");
const os = @import("std_os.zig");

const usage_line = "usage: stdlib_net_async_xmod <host:port>\n";
const WANT: usize = 5;
const CONNECT_TIMEOUT_MS: u32 = 15000;

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

// The coroutine parameters are copied positionally from this record by
// `@asyncInit` (the Track-3 ABI).
const Args = struct { fd: i32, buf: *[WANT]u8, got: *usize };

fn worker(fd: i32, buf: *[WANT]u8, got: *usize) void {
    var s: net.Socket = fd;
    const hello: []const u8 = "hello";
    net.sendAllAsync(&s, hello) catch @panic("sendAllAsync");
    var total: usize = 0;
    while (total < WANT) {
        const n = net.recvSomeAsync(&s, buf[total..WANT]) catch @panic("recvSomeAsync");
        if (n == 0) break;
        total += n;
    }
    got.* = total;
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

    if (net.init() != 0) @panic("init");
    const ip = net.resolve(host) catch @panic("resolve");
    const sock = net.tcpSocket() catch @panic("tcpSocket");
    net.connectToIp(sock, ip, port, CONNECT_TIMEOUT_MS) catch @panic("connect");

    var recv_buf: [WANT]u8 = undefined;
    var got: usize = 0;
    var args = Args{ .fd = sock, .buf = &recv_buf, .got = &got };

    // [128]u64 == 1024 bytes of 8-aligned storage: the first 16 bytes are the
    // Context header, the rest is the child-frame pool for the suspending
    // sendAllAsync/recvSomeAsync calls.
    var pool: [128]u64 = undefined;
    var ctx = std.async.contextInit(@ptrCast([*]u8, &pool)[0..128 * 8]);
    var frame_store: [1024]u8 = undefined;
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
    std.async.waitAll(&sched) catch @panic("scheduler");

    net.close(sock);
    net.cleanup();

    if (got != WANT) {
        out("async=incomplete\n");
        os.exit(1);
    }
    out("async=");
    out(recv_buf[0..WANT]);
    out("\n");
    os.exit(0);
}
