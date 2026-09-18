// stdlib_net_udp_recvfrom_xmod — STDLIB std_net (L3) udpRecvFrom GREEN fixture.
//
// Contract (blueprint §3 L3, operator m1432): udpRecvFrom(s, buf, out_addr,
// out_port) NetError!usize receives one datagram, writes the payload into buf,
// and reports the source address/port through the out-params. It returns 0 for
// a zero-length datagram. The IpAddr type is module-visible to callers (Z98
// does not gate top-level decls on `pub`), so the fixture declares storage of
// that type directly.
//
// GREEN (contract): deterministic byte-exact stdout `udp recvfrom ok\n`.
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4143;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, "hello") catch @panic("send");

    var buf: [32]u8 = undefined;
    var addr: net.IpAddr = undefined;
    var port: u16 = 0;
    const n = net.udpRecvFrom(&s, buf[0..], &addr, &port) catch @panic("recv");
    ck(n == 5, "recv length");
    ck(buf[0] == 'h' and buf[4] == 'o', "recv payload");
    ck(addr.a == 127 and addr.b == 0 and addr.c == 0 and addr.d == 1, "recv addr");
    ck(port == PORT, "recv source port");

    net.close(s);
    net.cleanup();
    io.write("udp recvfrom ok\n");
}
