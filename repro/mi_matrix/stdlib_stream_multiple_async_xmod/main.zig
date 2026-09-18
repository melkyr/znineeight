// stdlib_stream_multiple_async_xmod — Plan B hardening final review (finding A):
// async coverage for the exact-multiple long line (L6 readLineAsync).
//
// stdlib_stream_multiple_xmod pins readLineSync on a 4-byte buffer over
// "abcd\nz\n"; this sibling drives the SAME FileLineReader shape through
// readLineAsync so the `overflow_cont` / resolveOverflow wiring in awaitLine
// (sf/src/std_stream.zig) is exercised. Without this fixture a refactor could
// drop that async resolveOverflow call and no gate would fail.
//
// "abcd\n" is an exact multiple of the 4-byte reader buffer: the overflow call
// returns "abcd" and sets overflow_cont; the NEXT readLineAsync resolves the
// still-unread '\n' as that line's terminator and returns "z" (never a spurious
// empty line), then null at EOF.
//
// GREEN: exactly ["abcd", "z"], then EOF; stdout `stream multiple async ok\n`,
// rc=0.
const f = @import("std_file.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const sa = @import("std_async.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

// `ticks` is the driver's completed-tick counter; it is carried so the async
// run is driven by the landed scheduler exactly like stdlib_stream_readline_xmod.
const CoCtx = struct {
    lr: *st.FileLineReader,
    lines: u32,
    err: bool,
    bad: bool,
    ticks: *u32,
};
const CArgs = struct { c: *CoCtx };

fn co(c: *CoCtx) void {
    const first = st.readLineAsync(c.lr) catch {
        c.err = true;
        return;
    };
    if (first) |line| {
        if (line.len == 4 and line[0] == 'a' and line[1] == 'b' and line[2] == 'c' and line[3] == 'd') {
            c.lines += 1;
        } else {
            c.bad = true;
        }
    } else {
        c.bad = true;
        return;
    }

    const second = st.readLineAsync(c.lr) catch {
        c.err = true;
        return;
    };
    if (second) |line| {
        if (line.len == 1 and line[0] == 'z') {
            c.lines += 1;
        } else {
            c.bad = true;
        }
    } else {
        c.bad = true;
        return;
    }

    const third = st.readLineAsync(c.lr) catch {
        c.err = true;
        return;
    };
    if (third) |_| c.bad = true;
}

pub fn main() void {
    // "abcd\n" is an exact multiple of the 4-byte reader buffer; "z\n" then fits.
    f.writeAll("t_stream_multiple_async.txt", "abcd\nz\n") catch @panic("setup");
    var file = f.open(&g_arena, "t_stream_multiple_async.txt", f.Mode.Read) catch @panic("open");
    var rbuf: [4]u8 = undefined;
    var lr = st.initFileLineReader(&file, rbuf[0..]);
    var ticks: u32 = 0;
    var cc = CoCtx{ .lr = &lr, .lines = 0, .err = false, .bad = false, .ticks = &ticks };
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
    if (cc.bad) @panic("async exact-multiple line mismatch");
    if (cc.lines != 2) @panic("line count");

    f.close(&file);
    f.remove("t_stream_multiple_async.txt") catch {};
    io.write("stream multiple async ok\n");
}
