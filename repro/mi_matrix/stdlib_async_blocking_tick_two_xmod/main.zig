// stdlib_async_blocking_tick_two_xmod — readiness-gated two-client drive with
// a disconnect while a peer is idle.
//
// Same mechanism as `stdlib_async_blocking_tick_xmod`, but with two accepted
// clients. Client B connects first and stays idle (slot 0); client A connects
// second and then disconnects (slot 1). The pre-5a-F example resumed the ready
// fd A (whose coroutine returns on EOF) and then routed the null completion
// through `waitFor`/`tick`; `tick` resumes EVERY registered non-done task,
// reaching the idle slot 0 (B) and blocking `main` in `recv` — the exact
// multi-client hazard. Task 5a-F fix round 1 frees the completed slot directly
// (no `waitFor`/`tick`), so only select-ready fds are resumed.
//
// RED (pre-5a-F disconnect path, fixed point 18e0de5c): the drive calls
// `waitFor` on A's null return; `tick` resumes idle B and blocks; `alarm(2)`
// bounds the stall -> run rc=142 (SIGALRM) with stdout `accepted 2`.
//
// GREEN (5a-F readiness-gated drive, no waitFor/tick): the bounded select loop
// times out for the idle slot, prints `accepted 2` then `ok`, and exits rc=0.
// A is resumed exactly once (EOF), B is never resumed.
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

    // B connects first (idle); A connects second and then disconnects.
    const clientB = std_net.createTcpClient(PORT);
    const clientA = std_net.createTcpClient(PORT);
    if (clientB < 0 or clientA < 0) { std.io.print("client fail\n", .{}); return; }

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

    // A disconnects before the server resumes it: its `recv` will see EOF.
    std_net.close(clientA);

    var storage: [32 * 1024]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..32 * 1024 * 8]);
    // slot 0 = idle B, slot 1 = disconnecting A.
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

    var activeB: bool = true;
    var activeA: bool = true;
    var maxfd = accepted[0];
    if (accepted[1] > maxfd) { maxfd = accepted[1]; }
    var fds: std_net.fd_set = undefined;
    var iter: usize = 0;
    while (iter < 3) : (iter += 1) {
        std_net.fdZero(@ptrCast(*u8, &fds));
        if (activeB) { std_net.fdSet(accepted[0], @ptrCast(*u8, &fds)); }
        if (activeA) { std_net.fdSet(accepted[1], @ptrCast(*u8, &fds)); }
        const rc = std_net.select(maxfd + 1, @ptrCast(*u8, &fds), null, null, 100);
        if (rc > 0) {
            if (activeA and std_net.fdIsset(accepted[1], @ptrCast(*u8, &fds))) {
                const step = @asyncResume(tA.frame, null);
                if (step == null) {
                    // 5a-F fix round 1: the null return IS completion; free the
                    // slot directly (no waitFor/tick, which would resume idle B).
                    std_net.close(accepted[1]);
                    activeA = false;
                    tA.state = sa.TaskState.done;
                    sa.removeTask(&s, &tA);
                }
            }
            if (activeB and std_net.fdIsset(accepted[0], @ptrCast(*u8, &fds))) {
                _ = @asyncResume(tB.frame, null);
            }
        }
    }
    std.io.print("ok\n", .{});
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
    if (cA.recvs != 1 or cB.recvs != 0 or s.count != 1 or activeA) {
        @panic("stdlib_async_blocking_tick_two_xmod: disconnect-while-idle-peer drive broken");
    }
}
