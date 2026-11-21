// client_task_wiring_xmod — Track-4 Task 4a-I pin of the `rogue_mud`
// client-frame task wiring defects (the multiplayer path is dead in-corpus
// because `examples/z98/rogue_mud/main.zig` sets `MULTIPLAYER_ENABLED = false`).
//
// This driver imports the REAL example module and drives the REAL
// `clientFrameCoroutine` / `drawToSocketCoroutine` through the REAL
// `std.async` scheduler. It reproduces the example's startup wiring: one
// client task per slot is added at startup (regardless of `active`), and one
// `tick` is issued per "local move" (the example's `broadcastDungeon`). The
// client sockets are real `socketpair(2)` ends so every `std_net.send()` is
// deterministically observable (the single-player path leaves `.socket`
// `undefined`; a valid fd is the deterministic substitute for "a task runs
// against a NON-ACTIVE client").
//
// DEFECT (1) — task runs against a non-active client. Slot 1 is INACTIVE but
// still has a task added at startup; the coroutine does not check `.active`,
// so it streams a full frame to the inactive socket.
// DEFECT (2) — one-frame lifecycle. Slot 0 is ACTIVE; `clientFrameCoroutine`
// returns after ONE pass of `drawToSocketCoroutine`, `tick` marks the task
// `done`, and it is never re-added, so after ~`rows` broadcasts the connected
// client receives nothing.
//
// RED (current, fixed point 5c24305437629da54b4e4de1ed52e0e0):
//   inactive_total > 0  (slot 1 received a full frame)
//   active_last   == 0  (slot 0 received nothing on the final broadcast)
//   active_state  == 3  (TaskState.done)
//   -> @panic("client_task_wiring_xmod: ...")
//
// GREEN contract (Task 4a-F): `clientFrameCoroutine` self-gates on
// `server.clients[client_idx].active` and stays alive across broadcasts:
//   inactive_total == 0
//   active_last    >  0
//   stdout:
//     active_total=<n> inactive_total=0 active_last=<m> inactive_last=0
//
// NOTE ON THE ROOT-FRAME ARENA. This driver deliberately uses a SEPARATE
// backing array for the client root frames (`root_storage`) instead of the
// example's `async_arena` over `async_storage[HEADER_SIZE..]`, which ALIASES
// the `async_ctx` pool base (`async_storage[16..]`) — see the Task-4a report
// finding (3). With the example's aliasing layout the first task's nested
// `drawToSocketCoroutine` child frame overwrites its own root frame and the
// task stalls after one row; that is a distinct defect and is NOT what this
// fixture pins. The arena is separated here so the RED is attributable to the
// two wiring defects alone.

const std = @import("std");
const std_debug = @import("std_debug");
const rm = @import("../../../examples/z98/rogue_mud/main.zig");
const net_mod = @import("../../../examples/z98/rogue_mud/lib/net.zig");
const scenario = @import("../../../examples/z98/rogue_mud/lib/scenario.zig");
const entity_mod = @import("../../../examples/z98/rogue_mud/lib/entity.zig");
const combat_mod = @import("../../../examples/z98/rogue_mud/lib/combat.zig");
const rng_mod = @import("../../../examples/z98/rogue_mud/lib/rng.zig");
const sand_mod = @import("../../../examples/z98/rogue_mud/lib/sand.zig");
const ui_mod = @import("../../../examples/z98/rogue_mud/ui.zig");

extern "c" fn socketpair(domain: i32, typ: i32, protocol: i32, sv: [*]i32) i32;
extern "c" fn fflush(f: *void) i32;

const BROADCASTS: usize = 80;

var buffer: [512 * 1024]u8 = undefined;
var async_storage: [32 * 1024]u64 = undefined;
var root_storage: [32 * 1024]u64 = undefined;

