// stdlib_net_udp_truncation_xmod — STDLIB std_net (L3) truncation behavior.
//
// Contract (blueprint §3 L3, operator m1432): when the datagram is larger than
// buf, udpRecvFrom copies buf.len bytes and returns buf.len; it does not report
// the original datagram length. POSIX recvfrom truncates silently; WinSock
// reports WSAEMSGSIZE after copying the truncated prefix, which udpRecvFrom
// normalizes to buf.len. Either way truncation is not detectable through this
// API (documented; the remainder of the datagram is discarded). The source
// out_addr/out_port are populated on both paths (WinSock fills the sockaddr
// even on WSAEMSGSIZE), so the fixture asserts them to pin the parity.
//
// GREEN (contract): deterministic byte-exact stdout `udp truncation ok\n`.
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4147;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, "0123456789") catch @panic("send");

    var buf: [4]u8 = undefined;
    var addr: net.IpAddr = undefined;
    var port: u16 = 0;
    const n = net.udpRecvFrom(&s, buf[0..], &addr, &port) catch @panic("recv");
    ck(n == 4, "truncated length == buffer length");
    ck(buf[0] == '0' and buf[3] == '3', "truncated prefix");
    ck(addr.a == 127 and addr.b == 0 and addr.c == 0 and addr.d == 1, "truncated source addr");
    ck(port == PORT, "truncated source port");

    net.close(s);
    net.cleanup();
    io.write("udp truncation ok\n");
}
