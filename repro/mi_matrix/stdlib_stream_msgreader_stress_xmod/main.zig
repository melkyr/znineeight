// stdlib_stream_msgreader_stress_xmod — STDLIB std_stream (L6) MsgReader stress.
//
// No PRNG and no wall-clock sleep: every frame is an explicit deterministic
// pattern and every loop is bounded. Stresses the length-prefix frame contract
// (u32 big-endian prefix; zero-length frame is a valid empty frame; the frame
// body may not exceed the caller buffer) over loopback:
//   (a) sync — 40 back-to-back frames whose lengths cycle 0..15, then a
//       full-capacity 16-byte frame (the maximum the 16-byte buffer allows),
//       then a zero-length frame, then EOF. Every frame boundary and every body
//       byte is asserted.
//   (b) async — the 5-byte frame "hello" arrives in three pieces across ticks
//       (3 suspends), then a zero-length frame and "hi" back-to-back, then an
//       8-byte full-capacity frame ("ABCDEFGH") split across three ticks
//       (3 suspends), then EOF. The coroutine's per-call tick delta is the
//       suspension count.
//
// GREEN: sync 40 frames + max + zero + EOF; async frames [hello, "", hi,
// ABCDEFGH]; max-suspends 3; stdout `max-suspends 3\nmsgreader stress ok\n`; rc 0.
const net = @import("std_net.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const sa = @import("std_async.zig");

const PORT: u16 = 4160;
const NF: usize = 40;
const CAP: usize = 16;

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

fn sendRaw(conn: i32, bytes: []const u8, what: []const u8) void {
    ck(net.send(conn, bytes.ptr, @intCast(i32, bytes.len)) == @intCast(i32, bytes.len), what);
}

var g_wire: [4096]u8 = undefined;

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

    var off: usize = 0;
    var i: usize = 0;
    while (i < NF) : (i += 1) {
        const len: usize = i % CAP;
        putPrefix(g_wire[off..], @intCast(u32, len));
        off += 4;
        var j: usize = 0;
        while (j < len) : (j += 1) g_wire[off + j] = @intCast(u8, (i * 7 + j) % 256);
        off += len;
    }
    // full-capacity frame (the maximum the buffer allows)
    putPrefix(g_wire[off..], @intCast(u32, CAP));
    off += 4;
    var j: usize = 0;
    while (j < CAP) : (j += 1) g_wire[off + j] = @intCast(u8, (j * 3 + 1) % 256);
    off += CAP;
    // zero-length frame
    putPrefix(g_wire[off..], @intCast(u32, 0));
    off += 4;

    sendRaw(conn, g_wire[0..off], "sync send");
    net.close(conn);

    var buf: [CAP]u8 = undefined;
    var mr = st.initMsgReader(&client, buf[0..]);

    i = 0;
    while (i < NF) : (i += 1) {
        const len: usize = i % CAP;
        const got = st.readMsgSync(&mr) catch @panic("sync read");
        if (got) |frame| {
            ck(frame.len == len, "sync frame length");
            j = 0;
            while (j < len) : (j += 1) ck(frame[j] == @intCast(u8, (i * 7 + j) % 256), "sync frame byte");
        } else {
            @panic("sync frame missing");
        }
    }

    const big = st.readMsgSync(&mr) catch @panic("sync max read");
    if (big) |frame| {
        ck(frame.len == CAP, "sync max length");
        j = 0;
        while (j < CAP) : (j += 1) ck(frame[j] == @intCast(u8, (j * 3 + 1) % 256), "sync max byte");
    } else {
        @panic("sync max missing");
    }

    const zero = st.readMsgSync(&mr) catch @panic("sync zero read");
    if (zero) |frame| {
        ck(frame.len == 0, "sync zero length");
    } else {
        @panic("sync zero missing");
    }

    if ((st.readMsgSync(&mr) catch @panic("sync eof read")) != null) @panic("sync eof");

    net.close(client);
    net.close(server);
}

// (b) cooperative-yield half. `ticks` is the driver's completed-tick counter;
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
            } else if (c.frames == 3) {
                if (!(frame.len == 8 and frame[0] == 'A' and frame[7] == 'H')) c.bad = true;
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

    // Deterministic chunk schedule (buffer 8, frame "hello" prefix 00 00 00 05):
    // tick 0: no data -> would-block; send "00 00"
    // tick 1: 2 prefix bytes -> would-block; send "00 05he"
    // tick 2: prefix done, "he" -> would-block; send "llo"
    // tick 3: frame "hello" (3 suspends); next call would-blocks; send zero+hi
    // tick 4: zero then "hi" returned; next call would-blocks; send D "00 00"
    // tick 5: 2 prefix bytes -> would-block; send "00 08AB"
    // tick 6: prefix done, "AB" -> would-block; send "CDEFGH"
    // tick 7: frame "ABCDEFGH" (3 suspends); next call would-blocks; close peer
    // tick 8: read 0 -> EOF -> null; coroutine returns
    var step: u32 = 0;
    while (task.state != sa.TaskState.done and task.state != sa.TaskState.cancelled) {
        sa.tick(&s) catch @panic("tick");
        ticks += 1;
        if (step == 0) {
            var b: [2]u8 = undefined;
            b[0] = 0;
            b[1] = 0;
            sendRaw(conn, b[0..], "async send 1");
            step = 1;
        } else if (step == 1) {
            var b: [4]u8 = undefined;
            b[0] = 0;
            b[1] = 5;
            b[2] = 'h';
            b[3] = 'e';
            sendRaw(conn, b[0..], "async send 2");
            step = 2;
        } else if (step == 2) {
            var b: [3]u8 = undefined;
            b[0] = 'l';
            b[1] = 'l';
            b[2] = 'o';
            sendRaw(conn, b[0..], "async send 3");
            step = 3;
        } else if (step == 3) {
            // zero-length frame then "hi", back-to-back on the wire.
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
            var b: [2]u8 = undefined;
            b[0] = 0;
            b[1] = 0;
            sendRaw(conn, b[0..], "async send 5");
            step = 5;
        } else if (step == 5) {
            var b: [4]u8 = undefined;
            b[0] = 0;
            b[1] = 8;
            b[2] = 'A';
            b[3] = 'B';
            sendRaw(conn, b[0..], "async send 6");
            step = 6;
        } else if (step == 6) {
            const b: []const u8 = "CDEFGH";
            sendRaw(conn, b, "async send 7");
            step = 7;
        } else if (step == 7) {
            net.close(conn);
            step = 8;
        }
    }
    ck(!cc.err, "async read error");
    ck(!cc.bad, "async frame mismatch");
    ck(cc.frames == 4, "async frame count");
    ck(cc.max_suspends >= 2, "async gate: a readMsgAsync call suspended fewer than 2 times");

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
    io.write("msgreader stress ok\n");
}
