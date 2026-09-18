// stdlib_net_udp_stress_xmod — STDLIB std_net (L3) hand-written stress table.
//
// No PRNG: every payload is an explicit, deterministic formula. The fixture
// binds one fixed loopback UDP port and sends each datagram to itself, so the
// send and receive paths are exercised on one socket and the datagram
// boundaries are exact (one sendto == one recvfrom). Stresses:
//   - the maximum IPv4 UDP payload (65507 bytes) delivered intact and
//     byte-exact; the source port is the bound port.
//   - a zero-length datagram: udpRecvFrom returns 0, not an error.
//   - truncation: a 100-byte datagram received into a 10-byte buffer returns
//     buf.len (10) and the leading prefix, with the source out-params still
//     populated (POSIX silently truncates; WinSock normalizes WSAEMSGSIZE).
//
// GREEN (contract): deterministic byte-exact stdout `udp stress ok\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4148;
const MAXDG: usize = 65507;

var g_tx: [MAXDG]u8 = undefined;
var g_rx: [MAXDG]u8 = undefined;
var g_small: [100]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");

    var i: usize = 0;
    while (i < MAXDG) : (i += 1) {
        g_tx[i] = @intCast(u8, (i * 17 + 9) % 256);
    }
    i = 0;
    while (i < 100) : (i += 1) {
        g_small[i] = @intCast(u8, i);
    }

    var addr: net.IpAddr = undefined;
    var port: u16 = 0;

    // --- maximum datagram ---------------------------------------------------
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, g_tx[0..MAXDG]) catch @panic("send max");
    const n = net.udpRecvFrom(&s, g_rx[0..MAXDG], &addr, &port) catch @panic("recv max");
    ck(n == MAXDG, "max datagram length");
    ck(port == PORT, "max datagram source port");
    i = 0;
    while (i < MAXDG) : (i += 1) {
        ck(g_rx[i] == g_tx[i], "max datagram byte");
    }

    // --- zero-length datagram ----------------------------------------------
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, "") catch @panic("send zero");
    const z = net.udpRecvFrom(&s, g_rx[0..16], &addr, &port) catch @panic("recv zero");
    ck(z == 0, "zero-length datagram returns 0");

    // --- truncation ---------------------------------------------------------
    net.udpSendTo(&s, .{ .a = 127, .b = 0, .c = 0, .d = 1 }, PORT, g_small[0..]) catch @panic("send trunc");
    const t = net.udpRecvFrom(&s, g_rx[0..10], &addr, &port) catch @panic("recv trunc");
    ck(t == 10, "truncated length == buffer length");
    i = 0;
    while (i < 10) : (i += 1) {
        ck(g_rx[i] == g_small[i], "truncated prefix");
    }
    ck(port == PORT, "truncated source port");

    net.close(s);
    net.cleanup();
    io.write("udp stress ok\n");
}
