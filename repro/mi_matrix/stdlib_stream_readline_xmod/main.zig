// stdlib_stream_readline_xmod — Plan B Task 4 (L6) readLineAsync on a small
// file, Model C cooperative-yield.
//
// Contract (operator ruling m1449/m1451, sf/docs/answerT4.txt): the caller
// drives the landed std.async scheduler with tick(); readLineAsync is a
// separate chunked implementation that yields with @asyncSuspend once per
// incomplete read. The reader owns a caller buffer (16 bytes here); the async
// chunk is buf.len/4 = 4, so each 10-char line spans several reads and each
// readLineAsync call suspends >= 2 times.
//
// `@asyncInit`'s 4th argument is the pointer to the argument slot it loads
// (corpus ABI: see stdlib_async_blocking_tick_xmod), so `CArgs.c` is the
// coroutine parameter and `co` takes that pointer directly.
//
// GREEN: three lines in order, then the observed suspension count (>= 2),
// RUNRC=0.
const f = @import("std_file.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const sa = @import("std_async.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

// `ticks` is the driver's completed-tick counter; a readLineAsync call that
// suspends k times advances it by exactly k, so the per-call delta IS the
// per-call suspension count. `max_suspends` is the §6 async-gate quantity.
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
            io.write(line);
            io.writeByte('\n');
            c.lines += 1;
        } else {
            return;
        }
    }
}

pub fn main() void {
    f.writeAll("t_stream_a.txt", "aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\n") catch @panic("setup");
    var file = f.open(&g_arena, "t_stream_a.txt", f.Mode.Read) catch @panic("open");
    var rbuf: [16]u8 = undefined;
    var lr = st.initFileLineReader(&file, rbuf[0..]);
    var ticks: u32 = 0;
    var cc = CoCtx{ .lr = &lr, .lines = 0, .err = false, .ticks = &ticks, .max_suspends = 0 };
    var ca = CArgs{ .c = &cc };

    var storage: [4096]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..4096 * 8]);
    var frame_store: [1024]u8 = undefined;
    var task: sa.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), &frame_store, co, @ptrCast(*const void, &ca));
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
    if (cc.lines != 3) @panic("line count");
    if (cc.max_suspends < 2) @panic("async gate: a readLineAsync call suspended fewer than 2 times");

    f.close(&file);
    f.remove("t_stream_a.txt") catch {};
    io.write("max-suspends ");
    io.printInt(@intCast(i32, cc.max_suspends));
    io.writeByte('\n');
}
