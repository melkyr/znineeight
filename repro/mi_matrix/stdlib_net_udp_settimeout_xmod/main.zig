// stdlib_net_udp_settimeout_xmod — STDLIB std_net (L3) udpSetTimeout GREEN
// fixture (the blueprint's "timeout" shape).
//
// Contract (blueprint §3 L3, operator m1432): udpSetTimeout(s, ms) sets the
// receive timeout; a subsequent udpRecvFrom with no datagram returns
// error.Timeout. WinSock reports the expiry as WSAETIMEDOUT; POSIX
// SO_RCVTIMEO expiry surfaces as EAGAIN/EWOULDBLOCK, which udpRecvFrom
// normalizes to Timeout (a blocking socket's only EAGAIN source is the
// timeout).
//
// GREEN (contract): deterministic byte-exact stdout `udp timeout ok\n`.
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4144;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn recvTimeout(s: *net.Socket, buf: []u8, addr: *net.IpAddr, port: *u16) bool {
    _ = net.udpRecvFrom(s, buf, addr, port) catch |e| {
        if (e == error.Timeout) return true;
        return false;
    };
    return false;
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");
    net.udpSetTimeout(&s, @intCast(u32, 150)) catch @panic("udpSetTimeout");

    var buf: [32]u8 = undefined;
    var addr: net.IpAddr = undefined;
    var port: u16 = 0;
    ck(recvTimeout(&s, buf[0..], &addr, &port), "recv returns Timeout");

    net.close(s);
    net.cleanup();
    io.write("udp timeout ok\n");
}
