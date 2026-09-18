// stdlib_test/file_stream_usage — Plan B Task 5 (R7b) usage program.
//
// Composes std_file (L3) + std_stream (L6) + std.async into one intended
// workflow: std_file creates two small text files; std_stream.readLineSync
// drains the first (blocking, no async runtime); a std.async coroutine drains
// the second with std_stream.readLineAsync, yielding once per incomplete read
// (Model C cooperative-yield: main owns the scheduler and drives tick()).
//
// The reader buffer is 16 bytes, so the async chunk is buf.len/4 = 4: each
// 10-char line spans several reads and each readLineAsync call suspends >= 2
// times. `ticks` is the driver's completed-tick counter, so a call's tick delta
// IS its suspension count.
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0):
//   file_stream_usage
//   sync: [a]
//   sync: [b]
//   sync: []
//   sync: [c]
//   async: aaaaaaaaaa
//   async: bbbbbbbbbb
//   async: cccccccccc
//   async-lines: 3
//   max-suspends: 3
//   file_stream ok
// A mismatch calls @panic; the final line is `file_stream ok` only on success.
const f = @import("std_file.zig");
const st = @import("std_stream.zig");
const sa = @import("std_async.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn show(line: []const u8) void {
    io.write("sync: [");
    io.write(line);
    io.write("]\n");
}

const CoCtx = struct {
    lr: *st.FileLineReader,
    lines: u32,
    err: bool,
    ticks: *u32,
    max_suspends: u32,
};
const CArgs = struct { c: *CoCtx };

fn co(c: *CoCtx) void {
    while (true) {
        const before = c.ticks.*;
        const m = st.readLineAsync(c.lr) catch {
            c.err = true;
            return;
        };
        const n = c.ticks.* - before;
        if (n > c.max_suspends) c.max_suspends = n;
        if (m) |line| {
            io.write("async: ");
            io.write(line);
            io.writeByte('\n');
            c.lines += 1;
        } else {
            return;
        }
    }
}

pub fn main() void {
    f.writeAll("t_file_stream_usage_a.txt", "a\r\nb\n\nc") catch @panic("setup sync");
    f.writeAll("t_file_stream_usage_b.txt", "aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\n") catch @panic("setup async");

    io.write("file_stream_usage\n");

    // --- readLineSync: blocking, no async runtime ---------------------------
    var file = f.open(&g_arena, "t_file_stream_usage_a.txt", f.Mode.Read) catch @panic("open sync");
    var rbuf: [16]u8 = undefined;
    var lr = st.initFileLineReader(&file, rbuf[0..]);
    var sync_lines: u32 = 0;
    while (true) {
        const m = st.readLineSync(&lr) catch @panic("readLineSync");
        if (m) |line| {
            show(line);
            sync_lines += 1;
        } else {
            break;
        }
    }
    ck(sync_lines == 4, "sync line count");
    f.close(&file);

    // --- readLineAsync: cooperative coroutine, main drives tick -------------
    var afile = f.open(&g_arena, "t_file_stream_usage_b.txt", f.Mode.Read) catch @panic("open async");
    var abuf: [16]u8 = undefined;
    var alr = st.initFileLineReader(&afile, abuf[0..]);
    var ticks: u32 = 0;
    var cc = CoCtx{ .lr = &alr, .lines = 0, .err = false, .ticks = &ticks, .max_suspends = 0 };
    var ca = CArgs{ .c = &cc };

    var storage: [4096]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..4096 * 8]);
    // Frame buffer sized by the authoritative @asyncFrameSize (not a hardcoded
    // 1024): the size is a runtime int-literal in this compiler, so it backs an
    // arena allocation (same idiom as mud_server / client_task_arena_xmod).
    const frame_sz = @intCast(usize, @asyncFrameSize(co));
    const frame_store = arena_mod.alloc(&g_arena, frame_sz) catch @panic("frame alloc");
    var task: sa.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), @ptrCast([*]u8, frame_store), co, @ptrCast(*const void, &ca));
    task.ctx = ctx;
    task.arg = @ptrCast(*void, &ca);
    task.result = @ptrCast(*void, &ca);
    task.cancel_requested = false;
    task.waiting_on = &task;
    task.has_waiting_on = false;
    var pt: [1]*sa.Task = undefined;
    pt[0] = &task;
    var s = sa.schedulerInit(pt[0..]);
    _ = sa.addTask(&s, &task);

    while (task.state != sa.TaskState.done and task.state != sa.TaskState.cancelled) {
        sa.tick(&s) catch @panic("tick");
        ticks += 1;
    }
    if (cc.err) @panic("readLineAsync error");
    if (cc.lines != 3) @panic("async line count");
    if (cc.max_suspends < 2) @panic("async gate: a readLineAsync call suspended fewer than 2 times");

    f.close(&afile);
    f.remove("t_file_stream_usage_a.txt") catch {};
    f.remove("t_file_stream_usage_b.txt") catch {};

    io.write("async-lines: ");
    io.printInt(@intCast(i32, cc.lines));
    io.write("\n");
    io.write("max-suspends: ");
    io.printInt(@intCast(i32, cc.max_suspends));
    io.write("\n");
    io.write("file_stream ok\n");
}
