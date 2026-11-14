// stdlib_stream_msgreader_xmod — Plan D Task 3 (L6) MsgReader.
//
// Contract (operator framing ruling; program spec §8; blueprint §3 L6):
// `MsgReader` reads length-prefixed frames from a caller-owned
// `*std_net.Socket` over the same caller buffer as SocketLineReader.
//   (1) the length prefix is a u32 in NETWORK byte order (big-endian);
//   (2) a declared length larger than the reader buffer capacity is
//       `error.FrameTooLarge` (the one operator-authorized std_stream error);
//   (3) a zero-length frame (prefix 0) is a VALID empty frame — a length-0
//       slice, never null.
// `readMsgSync` blocks (no suspension); `readMsgAsync` is a SEPARATE
// implementation (C3) that yields on `error.WouldBlock` and is re-driven on
// the next tick (Model C).
//
// This fixture pins, over loopback:
//   (a) sync — pre-sent frames "abc", empty, a full-capacity 16-byte frame,
//       then two back-to-back frames "xy" and "z", then EOF. A 1-byte frame
//       proves the u32 prefix is decoded big-endian (little-endian would read
//       0x03000000 and reject it as oversized).
//   (b) the oversize probe — a declared length of 17 with a 16-byte buffer is
//       asserted to be `error.FrameTooLarge` (the declared expected-failure
//       assertion; it prints the stable line `frametoolarge ok`).
//   (c) async — the 5-byte frame "hello" arrives in three pieces across ticks
//       (2 prefix bytes; 2 prefix bytes + "he"; "llo"), then a zero-length
//       frame and "hi" arrive back-to-back, then EOF. The coroutine's per-call
//       tick delta is the suspension count; the async gate asserts a
//       readMsgAsync call suspended >= 2 times.
//
// GREEN: sync frames [abc, "", 0123456789abcdef, xy, z]; oversize probe ok;
// async frames [hello, "", hi]; max-suspends 3; stdout
// `frametoolarge ok\nmax-suspends 3\nmsgreader ok\n`; rc 0.
const net = @import("std_net.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const sa = @import("std_async.zig");

const PORT: u16 = 4153;

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

// Encode a u32 big-endian prefix into `pfx` (network byte order).
fn putPrefix(pfx: []u8, len: u32) void {
    pfx[0] = @intCast(u8, (len >> 24) & @intCast(u32, 255));
    pfx[1] = @intCast(u8, (len >> 16) & @intCast(u32, 255));
    pfx[2] = @intCast(u8, (len >> 8) & @intCast(u32, 255));
    pfx[3] = @intCast(u8, len & @intCast(u32, 255));
}

// Send one length-prefixed frame: 4-byte big-endian prefix then the body.
fn sendFrame(conn: i32, body: []const u8) void {
    var pfx: [4]u8 = undefined;
    putPrefix(pfx[0..4], @intCast(u32, body.len));
    ck(net.send(conn, @ptrCast([*]const u8, &pfx), 4) == 4, "send prefix");
    if (body.len > 0) {
        ck(net.send(conn, body.ptr, @intCast(i32, body.len)) == @intCast(i32, body.len), "send body");
    }
}

fn sendRaw(conn: i32, bytes: []const u8, what: []const u8) void {
    ck(net.send(conn, bytes.ptr, @intCast(i32, bytes.len)) == @intCast(i32, bytes.len), what);
}

// Assert the next sync frame equals `want` (null = EOF).
fn expectSync(mr: *st.MsgReader, want: ?[]const u8, what: []const u8) void {
    const got = st.readMsgSync(mr) catch @panic("sync read error");
    if (want) |w| {
        if (got) |frame| {
            ck(frame.len == w.len, what);
            var i: usize = 0;
            while (i < w.len) : (i += 1) {
                ck(frame[i] == w[i], what);
            }
        } else {
            @panic("sync frame missing");
        }
    } else {
        ck(got == null, what);
    }
}

// (a) blocking half. All data is sent before the reads because the program is
// single-threaded: a blocking read with nothing buffered would deadlock.
fn runSync() void {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "sync server");
    ck(net.bindListen(server, 5) >= 0, "sync listen");
    const client = net.createTcpClient(PORT);
    ck(client >= 0, "sync client");
    const conn = accept1(server);
    ck(conn >= 0, "sync accept");

    sendFrame(conn, "abc");
    sendFrame(conn, "");
    sendFrame(conn, "0123456789abcdef");
    sendFrame(conn, "xy");
    sendFrame(conn, "z");
    net.close(conn);

    var buf: [16]u8 = undefined;
    var mr = st.initMsgReader(&client, buf[0..]);
    expectSync(&mr, "abc", "sync frame 1 (big-endian prefix)");
    expectSync(&mr, "", "sync frame 2 (zero-length)");
    expectSync(&mr, "0123456789abcdef", "sync frame 3 (full capacity)");
    expectSync(&mr, "xy", "sync frame 4 (back-to-back a)");
    expectSync(&mr, "z", "sync frame 5 (back-to-back b)");
    expectSync(&mr, null, "sync eof");

    net.close(client);
    net.close(server);
}

