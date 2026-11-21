// client_task_arena_xmod — Track-4 Task 4a-F pin of the `rogue_mud` client
// root-frame / async-ctx POOL ALIASING (Task-4a report finding (3)).
//
// The example builds `async_arena` over `async_storage[HEADER_SIZE..]` and
// `async_ctx = contextInit(async_storage[0..])`, so `pool_base ==
// async_storage[16]`. The first `sand_alloc(&async_arena, ...)` root frame and
// the first `contextAlloc(async_ctx, ...)` CHILD frame land at the SAME
// address. While `clientFrameCoroutine` calls the nested
// `drawToSocketCoroutine`, that child frame overwrites the root frame and the
// task stalls/dies.
//
// This driver imports the REAL example module and drives the REAL
// `clientFrameCoroutine` through the REAL `std.async` scheduler with the
// example's ALIASING layout (unlike `client_task_wiring_xmod`, which
// deliberately separates the two backings). It mirrors the example's startup
// wiring: slot 0 ACTIVE, slot 1 NON-ACTIVE, both backed by real `socketpair(2)`
// ends, one task per slot, one `tick` per broadcast. Task 4a-F removes the
// nested call (inlines the row loop), so no child frame is ever allocated and
// the aliasing is harmless.
//
// RED (current, fixed point 5c24305437629da54b4e4de1ed52e0e0):
//   active_total: 74  active_last: 0  active_state: 3  -> defect-3 panic
// GREEN contract (Task 4a-F):
//   active_total: 8080  inactive_total: 0  active_last: 142  inactive_last: 0
//   active_state: 2  run rc=0

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
// SAME backing for the root-frame arena and the ctx pool (the example's layout).
var async_storage: [32 * 1024]u64 = undefined;

pub fn main() void {
    var arena = sand_mod.sand_init(buffer[0..], true);
    var rng = rng_mod.Random_init(@intCast(u32, 12345));
    var dungeon = scenario.generateDungeon(&arena, &rng, @intCast(u8, 60), @intCast(u8, 30)) catch return;
    var p_typ: entity_mod.EntityType = undefined;
    p_typ = .Player;
    combat_mod.addEntity(&dungeon, p_typ, @intCast(u8, 5), @intCast(u8, 5), @intCast(i16, 20));

    var sv_active: [2]i32 = undefined;
    var sv_inactive: [2]i32 = undefined;
    if (socketpair(1, 1, 0, &sv_active[0]) != 0) @panic("client_task_arena_xmod: socketpair active");
    if (socketpair(1, 1, 0, &sv_inactive[0]) != 0) @panic("client_task_arena_xmod: socketpair inactive");

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

    // EXACT example layout: arena and ctx pool share `async_storage`.
    var async_arena = sand_mod.sand_init(@ptrCast([*]u8, &async_storage)[std.async.HEADER_SIZE .. 32 * 1024 * 8], true);
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
        const cframe = sand_mod.sand_alloc(&async_arena, csz, 8) catch return;
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

    std_debug.logInt("active_total", @intCast(i32, total_active));
    std_debug.logInt("inactive_total", @intCast(i32, total_inactive));
    std_debug.logInt("active_last", @intCast(i32, last_active));
    std_debug.logInt("inactive_last", @intCast(i32, last_inactive));
    std_debug.logInt("active_state", @intCast(i32, @enumToInt(tptrs[0].state)));
    _ = fflush(@ptrCast(*void, @intToPtr(*void, 0)));

    if (total_inactive != 0) {
        @panic("client_task_arena_xmod: a task wrote to a NON-ACTIVE client socket (defect 1)");
    }
    if (last_active <= 0) {
        @panic("client_task_arena_xmod: aliased root frame killed the client task (defect 3)");
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
