// stdlib_async_blocking_tick_two_xmod — readiness-gated two-client drive.
//
// Same mechanism as `stdlib_async_blocking_tick_xmod`, but with two accepted
// clients. Client B connects first and stays idle (slot 0); client A connects
// second and sends one line (slot 1). The pre-5a-F drive direct-resumed the
// ready fd A (which consumed the line and suspended), then the trailing `tick`
// reached slot 0 (idle B) and blocked in `recv`. Because B never sends, `main`
// was stuck and A could never be serviced again — the exact multi-client
// hazard.
//
// RED (pre-5a-F drive, fixed point 18e0de5c): dump rc=0, 8 `.c`, gcc/link
// rc=0, run rc=142 (SIGALRM) with stdout `accepted 2`.
//
// GREEN (5a-F readiness-gated drive, no trailing `tick`): the bounded select
// loop times out for the idle slot, prints `accepted 2` then `ok`, and exits
// rc=0.
const std = @import("std");
const std_net = @import("std_net");
const sa = @import("std_async.zig");

extern "c" fn fflush(f: *void) i32;

const PORT: u16 = 4138;
const BUFFER_SIZE: usize = 64;

const Ctx = struct { fd: i32, buf: [BUFFER_SIZE]u8, recvs: u32 };
const CArgs = struct { cta: *Ctx };

fn clientCoroutine(cta: *Ctx) void {
    while (true) {
        const n = std_net.recv(cta.fd, &cta.buf[0], @intCast(i32, BUFFER_SIZE));
        cta.recvs += 1;
        if (n <= 0) return;
        _ = @asyncSuspend(null);
    }
}

fn setup(ctx: *sa.Context, c: *Ctx, rec: *CArgs, frame: []u8, task: *sa.Task) void {
    task.frame = @asyncInit(@ptrCast(*void, ctx), frame.ptr, clientCoroutine, @ptrCast(*const void, rec));
    task.ctx = ctx;
    task.arg = @ptrCast(*void, rec);
    task.result = @ptrCast(*void, rec);
    task.cancel_requested = false;
    task.waiting_on = task;
    task.has_waiting_on = false;
}

pub fn main() !void {
    if (std_net.init() != 0) { std.io.print("init fail\n", .{}); return; }
    const server = std_net.createTcpServer(PORT);
    if (server < 0) { std.io.print("server fail\n", .{}); return; }
    if (std_net.bindListen(server, 5) < 0) { std.io.print("listen fail\n", .{}); return; }

    // B connects first (idle); A connects second and sends one line.
    const clientB = std_net.createTcpClient(PORT);
    const clientA = std_net.createTcpClient(PORT);
    if (clientB < 0 or clientA < 0) { std.io.print("client fail\n", .{}); return; }
    const msg: []const u8 = "look\n";
    _ = std_net.send(clientA, msg.ptr, @intCast(i32, msg.len));

    var accepted: [2]i32 = undefined;
    accepted[0] = -1;
    accepted[1] = -1;
    var got: usize = 0;
    var tries: usize = 0;
    while (got < 2 and tries < 2000) : (tries += 1) {
        const a = std_net.accept(server);
        if (a >= 0) { accepted[got] = a; got += 1; }
    }
    if (got < 2) { std.io.print("accept fail\n", .{}); return; }
    std.io.print("accepted 2\n", .{});

    var storage: [32 * 1024]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..32 * 1024 * 8]);
    // slot 0 = idle B, slot 1 = active A.
    var cB = Ctx{ .fd = accepted[0], .buf = undefined, .recvs = 0 };
    var cA = Ctx{ .fd = accepted[1], .buf = undefined, .recvs = 0 };
    var recB = CArgs{ .cta = &cB };
    var recA = CArgs{ .cta = &cA };
    var fB: [512]u8 = undefined;
    var fA: [512]u8 = undefined;
    var tB: sa.Task = undefined;
    var tA: sa.Task = undefined;
    setup(ctx, &cB, &recB, fB[0..], &tB);
    setup(ctx, &cA, &recA, fA[0..], &tA);
    var pt: [2]*sa.Task = undefined;
    pt[0] = &tB;
    pt[1] = &tA;
    var s = sa.schedulerInit(pt[0..]);
    _ = sa.addTask(&s, &tB);
    _ = sa.addTask(&s, &tA);

    var fds: std_net.fd_set = undefined;
    var iter: usize = 0;
    while (iter < 3) : (iter += 1) {
        std_net.fdZero(@ptrCast(*u8, &fds));
        std_net.fdSet(accepted[0], @ptrCast(*u8, &fds));
        std_net.fdSet(accepted[1], @ptrCast(*u8, &fds));
        const rc = std_net.select(accepted[1] + 1, @ptrCast(*u8, &fds), null, null, 100);
        if (rc > 0) {
            if (std_net.fdIsset(accepted[1], @ptrCast(*u8, &fds))) {
                _ = @asyncResume(tA.frame, null);
            }
            if (std_net.fdIsset(accepted[0], @ptrCast(*u8, &fds))) {
                _ = @asyncResume(tB.frame, null);
            }
        }
        // Readiness-gated drive: no trailing `tick`; the idle slot is never
        // resumed, so `main` cannot stall in `recv`.
    }
    std.io.print("ok\n", .{});
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
}
