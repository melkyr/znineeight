// async_client_cells_xmod — S11: per-writer cells buffers.
//
// Two yielding "client frame" coroutines each build into their OWN cells
// buffer, then stream that buffer row-by-row with `@asyncSuspend` between rows
// into a captured output. Because each task has a private buffer, the
// scheduler interleaving the two tasks cannot make one task observe another's
// rows.
//
// If both tasks shared ONE cells buffer (the pre-S11 `local_cells` shape), the
// interleave is: A fills 'A' + streams row 0 + suspends; B fills 'B'
// (clobbering A's buffer) + streams row 0 + suspends; A resumes and streams
// rows 1..3 from the now-'B' buffer -> A's captured stream is "ABBB..." and the
// assertion fires. With per-task buffers A captures "AAAA..." and B "BBBB...".
//
// RED (shared buffer): run rc=133, stderr
//   panic: async_client_cells_xmod: A stream observed another writer's rows
// GREEN (per-task buffers): exact stdout
//   "AAAAAAAAAAAAAAAA\nBBBBBBBBBBBBBBBB\n" (RUNRC=0).
const std = @import("std");

fn fill(cells: [*]u8, ch: u8) void {
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        cells[i] = ch;
    }
}

fn writerA(out: [*]u8, cells: [*]u8) void {
    fill(cells, 'A');
    var y: usize = 0;
    while (y < 4) : (y += 1) {
        var x: usize = 0;
        while (x < 4) : (x += 1) {
            out[y * 4 + x] = cells[y * 4 + x];
        }
        _ = @asyncSuspend(null);
    }
}

fn writerB(out: [*]u8, cells: [*]u8) void {
    fill(cells, 'B');
    var y: usize = 0;
    while (y < 4) : (y += 1) {
        var x: usize = 0;
        while (x < 4) : (x += 1) {
            out[y * 4 + x] = cells[y * 4 + x];
        }
        _ = @asyncSuspend(null);
    }
}

const AArgs = struct { out: [*]u8, cells: [*]u8 };
const BArgs = struct { out: [*]u8, cells: [*]u8 };

pub fn main() void {
    // S11: a DISTINCT cells buffer per writer (never a shared one).
    var oa: [16]u8 = undefined;
    var ob: [16]u8 = undefined;
    var ca: [16]u8 = undefined;
    var cb: [16]u8 = undefined;
    var aa: AArgs = AArgs{ .out = @ptrCast([*]u8, &oa[0]), .cells = @ptrCast([*]u8, &ca[0]) };
    var ba: BArgs = BArgs{ .out = @ptrCast([*]u8, &ob[0]), .cells = @ptrCast([*]u8, &cb[0]) };

    // 8-aligned, permanent root-frame backing + per-task child pools.
    var aframe: [64]u64 = undefined;
    var bframe: [64]u64 = undefined;
    var apool: [32]u64 = undefined;
    var bpool: [32]u64 = undefined;
    var actx = std.async.contextInit(@ptrCast([*]u8, &apool)[0 .. 32 * 8]);
    var bctx = std.async.contextInit(@ptrCast([*]u8, &bpool)[0 .. 32 * 8]);

    var atask: std.async.Task = undefined;
    var btask: std.async.Task = undefined;
    var apt: [2]*std.async.Task = undefined;
    apt[0] = &atask;
    apt[1] = &btask;
    var sched = std.async.schedulerInit(apt[0..]);

    atask.frame = @asyncInit(actx, @ptrCast([*]u8, &aframe), writerA, @ptrCast(*const void, &aa));
    atask.ctx = actx;
    atask.arg = @ptrCast(*void, &aa);
    atask.result = @ptrCast(*void, &aa);
    atask.cancel_requested = false;
    atask.waiting_on = &atask;
    atask.has_waiting_on = false;
    _ = std.async.addTask(&sched, &atask);

    btask.frame = @asyncInit(bctx, @ptrCast([*]u8, &bframe), writerB, @ptrCast(*const void, &ba));
    btask.ctx = bctx;
    btask.arg = @ptrCast(*void, &ba);
    btask.result = @ptrCast(*void, &ba);
    btask.cancel_requested = false;
    btask.waiting_on = &btask;
    btask.has_waiting_on = false;
    _ = std.async.addTask(&sched, &btask);

    std.async.waitAll(&sched) catch {
        @panic("async_client_cells_xmod: scheduler error");
    };

    var i: usize = 0;
    while (i < 16) : (i += 1) {
        if (oa[i] != 'A') {
            @panic("async_client_cells_xmod: A stream observed another writer's rows");
        }
        if (ob[i] != 'B') {
            @panic("async_client_cells_xmod: B stream observed another writer's rows");
        }
    }

    i = 0;
    while (i < 16) : (i += 1) {
        std.io.writeByte(oa[i]);
    }
    std.io.writeByte('\n');
    i = 0;
    while (i < 16) : (i += 1) {
        std.io.writeByte(ob[i]);
    }
    std.io.writeByte('\n');
}
