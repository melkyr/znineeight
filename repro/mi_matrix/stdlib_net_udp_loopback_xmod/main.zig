// stdlib_net_udp_loopback_xmod — STDLIB std_net (L3) loopback send/recv shape.
//
// Contract (blueprint §3 L3, operator m1432): a datagram sent from one bound
// UDP socket to the loopback address/port of another is delivered with the
// sender's source address and an ephemeral source port. rx binds the fixed
// port; tx binds port 0 (kernel-assigned), so the received source port must be
// nonzero.
//
// GREEN (contract): deterministic byte-exact stdout `udp loopback ok\n`.
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4145;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const rx = net.udpBind(PORT) catch @panic("bind rx");
    const tx = net.udpBind(0) catch @panic("bind tx");

    net.udpSendTo(&tx, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, "loop") catch @panic("send");

    var buf: [16]u8 = undefined;
    var addr: net.IpAddr = undefined;
    var port: u16 = 0;
    const n = net.udpRecvFrom(&rx, buf[0..], &addr, &port) catch @panic("recv");
    ck(n == 4, "loopback length");
    ck(buf[0] == 'l' and buf[3] == 'p', "loopback payload");
    ck(port != 0, "loopback source port");

    net.close(tx);
    net.close(rx);
    net.cleanup();
    io.write("udp loopback ok\n");
}
