// stdlib_stream_socketlinereader_xmod — Plan D Task 2 (L6) SocketLineReader.
//
// Contract (program spec §8; blueprint §3 L6): `SocketLineReader` wraps a
// caller-owned `*std_net.Socket` and the same caller buffer as FileLineReader.
// `readSocketLineSync` blocks (no suspension); `readSocketLineAsync` is a
// SEPARATE implementation (C3) that yields on `error.WouldBlock` and is
// re-driven on the next tick (Model C). Both strip the terminating \n and the
// \r of \r\n, return the final unterminated line, and return null at EOF.
//
// This fixture pins both halves:
//   (a) sync — pre-sent loopback stream "one\r\nabcdefg\r\nhi\nlast" read with
//       an 8-byte buffer (blocks; no coroutine). This covers a normal CRLF, a
//       boundary CR at a full-buffer overflow (the following '\n' is consumed
//       as that line's terminator, not a spurious empty line), and the final
//       unterminated line.
//   (b) async — loopback line "abcdef\n" arrives as "abc" then "def\n" on
//       separate ticks (a partial line across ticks), then "xyz\n". The
//       coroutine's per-call tick delta is the suspension count; the async
//       gate asserts a readSocketLineAsync call suspended >= 2 times.
//
// GREEN: sync lines [one, abcdefg, hi, last]; async lines [abcdef, xyz];
// max-suspends 2; stdout `max-suspends 2\nsocketlinereader ok\n`; rc 0.
const net = @import("std_net.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const sa = @import("std_async.zig");

const PORT: u16 = 4152;

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

// (a) blocking half. The data is sent before the read because the program is
// single-threaded: a blocking read with nothing buffered would deadlock.
fn runSync() void {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "sync server");
    ck(net.bindListen(server, 5) >= 0, "sync listen");
    const client = net.createTcpClient(PORT);
    ck(client >= 0, "sync client");
    const conn = accept1(server);
    ck(conn >= 0, "sync accept");

    // "one\r\n" normal CRLF; "abcdefg\r" fills the 8-byte buffer with a
    // boundary CR (takeSocketOverflow -> pending_cr; the next read consumes
    // the following '\n' as the same terminator, no spurious empty line);
    // "hi\n" then "last" (unterminated) at EOF.
    const payload: []const u8 = "one\r\nabcdefg\r\nhi\nlast";
    ck(net.send(conn, payload.ptr, @intCast(i32, payload.len)) == @intCast(i32, payload.len), "sync send");
    net.close(conn);

    var buf: [8]u8 = undefined;
    var lr = st.initSocketLineReader(&client, buf[0..]);

    const a = st.readSocketLineSync(&lr) catch @panic("sync read 1");
    if (a) |line| {
        ck(line.len == 3 and line[0] == 'o' and line[2] == 'e', "sync line one (CRLF strip)");
    } else {
        @panic("sync line one missing");
    }
    const b = st.readSocketLineSync(&lr) catch @panic("sync read 2");
    if (b) |line| {
        ck(line.len == 7 and line[0] == 'a' and line[6] == 'g', "sync line two (overflow boundary CR)");
    } else {
        @panic("sync line two missing");
    }
    const c = st.readSocketLineSync(&lr) catch @panic("sync read 3");
    if (c) |line| {
        ck(line.len == 2 and line[0] == 'h' and line[1] == 'i', "sync line three (after boundary CR)");
    } else {
        @panic("sync line three missing");
    }
    const d = st.readSocketLineSync(&lr) catch @panic("sync read 4");
    if (d) |line| {
        ck(line.len == 4 and line[0] == 'l' and line[3] == 't', "sync line four (unterminated)");
    } else {
        @panic("sync line four missing");
    }
    const e = st.readSocketLineSync(&lr) catch @panic("sync read 5");
    ck(e == null, "sync eof");

    net.close(client);
    net.close(server);
}

