// stdlib_net_udp_sendto_xmod — STDLIB std_net (L3) udpSendTo GREEN fixture.
//
// Contract (blueprint §3 L3, operator m1432): udpSendTo(s, addr, port, data)
// NetError!void sends one datagram to addr:port from the bound socket. addr is
// the private IpAddr {a,b,c,d}; callers build it with an anonymous struct
// literal. The datagram is queued on the loopback socket and discarded by
// close (no drain needed).
//
// GREEN (contract): deterministic byte-exact stdout `udp sendto ok\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4142;

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, "ping") catch @panic("udpSendTo");
    net.close(s);
    net.cleanup();
    io.write("udp sendto ok\n");
}
