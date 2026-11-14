// stdlib_net_udp_zero_len_xmod — STDLIB std_net (L3) zero-length datagram.
//
// Contract (blueprint §3 L3, operator m1432): a zero-length UDP datagram is
// delivered, and udpRecvFrom returns 0 (not an error, not null). The datagram
// boundary is preserved: one sendto == one recvfrom.
//
// GREEN (contract): deterministic byte-exact stdout `udp zero len ok\n`.
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4146;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, "") catch @panic("send");

    var buf: [16]u8 = undefined;
    var addr: net.IpAddr = undefined;
    var port: u16 = 0;
    const n = net.udpRecvFrom(&s, buf[0..], &addr, &port) catch @panic("recv");
    ck(n == 0, "zero-length datagram returns 0");

    net.close(s);
    net.cleanup();
    io.write("udp zero len ok\n");
}
