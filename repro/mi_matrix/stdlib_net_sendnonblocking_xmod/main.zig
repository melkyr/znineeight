// stdlib_net_sendnonblocking_xmod — STDLIB std_net (L3) sendNonBlocking contract.
//
// Contract (Plan D Task 1, Model C): sendNonBlocking(s, buf) is NetError!usize.
// On a non-blocking connected socket it submits `buf` and returns the number of
// bytes accepted (a short count is legal when the send buffer is full; full
// buffers surface `error.WouldBlock` via the module mapErr). This fixture pins
// the small-payload path: the whole payload is accepted and arrives intact at
// the peer. The would-block path is intentionally not pinned here (it depends
// on OS send-buffer sizing and is not deterministic).
//
// RED (pre-Task-1): the emitted module has no `sendNonBlocking`, so this
// fixture fails to compile.
//
// GREEN (contract): deterministic byte-exact stdout `sendnonblocking ok\n`
// (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4151;

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

    net.setNonBlocking(&conn) catch @panic("setNonBlocking");

    // Small payload on an empty send buffer: the whole buffer is accepted.
    const msg: []const u8 = "WORLD";
    const n = net.sendNonBlocking(&conn, msg) catch @panic("sendNonBlocking");
    ck(n == 5, "send count");

    // The peer receives the exact bytes (blocking recv; data is in flight).
    var buf: [16]u8 = undefined;
    var got: i32 = -1;
    var it: usize = 0;
    while (got < 0 and it < 1000000) : (it += 1) {
        got = net.recv(client, &buf[0], @intCast(i32, 16));
    }
    ck(got == 5, "recv count");
    ck(buf[0] == 'W' and buf[4] == 'D', "payload");

    net.close(conn);
    net.close(client);
    net.close(server);
    net.cleanup();
    io.write("sendnonblocking ok\n");
}
