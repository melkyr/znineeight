// stdlib_net_recvnonblocking_close_xmod — Plan D hardening Task 3 probe.
//
// Single-failure-per-process probe for the recvNonBlocking EOF boundary
// (Plan D Task 1, Model C). After the peer closes a loopback connection, a
// non-blocking recv must eventually return 0 (EOF) — not error.WouldBlock and
// not a positive count. The FIN may lag the close(2) by a scheduling quantum,
// so the probe uses a bounded retry loop (no wall-clock sleep, no executor);
// WouldBlock is the only tolerated interim result. Any data byte or any other
// error is a contract violation and panics.
//
// GREEN contract (declared expected.rc 0): stdout `close-eof ok\n`.
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4156;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

// One recvNonBlocking attempt, normalized: 0 = would-block, 1 = EOF (0 bytes),
// 2 = data. Any other error panics.
fn pollRecv(s: *net.Socket, buf: []u8) i32 {
    const n = net.recvNonBlocking(s, buf) catch |e| {
        if (e == error.WouldBlock) return 0;
        @panic("recv error");
    };
    if (n == 0) return 1;
    return 2;
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "server");
    ck(net.bindListen(server, 5) >= 0, "listen");
    const client = net.createTcpClient(PORT);
    ck(client >= 0, "client");

    var conn: i32 = -1;
    var tries: usize = 0;
    while (conn < 0 and tries < 100000) : (tries += 1) {
        conn = net.accept(server);
    }
    ck(conn >= 0, "accept");

    net.setNonBlocking(&client) catch @panic("setNonBlocking");

    // Peer close: recvNonBlocking must converge to 0 (EOF), never data.
    net.close(conn);

    var buf: [16]u8 = undefined;
    var eof: bool = false;
    var it: usize = 0;
    while (it < 1000000) : (it += 1) {
        const st = pollRecv(&client, buf[0..]);
        if (st == 1) {
            eof = true;
            break;
        }
        if (st == 2) @panic("data after peer close");
    }
    ck(eof, "peer close -> 0");

    io.write("close-eof ok\n");
    net.close(client);
    net.close(server);
    net.cleanup();
}
