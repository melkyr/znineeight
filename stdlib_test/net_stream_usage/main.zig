// stdlib_test/net_stream_usage — Plan D Task 5 (R7b) usage program.
//
// Composes std_net (L3: createTcpServer/createTcpClient/accept/setNonBlocking)
// + std_stream (L6: SocketLineReader + MsgReader) + std.async into one intended
// workflow: a loopback line stream is drained synchronously first, then a
// std.async coroutine drains lines with readSocketLineAsync and length-prefixed
// frames with readMsgAsync (Model C cooperative-yield: main owns the scheduler
// and drives tick(); each reader suspends on error.WouldBlock and is re-driven
// next tick).
//
// The readers use a 16-byte line buffer and an 8-byte frame buffer, so each
// partial wire chunk forces several suspensions per read call. `ticks` is the
// driver's completed-tick counter, so a call's tick delta IS its suspension
// count.
//
// GREEN (contract): deterministic byte-exact stdout (rc 0):
//   net_stream_usage
//   sync: [alpha]
//   sync: [beta]
//   async: [one]
//   async: [two]
//   frame: [hello]
//   frame: []
//   frame: [hi]
//   async-lines: 2
//   async-frames: 3
//   max-suspends: 3
//   net_stream ok
// A mismatch calls @panic; the final line is `net_stream ok` only on success.
const net = @import("std_net.zig");
const st = @import("std_stream.zig");
const sa = @import("std_async.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4154;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn accept1(server: i32) i32 {
    var conn: i32 = -1;
    var tries: usize = 0;
    while (conn < 0 and tries < 100000) : (tries += 1) {
        conn = net.accept(server);
    }
    return conn;
}

fn sendRaw(conn: i32, bytes: []const u8, what: []const u8) void {
    ck(net.send(conn, bytes.ptr, @intCast(i32, bytes.len)) == @intCast(i32, bytes.len), what);
}

// Encode a u32 big-endian length prefix into `pfx` (network byte order).
fn putPrefix(pfx: []u8, len: u32) void {
    pfx[0] = @intCast(u8, (len >> 24) & @intCast(u32, 255));
    pfx[1] = @intCast(u8, (len >> 16) & @intCast(u32, 255));
    pfx[2] = @intCast(u8, (len >> 8) & @intCast(u32, 255));
    pfx[3] = @intCast(u8, len & @intCast(u32, 255));
}

// (a) blocking half: pre-sent lines read with readSocketLineSync (no runtime).
fn runSync() void {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "sync server");
    ck(net.bindListen(server, 5) >= 0, "sync listen");
    const client = net.createTcpClient(PORT);
    ck(client >= 0, "sync client");
    const conn = accept1(server);
    ck(conn >= 0, "sync accept");

    const payload: []const u8 = "alpha\r\nbeta\n";
    sendRaw(conn, payload, "sync send");
    net.close(conn);

    var buf: [16]u8 = undefined;
    var lr = st.initSocketLineReader(&client, buf[0..]);
    var lines: u32 = 0;
    while (true) {
        const m = st.readSocketLineSync(&lr) catch @panic("readSocketLineSync");
        if (m) |line| {
            io.write("sync: [");
            io.write(line);
            io.write("]\n");
            lines += 1;
        } else {
            break;
        }
    }
    ck(lines == 2, "sync line count");

    net.close(client);
    net.close(server);
}

// (b) async lines: cooperative coroutine, main drives tick. `ticks` is the
// driver's completed-tick counter; a call's tick delta is its suspension count.
const CoLines = struct {
    lr: *st.SocketLineReader,
    lines: u32,
    err: bool,
    ticks: *u32,
    max_suspends: u32,
};
const LinesArgs = struct { c: *CoLines };

fn coLines(c: *CoLines) void {
    while (true) {
        const before = c.ticks.*;
        const m = st.readSocketLineAsync(c.lr) catch {
            c.err = true;
            return;
        };
        const n = c.ticks.* - before;
        if (n > c.max_suspends) c.max_suspends = n;
        if (m) |line| {
            io.write("async: [");
            io.write(line);
            io.write("]\n");
            c.lines += 1;
        } else {
            return;
        }
    }
}

fn runAsyncLines() u32 {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "async lines server");
    ck(net.bindListen(server, 5) >= 0, "async lines listen");
    var client = net.createTcpClient(PORT);
    ck(client >= 0, "async lines client");
    const conn = accept1(server);
    ck(conn >= 0, "async lines accept");
    net.setNonBlocking(&client) catch @panic("setNonBlocking");

    var buf: [16]u8 = undefined;
    var lr = st.initSocketLineReader(&client, buf[0..]);
    var ticks: u32 = 0;
    var cc = CoLines{ .lr = &lr, .lines = 0, .err = false, .ticks = &ticks, .max_suspends = 0 };
    var ca = LinesArgs{ .c = &cc };

    var storage: [4096]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..4096 * 8]);
    var frame_store: [8192]u8 = undefined;
    var task: sa.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), &frame_store, coLines, @ptrCast(*const void, &ca));
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

    // Deterministic chunk schedule ("one\n" then "two\n", split across ticks):
    // tick 0: no data -> would-block; send "on"
    // tick 1: read "on" -> would-block; send "e\n"
    // tick 2: line "one" returned; next call would-blocks; send "tw"
    // tick 3: read "tw" -> would-block; send "o\n"
    // tick 4: line "two" returned; next call would-blocks; close peer
    // tick 5: read 0 -> EOF -> coroutine returns null
    var step: u32 = 0;
    while (task.state != sa.TaskState.done and task.state != sa.TaskState.cancelled) {
        sa.tick(&s) catch @panic("tick");
        ticks += 1;
        if (step == 0) {
            const m1: []const u8 = "on";
            sendRaw(conn, m1, "async lines send 1");
            step = 1;
        } else if (step == 1) {
            const m2: []const u8 = "e\n";
            sendRaw(conn, m2, "async lines send 2");
            step = 2;
        } else if (step == 2) {
            const m3: []const u8 = "tw";
            sendRaw(conn, m3, "async lines send 3");
            step = 3;
        } else if (step == 3) {
            const m4: []const u8 = "o\n";
            sendRaw(conn, m4, "async lines send 4");
            step = 4;
        } else if (step == 4) {
            net.close(conn);
            step = 5;
        }
    }
    ck(!cc.err, "async lines read error");
    ck(cc.lines == 2, "async lines count");
    ck(cc.max_suspends >= 2, "async lines gate: a readSocketLineAsync call suspended fewer than 2 times");

    net.close(client);
    net.close(server);
    return cc.max_suspends;
}

