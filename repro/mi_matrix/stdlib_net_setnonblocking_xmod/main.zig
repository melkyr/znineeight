// stdlib_net_setnonblocking_xmod — STDLIB std_net (L3) setNonBlocking contract.
//
// Contract (Plan D Task 1, Model C cooperative-yield): setNonBlocking(s)
// flips a connected socket to non-blocking (win32 ioctlsocket(FIONBIO);
// POSIX fcntl(F_GETFL)/fcntl(F_SETFL, O_NONBLOCK)) and reports NetError!void.
//
// The flip is observed WITHOUT recvNonBlocking so this fixture isolates
// setNonBlocking: after the flip a raw `recv` on a socket with no pending data
// returns -1 immediately (POSIX EAGAIN/EWOULDBLOCK, win32 WSAEWOULDBLOCK)
// instead of blocking; once the peer sends bytes the same raw `recv` returns
// them, proving the socket is otherwise healthy and the -1 was would-block.
//
// RED (pre-Task-1): the emitted module has no `setNonBlocking`, so this fixture
// fails to compile (unknown member / unsupported call).
//
// GREEN (contract): deterministic byte-exact stdout `setnonblocking ok\n`
// (rc 0). The loopback pair is torn down before exit.
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4149;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
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

    // No data pending: the non-blocking raw recv returns -1 (would-block).
    var buf: [16]u8 = undefined;
    const empty = net.recv(client, &buf[0], @intCast(i32, 16));
    ck(empty == -1, "no data -> recv -1");

    // The socket still carries data: peer sends, raw recv returns it.
    const msg: []const u8 = "PING";
    ck(net.send(conn, msg.ptr, @intCast(i32, msg.len)) == 4, "send");
    var got: i32 = -1;
    var it: usize = 0;
    while (got < 0 and it < 1000000) : (it += 1) {
        got = net.recv(client, &buf[0], @intCast(i32, 16));
    }
    ck(got == 4, "data -> recv 4");
    ck(buf[0] == 'P' and buf[3] == 'G', "payload");

    net.close(conn);
    net.close(client);
    net.close(server);
    net.cleanup();
    io.write("setnonblocking ok\n");
}