// (b) oversize probe. A declared length of 17 with a 16-byte buffer must be
// rejected as error.FrameTooLarge (the declared expected-failure assertion).
fn runTooLarge() void {
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "large server");
    ck(net.bindListen(server, 5) >= 0, "large listen");
    const client = net.createTcpClient(PORT);
    ck(client >= 0, "large client");
    const conn = accept1(server);
    ck(conn >= 0, "large accept");

    var pfx: [4]u8 = undefined;
    putPrefix(pfx[0..4], @intCast(u32, 17));
    ck(net.send(conn, @ptrCast([*]const u8, &pfx), 4) == 4, "large send");

    var buf: [16]u8 = undefined;
    var mr = st.initMsgReader(&client, buf[0..]);
    const got = st.readMsgSync(&mr) catch |e| {
        if (e == error.FrameTooLarge) {
            net.close(conn);
            net.close(client);
            net.close(server);
            return;
        }
        @panic("large: wrong error");
    };
    _ = got;
    @panic("large: no error");
}

// (c) cooperative-yield half. `ticks` is the driver's completed-tick counter;
// a readMsgAsync call that suspends k times advances it by exactly k.
const CoCtx = struct {
    mr: *st.MsgReader,
    frames: u32,
    bad: bool,
    err: bool,
    ticks: *u32,
    max_suspends: u32,
};
const CArgs = struct { c: *CoCtx };

fn co(c: *CoCtx) void {
    while (true) {
        const before = c.ticks.*;
        const m = st.readMsgAsync(c.mr) catch {
            c.err = true;
            return;
        };
        const n = c.ticks.* - before;
        if (n > c.max_suspends) c.max_suspends = n;
        if (m) |frame| {
            if (c.frames == 0) {
                if (!(frame.len == 5 and frame[0] == 'h' and frame[4] == 'o')) c.bad = true;
            } else if (c.frames == 1) {
                if (frame.len != 0) c.bad = true;
            } else if (c.frames == 2) {
                if (!(frame.len == 2 and frame[0] == 'h' and frame[1] == 'i')) c.bad = true;
            } else {
                c.bad = true;
            }
            c.frames += 1;
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

    var buf: [8]u8 = undefined;
    var mr = st.initMsgReader(&client, buf[0..]);
    var ticks: u32 = 0;
    var cc = CoCtx{ .mr = &mr, .frames = 0, .bad = false, .err = false, .ticks = &ticks, .max_suspends = 0 };
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
            sendRaw(conn, p1[0..], "async send 1");
            step = 1;
        } else if (step == 1) {
            var p2: [4]u8 = undefined;
            p2[0] = 0;
            p2[1] = 5;
            p2[2] = 'h';
            p2[3] = 'e';
            sendRaw(conn, p2[0..], "async send 2");
            step = 2;
        } else if (step == 2) {
            var p3: [3]u8 = undefined;
            p3[0] = 'l';
            p3[1] = 'l';
            p3[2] = 'o';
            sendRaw(conn, p3[0..], "async send 3");
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
            sendRaw(conn, b[0..], "async send 4");
            step = 4;
        } else if (step == 4) {
            net.close(conn);
            step = 5;
        }
    }
    ck(!cc.err, "async read error");
    ck(!cc.bad, "async frame mismatch");
    ck(cc.frames == 3, "async frame count");
    ck(cc.max_suspends >= 2, "async gate: a readMsgAsync call suspended fewer than 2 times");

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
    runTooLarge();
    io.write("frametoolarge ok\n");
    runAsync();
    net.cleanup();
    io.write("msgreader ok\n");
}
