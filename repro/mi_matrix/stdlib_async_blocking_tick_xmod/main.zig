// stdlib_async_blocking_tick_xmod — the trailing `tick` blocks on a non-ready
// socket.
//
// `mud_server` (Task 5, E4) drives each ready socket with a direct
// `@asyncResume` and then calls `std.async.tick(&client_sched)` at the bottom
// of every select iteration. `tick` (`sf/src/std_async.zig:156-189`) resumes
// EVERY non-done task, not just the select-ready ones. Accepted sockets are
// blocking (never `O_NONBLOCK`), so when `tick` resumes a client task whose
// socket has no pending data its `recv` blocks and stalls `main`.
//
// This fixture is the minimal real-socket repro: one client connects and sends
// a single line, then stays idle. The drive mirrors `mud_server`'s
// (select -> direct `@asyncResume` -> trailing `tick`). On the trailing tick
// the task re-enters `recv` and blocks forever; `alarm(2)` bounds the stall.
//
// RED today (fixed point 18e0de5c): dump rc=0, 7 `.c`, gcc/link rc=0, run
// rc=142 (SIGALRM) with stdout `accepted` — the trailing `tick` blocked on the
// idle socket.
//
// GREEN contract (Task 5a-F: drop the trailing `tick`; resume only
// select-ready tasks — the readiness-gated drive): the bounded loop times out
// on `select` for the idle socket, prints `accepted` then `ok`, and exits rc=0.
// (The same fixture with the trailing `tick` removed was measured GREEN rc=0,
// stdout `accepted\nok`.)
const std = @import("std");
const std_net = @import("std_net");
const sa = @import("std_async.zig");

extern "stdcall" fn alarm(seconds: u32) u32;
extern "c" fn fflush(f: *void) i32;

const PORT: u16 = 4137;
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

pub fn main() !void {
    if (std_net.init() != 0) { std.io.print("init fail\n", .{}); return; }
    const server = std_net.createTcpServer(PORT);
    if (server < 0) { std.io.print("server fail\n", .{}); return; }
    if (std_net.bindListen(server, 5) < 0) { std.io.print("listen fail\n", .{}); return; }
    const client = std_net.createTcpClient(PORT);
    if (client < 0) { std.io.print("client fail\n", .{}); return; }
    const msg: []const u8 = "look\n";
    _ = std_net.send(client, msg.ptr, @intCast(i32, msg.len));

    var accepted: i32 = -1;
    var tries: usize = 0;
    while (accepted < 0 and tries < 1000) : (tries += 1) {
        accepted = std_net.accept(server);
    }
    if (accepted < 0) { std.io.print("accept fail\n", .{}); return; }
    std.io.print("accepted\n", .{});

    var storage: [32 * 1024]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..32 * 1024 * 8]);
    var c = Ctx{ .fd = accepted, .buf = undefined, .recvs = 0 };
    var rec = CArgs{ .cta = &c };
    var frame_store: [512]u8 = undefined;
    var task: sa.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), &frame_store, clientCoroutine, @ptrCast(*const void, &rec));
    task.ctx = ctx;
    task.arg = @ptrCast(*void, &rec);
    task.result = @ptrCast(*void, &rec);
    task.cancel_requested = false;
    task.waiting_on = &task;
    task.has_waiting_on = false;
    var pt: [1]*sa.Task = undefined;
    pt[0] = &task;
    var s = sa.schedulerInit(pt[0..]);
    _ = sa.addTask(&s, &task);

    var fds: std_net.fd_set = undefined;
    var iter: usize = 0;
    while (iter < 3) : (iter += 1) {
        std_net.fdZero(@ptrCast(*u8, &fds));
        std_net.fdSet(accepted, @ptrCast(*u8, &fds));
        const rc = std_net.select(accepted + 1, @ptrCast(*u8, &fds), null, null, 100);
        if (rc > 0 and std_net.fdIsset(accepted, @ptrCast(*u8, &fds))) {
            _ = @asyncResume(task.frame, null);
        }
        // The mud_server trailing tick: resumes the just-suspended idle task.
        alarm(2);
        sa.tick(&s) catch {};
        alarm(0);
    }
    std.io.print("ok\n", .{});
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));
}
