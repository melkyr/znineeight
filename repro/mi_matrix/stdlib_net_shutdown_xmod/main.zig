// stdlib_net_shutdown_xmod — STDLIB std_net (M0 §4.1) shutdown() contract.
//
// After a loopback connect, shutdown(client, 1) shuts down the client's SEND
// side, which delivers a FIN to the peer. The server's blocking recv() on the
// accepted connection then observes the half-close as a 0-byte read.
//
// GREEN: deterministic byte-exact stdout `shutdown ok\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4165;
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

    net.shutdown(client, 1);

    var buf: [8]u8 = undefined;
    var got: i32 = -1;
    var tries: usize = 0;
    while (got < 0 and tries < 1000000) : (tries += 1) {
        got = net.recv(conn, &buf[0], @intCast(i32, 1));
    }
    ck(got == 0, "server recv eof");

    net.close(conn);
    net.close(client);
    net.close(server);
    net.cleanup();
    io.write("shutdown ok\n");
}