pub fn main() void {
    var arena = sand_mod.sand_init(buffer[0..], true);
    var rng = rng_mod.Random_init(@intCast(u32, 12345));
    var dungeon = scenario.generateDungeon(&arena, &rng, @intCast(u8, 60), @intCast(u8, 30)) catch return;
    var p_typ: entity_mod.EntityType = undefined;
    p_typ = .Player;
    combat_mod.addEntity(&dungeon, p_typ, @intCast(u8, 5), @intCast(u8, 5), @intCast(i16, 20));

    // Two real socket pairs: [0] = ACTIVE client, [1] = NON-ACTIVE client.
    var sv_active: [2]i32 = undefined;
    var sv_inactive: [2]i32 = undefined;
    if (socketpair(1, 1, 0, &sv_active[0]) != 0) @panic("client_task_wiring_xmod: socketpair active");
    if (socketpair(1, 1, 0, &sv_inactive[0]) != 0) @panic("client_task_wiring_xmod: socketpair inactive");

    var server: net_mod.Server = undefined;
    server.listen_socket = -1;
    var si: usize = 0;
    while (si < 5) : (si += 1) {
        server.clients[si].active = false;
        server.clients[si].socket = -1;
        server.clients[si].pos = 0;
    }
    server.clients[0].active = true;
    server.clients[0].socket = sv_active[0];
    server.clients[1].active = false;
    server.clients[1].socket = sv_inactive[0];

    // Separated root-frame arena (see the header note); the ctx pool is over
    // `async_storage` exactly as the example builds it.
    var root_arena = sand_mod.sand_init(@ptrCast([*]u8, &root_storage)[0 .. 32 * 1024 * 8], true);
    var async_ctx = std.async.contextInit(@ptrCast([*]u8, &async_storage)[0 .. 32 * 1024 * 8]);

    var tasks: [2]std.async.Task = undefined;
    var tptrs: [2]*std.async.Task = undefined;
    var args: [2]rm.ClientFrameArgs = undefined;
    var recs: [2]rm.ClientFrameCoroutineArgs = undefined;
    var cells: [2][4000]ui_mod.Cell = undefined;
    tptrs[0] = &tasks[0];
    tptrs[1] = &tasks[1];
    var sched = std.async.schedulerInit(tptrs[0..]);

    var i: usize = 0;
    while (i < 2) : (i += 1) {
        args[i] = rm.ClientFrameArgs{ .server = &server, .dungeon = &dungeon, .client_idx = i,
            .cells = @ptrCast([*]ui_mod.Cell, &cells[i][0]) };
        recs[i] = rm.ClientFrameCoroutineArgs{ .ctx = async_ctx, .cfa = &args[i] };
        const csz = @intCast(usize, @asyncFrameSize(rm.clientFrameCoroutine));
        const cframe = sand_mod.sand_alloc(&root_arena, csz, 8) catch return;
        tptrs[i].frame = @asyncInit(async_ctx, @ptrCast([*]u8, cframe), rm.clientFrameCoroutine, @ptrCast(*const void, &recs[i]));
        tptrs[i].ctx = async_ctx;
        tptrs[i].arg = @ptrCast(*void, &recs[i]);
        tptrs[i].result = @ptrCast(*void, &recs[i]);
        tptrs[i].cancel_requested = false;
        tptrs[i].waiting_on = tptrs[i];
        tptrs[i].has_waiting_on = false;
        _ = std.async.addTask(&sched, tptrs[i]);
    }

    var total_active: i64 = 0;
    var total_inactive: i64 = 0;
    var last_active: i64 = 0;
    var last_inactive: i64 = 0;
    var b: usize = 0;
    while (b < BROADCASTS) : (b += 1) {
        std.async.tick(&sched) catch {};
        last_active = drain(sv_active[1]);
        last_inactive = drain(sv_inactive[1]);
        total_active += last_active;
        total_inactive += last_inactive;
    }

    // @stdoutWrite-backed (unbuffered) so the evidence survives the RED trap.
    std_debug.logInt("active_total", @intCast(i32, total_active));
    std_debug.logInt("inactive_total", @intCast(i32, total_inactive));
    std_debug.logInt("active_last", @intCast(i32, last_active));
    std_debug.logInt("inactive_last", @intCast(i32, last_inactive));
    std_debug.logInt("active_state", @intCast(i32, @enumToInt(tptrs[0].state)));
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));

    if (total_inactive != 0) {
        @panic("client_task_wiring_xmod: a task wrote to a NON-ACTIVE client socket (defect 1)");
    }
    if (last_active <= 0) {
        @panic("client_task_wiring_xmod: active client stopped receiving frames (defect 2)");
    }
}

fn drain(fd: i32) i64 {
    var total: i64 = 0;
    var go: bool = true;
    while (go) {
        var fds: net_mod.fd_set = undefined;
        net_mod.fdZero(@ptrCast(*u8, &fds));
        net_mod.fdSet(fd, @ptrCast(*u8, &fds));
        const r = net_mod.select(fd + 1, @ptrCast(*u8, &fds), null, null, 0);
        if (r <= 0) {
            go = false;
        } else {
            var buf: [512]u8 = undefined;
            const n = net_mod.recv(fd, &buf[0], 512);
            if (n <= 0) { go = false; } else { total += n; }
        }
    }
    return total;
}
