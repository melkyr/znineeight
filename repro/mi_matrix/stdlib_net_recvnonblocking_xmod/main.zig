// stdlib_net_recvnonblocking_xmod — STDLIB std_net (L3) recvNonBlocking contract.
//
// Contract (Plan D Task 1, Model C): recvNonBlocking(s, buf) is NetError!usize.
// On a non-blocking connected socket it returns `error.WouldBlock` when no data
// is ready, the byte count once the peer sends, and 0 at peer close (EOF). The
// error mapping reuses the module's mapErr (POSIX EAGAIN/EWOULDBLOCK=11,
// win32 WSAEWOULDBLOCK=10035 -> WouldBlock).
//
// RED (pre-Task-1): the emitted module has no `recvNonBlocking`, so this
// fixture fails to compile.
//
// GREEN (contract): deterministic byte-exact stdout `recvnonblocking ok\n`
// (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4150;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

// One recvNonBlocking attempt, normalized for the polling loop:
//   0 = would-block, 1 = peer close (0 bytes), 2 = data (`out_n` bytes).
// Any other error is a contract violation and panics.
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
    if (server < 0) @panic("server");
    if (net.bindListen(server, 5) < 0) @panic("listen");
    const client = net.createTcpClient(PORT);
    if (client < 0) @panic("client");

    var conn: i32 = -1;
    var tries: usize = 0;
    while (conn < 0 and tries < 100000) : (tries += 1) {
        conn = net.accept(server);
    }
    if (conn < 0) @panic("accept");

    net.setNonBlocking(&client) catch @panic("setNonBlocking");

    var buf: [16]u8 = undefined;
    var n: usize = 0;

    // 1. No data yet -> WouldBlock (the non-blocking contract).
    ck(pollRecv(&client, buf[0..], &n) == 0, "no data -> WouldBlock");

    // 2. Peer sends -> the exact bytes arrive.
    const msg: []const u8 = "HELLO";
    ck(net.send(conn, msg.ptr, @intCast(i32, msg.len)) == 5, "send");
    var st: i32 = 0;
    var it: usize = 0;
    while (it < 1000000) : (it += 1) {
        st = pollRecv(&client, buf[0..], &n);
        if (st == 2) break;
    }
    ck(st == 2, "data status");
    ck(n == 5, "recv length");
    ck(buf[0] == 'H' and buf[4] == 'O', "recv payload");

    // 3. Peer close -> 0 (EOF), not WouldBlock.
    net.close(conn);
    var eof: bool = false;
    var it2: usize = 0;
    while (it2 < 1000000) : (it2 += 1) {
        if (pollRecv(&client, buf[0..], &n) == 1) {
            eof = true;
            break;
        }
    }
    ck(eof, "peer close -> 0");

    net.close(client);
    net.close(server);
    net.cleanup();
    io.write("recvnonblocking ok\n");
}
