// stdlib_net_nonblocking_stress_xmod — STDLIB std_net (L3) non-blocking stress.
//
// No PRNG and no wall-clock sleep: every byte is an explicit deterministic
// formula and every loop is bounded. One loopback TCP connection; the client is
// switched non-blocking (setNonBlocking) and drained with recvNonBlocking.
// Stresses, in order:
//   - would-block on an empty socket (the initial contract);
//   - a 4096-byte payload drained through a SMALL (8-byte) buffer so the
//     partial-chunk interleaving is exercised (512 bounded reads, byte-exact);
//   - a zero-length send (delivers nothing; the socket stays would-block);
//   - the maximum chunk: a 65536-byte payload drained through a 65536-byte
//     buffer, asserting the full byte-exact payload and that the largest single
//     recv exceeded the small-buffer read size;
//   - the EOF boundary: peer close -> recvNonBlocking returns 0.
//
// GREEN (contract): deterministic byte-exact stdout `net nonblocking stress ok\n`
// (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4158;
const N_PARTIAL: usize = 4096;
const SMALL: usize = 8;
const BIG: usize = 65536;
const BOUND: usize = 1000000;

var g_tx: [BIG]u8 = undefined;
var g_rx: [BIG]u8 = undefined;

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

// One recvNonBlocking attempt, normalized: 0 = would-block, 1 = peer close
// (0 bytes), 2 = data (`out_n` bytes). Any other error panics.
fn pollRecv(s: *net.Socket, buf: []u8, out_n: *usize) i32 {
    out_n.* = 0;
    const n = net.recvNonBlocking(s, buf) catch |e| {
        if (e == error.WouldBlock) return 0;
        @panic("recv error");
    };
    if (n == 0) return 1;
    out_n.* = n;
    return 2;
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "server");
    ck(net.bindListen(server, 5) >= 0, "listen");
    const client = net.createTcpClient(PORT);
    ck(client >= 0, "client");
    const conn = accept1(server);
    ck(conn >= 0, "accept");
    net.setNonBlocking(&client) catch @panic("setNonBlocking");

    var n: usize = 0;
    var buf: [SMALL]u8 = undefined;

    // --- would-block on an empty socket -------------------------------------
    ck(pollRecv(&client, buf[0..], &n) == 0, "empty -> WouldBlock");

    // --- partial drain through the small buffer -----------------------------
    var i: usize = 0;
    while (i < N_PARTIAL) : (i += 1) {
        g_tx[i] = @intCast(u8, (i * 31 + 7) % 256);
    }
    ck(net.send(conn, g_tx[0..].ptr, @intCast(i32, N_PARTIAL)) == @intCast(i32, N_PARTIAL), "send partial payload");

    var total: usize = 0;
    var reads: usize = 0;
    var st: i32 = 0;
    while (total < N_PARTIAL and reads < BOUND) : (reads += 1) {
        st = pollRecv(&client, buf[0..], &n);
        if (st != 2) break;
        var j: usize = 0;
        while (j < n) : (j += 1) {
            ck(buf[j] == g_tx[total + j], "partial byte");
        }
        total += n;
    }
    ck(st == 2, "partial drain status");
    ck(total == N_PARTIAL, "partial total");
    ck(reads == N_PARTIAL / SMALL, "partial read count");
    ck(pollRecv(&client, buf[0..], &n) == 0, "drained -> WouldBlock");

    // --- zero-length send ---------------------------------------------------
    ck(net.send(conn, g_tx[0..].ptr, @intCast(i32, 0)) == 0, "zero-length send");
    ck(pollRecv(&client, buf[0..], &n) == 0, "after zero send -> WouldBlock");

    // --- maximum chunk ------------------------------------------------------
    i = 0;
    while (i < BIG) : (i += 1) {
        g_tx[i] = @intCast(u8, (i * 13 + 5) % 256);
    }
    ck(net.send(conn, g_tx[0..].ptr, @intCast(i32, BIG)) == @intCast(i32, BIG), "send big payload");

    var max_recv: usize = 0;
    total = 0;
    var it: usize = 0;
    while (total < BIG and it < BOUND) : (it += 1) {
        const got = net.recvNonBlocking(&client, g_rx[total..BIG]) catch |e| {
            if (e == error.WouldBlock) continue;
            @panic("big recv error");
        };
        ck(got != 0, "big unexpected eof");
        if (got > max_recv) max_recv = got;
        total += got;
    }
    ck(total == BIG, "big total");
    i = 0;
    while (i < BIG) : (i += 1) {
        ck(g_rx[i] == g_tx[i], "big byte");
    }
    ck(max_recv > SMALL, "max chunk larger than the small buffer");

    // --- EOF boundary -------------------------------------------------------
    net.close(conn);
    var eof: bool = false;
    it = 0;
    while (it < BOUND) : (it += 1) {
        if (pollRecv(&client, buf[0..], &n) == 1) {
            eof = true;
            break;
        }
    }
    ck(eof, "peer close -> 0");

    net.close(client);
    net.close(server);
    net.cleanup();
    io.write("net nonblocking stress ok\n");
}
