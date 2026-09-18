// stdlib_stream_readline_empty_xmod — Plan B Task 4 (L6) readLineAsync on an
// empty file.
//
// The empty read must return null immediately (no line, no suspension). The
// same coroutine then reads a small non-empty file so the fixture still
// exercises the §6 async gate (>= 2 cooperative suspensions); an empty file
// has nothing to read and therefore cannot suspend by itself.
//
// `@asyncInit`'s argument ABI is the corpus one: CArgs.c is the coroutine
// parameter (see stdlib_stream_readline_xmod).
//
// GREEN: `empty ok`, the non-empty file's two lines, then the suspension
// count (>= 2), RUNRC=0.
const f = @import("std_file.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const sa = @import("std_async.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

// Per-call gate: the driver's completed-tick delta around each readLineAsync
// call IS that call's suspension count; `max_suspends` is asserted >= 2. The
// empty-file call legitimately suspends 0 times (nothing to read); the
// non-empty call in the same coroutine supplies the gate evidence.
const CoCtx = struct {
    empty: *st.FileLineReader,
    nonempty: *st.FileLineReader,
    empty_ok: bool,
    lines: u32,
    err: bool,
    ticks: *u32,
    max_suspends: u32,
};
const CArgs = struct { c: *CoCtx };

fn co(c: *CoCtx) void {
    const e0 = c.ticks.*;
    const e = st.readLineAsync(c.empty) catch {
        c.err = true;
        return;
    };
    const n0 = c.ticks.* - e0;
    if (n0 > c.max_suspends) c.max_suspends = n0;
    if (e) |_| {
        c.err = true;
        return;
    }
    c.empty_ok = true;
    while (true) {
        const before = c.ticks.*;
        const m = st.readLineAsync(c.nonempty) catch {
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
    f.writeAll("t_stream_c.txt", "") catch @panic("setup empty");
    f.writeAll("t_stream_d.txt", "aaaaaaaaaa\nbbbbbbbbbb\n") catch @panic("setup nonempty");
    var empty = f.open(&g_arena, "t_stream_c.txt", f.Mode.Read) catch @panic("open empty");
    var nonempty = f.open(&g_arena, "t_stream_d.txt", f.Mode.Read) catch @panic("open nonempty");
    var ebuf: [16]u8 = undefined;
    var nbuf: [16]u8 = undefined;
    var elr = st.initFileLineReader(&empty, ebuf[0..]);
    var nlr = st.initFileLineReader(&nonempty, nbuf[0..]);
    var ticks: u32 = 0;
    var cc = CoCtx{ .empty = &elr, .nonempty = &nlr, .empty_ok = false, .lines = 0, .err = false, .ticks = &ticks, .max_suspends = 0 };
    var ca = CArgs{ .c = &cc };

    io.write("empty ok\n");

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
    if (!cc.empty_ok) @panic("empty file did not return null");
    if (cc.lines != 2) @panic("line count");
    if (cc.max_suspends < 2) @panic("async gate: a readLineAsync call suspended fewer than 2 times");

    f.close(&empty);
    f.close(&nonempty);
    f.remove("t_stream_c.txt") catch {};
    f.remove("t_stream_d.txt") catch {};
    io.write("max-suspends ");
    io.printInt(@intCast(i32, cc.max_suspends));
    io.writeByte('\n');
}
