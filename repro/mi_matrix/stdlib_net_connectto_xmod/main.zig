// stdlib_net_connectto_xmod — STDLIB std_net (M0 §4.1) tcpSocket/connectToIp.
//
// tcpSocket() returns a fresh AF_INET/SOCK_STREAM socket and connectToIp()
// performs a non-blocking connect to an arbitrary IPv4 (network byte order) +
// port, waiting on select(2) for writability and then reading
// getsockopt(SO_ERROR). This fixture stands up a loopback listener with
// createTcpServer + bindListen, connects with the new primitives, then echoes a
// 2-byte payload client -> server -> client and verifies it byte-for-byte.
//
// GREEN: deterministic byte-exact stdout `connectto ok\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4161;
const LOOPBACK: u32 = 0x0100007F;

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

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "server");
    ck(net.bindListen(server, 5) >= 0, "listen");

    const client = net.tcpSocket() catch @panic("tcpSocket");
    net.connectToIp(client, LOOPBACK, PORT, 2000) catch @panic("connectToIp");
    const conn = accept1(server);
    ck(conn >= 0, "accept");

    var msg: []const u8 = "hi";
    ck(net.send(client, msg.ptr, @intCast(i32, msg.len)) == @intCast(i32, msg.len), "client send");

    var buf: [8]u8 = undefined;
    var got: i32 = -1;
    var tries: usize = 0;
    while (got < 0 and tries < 1000000) : (tries += 1) {
        got = net.recv(conn, &buf[0], @intCast(i32, 2));
    }
    ck(got == 2, "server recv");
    ck(buf[0] == 'h' and buf[1] == 'i', "payload");

    ck(net.send(conn, msg.ptr, @intCast(i32, msg.len)) == @intCast(i32, msg.len), "server send");
    var back: [8]u8 = undefined;
    var gb: i32 = -1;
    var t2: usize = 0;
    while (gb < 0 and t2 < 1000000) : (t2 += 1) {
        gb = net.recv(client, &back[0], @intCast(i32, 2));
    }
    ck(gb == 2, "client recv");
    ck(back[0] == 'h' and back[1] == 'i', "echo");

    net.close(conn);
    net.close(client);
    net.close(server);
    net.cleanup();
    io.write("connectto ok\n");
}