// (b) cooperative-yield half. `ticks` is the driver's completed-tick counter;
// a readSocketLineAsync call that suspends k times advances it by exactly k.
const CoCtx = struct {
    lr: *st.SocketLineReader,
    lines: u32,
    bad: bool,
    err: bool,
    ticks: *u32,
    max_suspends: u32,
};
const CArgs = struct { c: *CoCtx };

fn co(c: *CoCtx) void {
    while (true) {
        const before = c.ticks.*;
        const m = st.readSocketLineAsync(c.lr) catch {
            c.err = true;
            return;
        };
        const n = c.ticks.* - before;
        if (n > c.max_suspends) c.max_suspends = n;
        if (m) |line| {
            if (c.lines == 0) {
                if (!(line.len == 6 and line[0] == 'a' and line[5] == 'f')) c.bad = true;
            } else if (c.lines == 1) {
                if (!(line.len == 3 and line[0] == 'x' and line[2] == 'z')) c.bad = true;
            } else {
                c.bad = true;
            }
            c.lines += 1;
        } else {
            return;
        }
    }
}

fn runAsync() void {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "async server");
    ck(net.bindListen(server, 5) >= 0, "async listen");
    var client = net.createTcpClient(PORT);
    ck(client >= 0, "async client");
    const conn = accept1(server);
    ck(conn >= 0, "async accept");
    net.setNonBlocking(&client) catch @panic("setNonBlocking");

    var buf: [16]u8 = undefined;
    var lr = st.initSocketLineReader(&client, buf[0..]);
    var ticks: u32 = 0;
    var cc = CoCtx{ .lr = &lr, .lines = 0, .bad = false, .err = false, .ticks = &ticks, .max_suspends = 0 };
    var ca = CArgs{ .c = &cc };

    var storage: [4096]u64 = undefined;
    var ctx = sa.contextInit(@ptrCast([*]u8, &storage)[0..4096 * 8]);
    var frame_store: [8192]u8 = undefined;
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

    // Deterministic chunk schedule: after each completed tick the coroutine has
    // consumed the previous chunk (and is waiting), so send the next piece.
    // tick 0: no data -> would-block; send "abc"    (partial, no newline)
    // tick 1: read "abc" -> would-block; send "def\n"
    // tick 2: read "def\n" -> line "abcdef"; send "xyz\n"
    // tick 3: read "xyz\n" -> line "xyz"; close peer
    // tick 4: read 0 -> EOF -> coroutine returns null
    var step: u32 = 0;
    while (task.state != sa.TaskState.done and task.state != sa.TaskState.cancelled) {
        sa.tick(&s) catch @panic("tick");
        ticks += 1;
        if (step == 0) {
            const m1: []const u8 = "abc";
            ck(net.send(conn, m1.ptr, @intCast(i32, m1.len)) == 3, "async send 1");
            step = 1;
        } else if (step == 1) {
            const m2: []const u8 = "def\n";
            ck(net.send(conn, m2.ptr, @intCast(i32, m2.len)) == 4, "async send 2");
            step = 2;
        } else if (step == 2) {
            const m3: []const u8 = "xyz\n";
            ck(net.send(conn, m3.ptr, @intCast(i32, m3.len)) == 4, "async send 3");
            step = 3;
        } else if (step == 3) {
            net.close(conn);
            step = 4;
        }
    }
    ck(!cc.err, "async read error");
    ck(!cc.bad, "async line mismatch");
    ck(cc.lines == 2, "async line count");
    ck(cc.max_suspends >= 2, "async gate: a readSocketLineAsync call suspended fewer than 2 times");

    net.close(client);
    net.close(server);

    // Observable async gate: the per-call suspension maximum (must be >= 2).
    io.write("max-suspends ");
    io.printInt(@intCast(i32, cc.max_suspends));
    io.writeByte('\n');
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    runSync();
    runAsync();
    net.cleanup();
    io.write("socketlinereader ok\n");
}
