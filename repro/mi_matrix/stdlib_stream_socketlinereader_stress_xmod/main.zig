// stdlib_stream_socketlinereader_stress_xmod — STDLIB std_stream (L6) socket
// line-reader stress. No PRNG and no wall-clock sleep: every input is an
// explicit deterministic pattern and every loop is bounded. The blocking and
// cooperative-yield halves of SocketLineReader are stressed over loopback:
//   (a) sync — a 250-byte line through a 100-byte buffer (two full overflow
//       chunks then a 50-byte remainder, so the terminator is consumed in the
//       last chunk and no spurious empty line is produced); a final line with
//       no trailing newline (returned by the EOF path); an empty source (null
//       immediately); and interleaved readers: two independent SocketLineReaders
//       over two connections, each with a 150-byte line, alternated call-by-call
//       so each reader's pending buffer must survive the other's reads.
//   (b) async — one line arrives in three pieces across ticks ("ab", "cdef",
//       "gh\n") so a single readSocketLineAsync call suspends 3 times (>= 2),
//       then "xyz\n"; then EOF. The coroutine's per-call tick delta is the
//       suspension count.
//
// GREEN: sync lines [aaa(100), aaa(100), aaa(50), xyz, empty-null, ...];
// async lines [abcdefgh, xyz]; max-suspends 3; stdout
// `max-suspends 3\nsocketlinereader stress ok\n`; rc 0.
const net = @import("std_net.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const sa = @import("std_async.zig");

const PORT: u16 = 4159;

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

fn expectChunk(lr: *st.SocketLineReader, ch: u8, len: usize, what: []const u8) void {
    const m = st.readSocketLineSync(lr) catch @panic(what);
    if (m) |line| {
        ck(line.len == len, what);
        var i: usize = 0;
        while (i < len) : (i += 1) ck(line[i] == ch, what);
    } else {
        @panic(what);
    }
}

fn expectText(lr: *st.SocketLineReader, want: []const u8, what: []const u8) void {
    const m = st.readSocketLineSync(lr) catch @panic(what);
    if (m) |line| {
        ck(line.len == want.len, what);
        var i: usize = 0;
        while (i < want.len) : (i += 1) ck(line[i] == want[i], what);
    } else {
        @panic(what);
    }
}

fn expectNull(lr: *st.SocketLineReader, what: []const u8) void {
    if ((st.readSocketLineSync(lr) catch @panic(what)) != null) @panic(what);
}

// Fill `out` with `ch` and append '\n', then send the whole line and close the
// peer so the blocking read sees the line followed by EOF.
fn sendLineClose(conn: i32, ch: u8, len: usize, what: []const u8) void {
    var i: usize = 0;
    while (i < len) : (i += 1) g_fill[i] = ch;
    g_fill[len] = '\n';
    ck(net.send(conn, g_fill[0..].ptr, @intCast(i32, len + 1)) == @intCast(i32, len + 1), what);
    net.close(conn);
}

var g_fill: [512]u8 = undefined;

// (a) blocking half.
fn runSync() void {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "sync server");
    ck(net.bindListen(server, 5) >= 0, "sync listen");

    // long line: 250 'a' through a 100-byte buffer.
    {
        const client = net.createTcpClient(PORT);
        ck(client >= 0, "long client");
        const conn = accept1(server);
        ck(conn >= 0, "long accept");
        sendLineClose(conn, 'a', 250, "long send");
        var buf: [100]u8 = undefined;
        var lr = st.initSocketLineReader(&client, buf[0..]);
        expectChunk(&lr, 'a', 100, "long chunk 1");
        expectChunk(&lr, 'a', 100, "long chunk 2");
        expectChunk(&lr, 'a', 50, "long remainder");
        expectNull(&lr, "long EOF");
        net.close(client);
    }

    // no trailing newline: "xyz" then EOF.
    {
        const client = net.createTcpClient(PORT);
        ck(client >= 0, "noeof client");
        const conn = accept1(server);
        ck(conn >= 0, "noeof accept");
        const msg: []const u8 = "xyz";
        ck(net.send(conn, msg.ptr, @intCast(i32, msg.len)) == 3, "noeof send");
        net.close(conn);
        var buf: [100]u8 = undefined;
        var lr = st.initSocketLineReader(&client, buf[0..]);
        expectText(&lr, "xyz", "noeof final line");
        expectNull(&lr, "noeof EOF");
        net.close(client);
    }

    // empty source: peer closes with no bytes.
    {
        const client = net.createTcpClient(PORT);
        ck(client >= 0, "empty client");
        const conn = accept1(server);
        ck(conn >= 0, "empty accept");
        net.close(conn);
        var buf: [100]u8 = undefined;
        var lr = st.initSocketLineReader(&client, buf[0..]);
        expectNull(&lr, "empty EOF");
        net.close(client);
    }

    // interleaved readers over two connections.
    {
        const ca = net.createTcpClient(PORT);
        ck(ca >= 0, "ia client");
        const cona = accept1(server);
        ck(cona >= 0, "ia accept");
        const cb = net.createTcpClient(PORT);
        ck(cb >= 0, "ib client");
        const conb = accept1(server);
        ck(conb >= 0, "ib accept");
        sendLineClose(cona, 'a', 150, "ia send");
        sendLineClose(conb, 'b', 150, "ib send");
        var abuf: [100]u8 = undefined;
        var bbuf: [100]u8 = undefined;
        var alr = st.initSocketLineReader(&ca, abuf[0..]);
        var blr = st.initSocketLineReader(&cb, bbuf[0..]);
        expectChunk(&alr, 'a', 100, "interleave a1");
        expectChunk(&blr, 'b', 100, "interleave b1");
        expectChunk(&alr, 'a', 50, "interleave a2");
        expectChunk(&blr, 'b', 50, "interleave b2");
        expectNull(&alr, "interleave a EOF");
        expectNull(&blr, "interleave b EOF");
        net.close(ca);
        net.close(cb);
    }

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
                if (!(line.len == 8 and line[0] == 'a' and line[7] == 'h')) c.bad = true;
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

    // Deterministic chunk schedule (buffer 16, async chunk 4):
    // tick 0: no data -> would-block (suspend 1); send "ab"
    // tick 1: read "ab" -> would-block (suspend 2); send "cdef"
    // tick 2: read "cdef" -> would-block (suspend 3); send "gh\n"
    // tick 3: line "abcdefgh" (3 suspends); next call would-blocks; send "xyz\n"
    // tick 4: line "xyz" (1 suspend); next call would-blocks; close peer
    // tick 5: read 0 -> EOF -> null; coroutine returns
    var step: u32 = 0;
    while (task.state != sa.TaskState.done and task.state != sa.TaskState.cancelled) {
        sa.tick(&s) catch @panic("tick");
        ticks += 1;
        if (step == 0) {
            const m1: []const u8 = "ab";
            ck(net.send(conn, m1.ptr, @intCast(i32, m1.len)) == 2, "async send 1");
            step = 1;
        } else if (step == 1) {
            const m2: []const u8 = "cdef";
            ck(net.send(conn, m2.ptr, @intCast(i32, m2.len)) == 4, "async send 2");
            step = 2;
        } else if (step == 2) {
            const m3: []const u8 = "gh\n";
            ck(net.send(conn, m3.ptr, @intCast(i32, m3.len)) == 3, "async send 3");
            step = 3;
        } else if (step == 3) {
            const m4: []const u8 = "xyz\n";
            ck(net.send(conn, m4.ptr, @intCast(i32, m4.len)) == 4, "async send 4");
            step = 4;
        } else if (step == 4) {
            net.close(conn);
            step = 5;
        }
    }
    ck(!cc.err, "async read error");
    ck(!cc.bad, "async line mismatch");
    ck(cc.lines == 2, "async line count");
    ck(cc.max_suspends >= 2, "async gate: a readSocketLineAsync call suspended fewer than 2 times");

    net.close(client);
    net.close(server);

    io.write("max-suspends ");
    io.printInt(@intCast(i32, cc.max_suspends));
    io.writeByte('\n');
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    runSync();
    runAsync();
    net.cleanup();
    io.write("socketlinereader stress ok\n");
}
