// stdlib_net_soerror_xmod — STDLIB std_net (M0 §4.1) checkSoError() contract.
//
// connectToIp() to a CLOSED loopback port must fail: the non-blocking connect
// reports EINPROGRESS, select(2) reports the socket writable, and
// checkSoError() reads getsockopt(SO_ERROR) = ECONNREFUSED and normalizes it
// through the module mapErr. The fixture reserves a free port by binding it and
// closing it (so the port is provably not listening), then connects to it and
// asserts an error is returned.
//
// GREEN: deterministic byte-exact stdout `soerror refused\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4164;
const LOOPBACK: u32 = 0x0100007F;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");

    const probe = net.createTcpServer(PORT);
    ck(probe >= 0, "probe bind");
    net.close(probe);

    const client = net.tcpSocket() catch @panic("tcpSocket");
    var failed: bool = false;
    net.connectToIp(client, LOOPBACK, PORT, 2000) catch |e| {
        _ = e;
        failed = true;
    };
    ck(failed, "expected connect error");
    net.close(client);
    net.cleanup();
    io.write("soerror refused\n");
}
