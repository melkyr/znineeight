// stdlib_net_udp_sendto_xmod — STDLIB std_net (L3) udpSendTo GREEN fixture.
//
// Contract (blueprint §3 L3, operator m1432): udpSendTo(s, addr, port, data)
// NetError!void sends one datagram to addr:port from the bound socket. addr is
// the private IpAddr {a,b,c,d}; callers build it with an anonymous struct
// literal. The fixture also receives the looped-back datagram and asserts the
// payload, the source port, and the source IP (127.0.0.1).
//
// GREEN (contract): deterministic byte-exact stdout `udp sendto ok\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4142;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, "ping") catch @panic("udpSendTo");

    // Receive-side delivery assertion: the datagram looped back to the bound
    // socket, with the sender's source port and loopback source IP.
    var buf: [32]u8 = undefined;
    var addr: net.IpAddr = undefined;
    var port: u16 = 0;
    const n = net.udpRecvFrom(&s, buf[0..], &addr, &port) catch @panic("udpRecvFrom");
    ck(n == 4, "recv length");
    ck(buf[0] == 'p' and buf[3] == 'g', "recv payload");
    ck(port == PORT, "recv source port");
    ck(addr.a == 127 and addr.b == 0 and addr.c == 0 and addr.d == 1, "recv source ip");

    net.close(s);
    net.cleanup();
    io.write("udp sendto ok\n");
}