// (c) async frames: length-prefixed MsgReader over the same coroutine model.
const CoFrames = struct {
    mr: *st.MsgReader,
    frames: u32,
    err: bool,
    ticks: *u32,
    max_suspends: u32,
};
const FramesArgs = struct { c: *CoFrames };

fn coFrames(c: *CoFrames) void {
    while (true) {
        const before = c.ticks.*;
        const m = st.readMsgAsync(c.mr) catch {
            c.err = true;
            return;
        };
        const n = c.ticks.* - before;
        if (n > c.max_suspends) c.max_suspends = n;
        if (m) |frame| {
            io.write("frame: [");
            io.write(frame);
            io.write("]\n");
            c.frames += 1;
        } else {
            return;
        }
    }
}

fn runAsyncFrames() u32 {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "async frames server");
    ck(net.bindListen(server, 5) >= 0, "async frames listen");
    var client = net.createTcpClient(PORT);
    ck(client >= 0, "async frames client");
    const conn = accept1(server);
    ck(conn >= 0, "async frames accept");
    net.setNonBlocking(&client) catch @panic("setNonBlocking");

    var buf: [8]u8 = undefined;
    var mr = st.initMsgReader(&client, buf[0..]);
    var ticks: u32 = 0;
    var cc = CoFrames{ .mr = &mr, .frames = 0, .err = false, .ticks = &ticks, .max_suspends = 0 };
    var ca = FramesArgs{ .c = &cc };

    var storage: [4096]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..4096 * 8]);
    var frame_store: [8192]u8 = undefined;
    var task: sa.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), &frame_store, coFrames, @ptrCast(*const void, &ca));
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

    // Deterministic chunk schedule (frame "hello", prefix 00 00 00 05):
    // tick 0: no data -> would-block; send "00 00"
    // tick 1: read 2 prefix bytes -> would-block; send "00 05he"
    // tick 2: prefix done, read "he" -> would-block; send "llo"
    // tick 3: frame "hello" returned; next call would-blocks; send empty + "hi"
    // tick 4: empty then "hi" returned; next call would-blocks; close peer
    // tick 5: read 0 -> EOF -> coroutine returns null
    var step: u32 = 0;
    while (task.state != sa.TaskState.done and task.state != sa.TaskState.cancelled) {
        sa.tick(&s) catch @panic("tick");
        ticks += 1;
        if (step == 0) {
            var p1: [2]u8 = undefined;
            p1[0] = 0;
            p1[1] = 0;
            sendRaw(conn, p1[0..], "async frames send 1");
            step = 1;
        } else if (step == 1) {
            var p2: [4]u8 = undefined;
            p2[0] = 0;
            p2[1] = 5;
            p2[2] = 'h';
            p2[3] = 'e';
            sendRaw(conn, p2[0..], "async frames send 2");
            step = 2;
        } else if (step == 2) {
            var p3: [3]u8 = undefined;
            p3[0] = 'l';
            p3[1] = 'l';
            p3[2] = 'o';
            sendRaw(conn, p3[0..], "async frames send 3");
            step = 3;
        } else if (step == 3) {
            // Zero-length frame then "hi", back-to-back on the wire.
            var b: [10]u8 = undefined;
            b[0] = 0;
            b[1] = 0;
            b[2] = 0;
            b[3] = 0;
            b[4] = 0;
            b[5] = 0;
            b[6] = 0;
            b[7] = 2;
            b[8] = 'h';
            b[9] = 'i';
            sendRaw(conn, b[0..], "async frames send 4");
            step = 4;
        } else if (step == 4) {
            net.close(conn);
            step = 5;
        }
    }
    ck(!cc.err, "async frames read error");
    ck(cc.frames == 3, "async frames count");
    ck(cc.max_suspends >= 2, "async frames gate: a readMsgAsync call suspended fewer than 2 times");

    net.close(client);
    net.close(server);
    return cc.max_suspends;
}

pub fn main() void {
    if (net.init() != 0) @panic("init");

    io.write("net_stream_usage\n");

    runSync();
    const line_max = runAsyncLines();
    const frame_max = runAsyncFrames();

    var max_suspends: u32 = line_max;
    if (frame_max > max_suspends) max_suspends = frame_max;

    net.cleanup();

    io.write("async-lines: 2\n");
    io.write("async-frames: 3\n");
    io.write("max-suspends: ");
    io.printInt(@intCast(i32, max_suspends));
    io.write("\n");
    io.write("net_stream ok\n");
}
