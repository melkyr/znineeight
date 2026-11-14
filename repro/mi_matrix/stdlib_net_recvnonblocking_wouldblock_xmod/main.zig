// stdlib_net_recvnonblocking_wouldblock_xmod — Plan D hardening Task 3 probe.
//
// Single-failure-per-process probe for the recvNonBlocking WouldBlock boundary
// (Plan D Task 1, Model C). On an IDLE loopback connection (nothing sent) a
// non-blocking recv must report error.WouldBlock — never a byte count and never
// 0 (EOF). The setup is deterministic and bounded: connect + accept, flip the
// client non-blocking, then one recvNonBlocking attempt. No sleep, no executor,
// no poll loop.
//
// GREEN contract (declared expected.rc 0): stdout `wouldblock ok\n`.
// Any other outcome (data, EOF, or a different error) panics (a trap is a FAIL).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4155;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
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

    // Idle socket: the ONLY accepted outcome is error.WouldBlock. A returned
    // count (data) or 0 (EOF) is a contract violation and panics.
    var buf: [16]u8 = undefined;
    const r = net.recvNonBlocking(&client, buf[0..]) catch |e| {
        ck(e == error.WouldBlock, "idle recv -> unexpected error");
        io.write("wouldblock ok\n");
        net.close(conn);
        net.close(client);
        net.close(server);
        net.cleanup();
        return;
    };
    _ = r;
    @panic("idle recv returned a count, not WouldBlock");
}
