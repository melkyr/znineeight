const std = @import("std");
const tcp = @import("std_tcpip.zig");

const LOCAL: u32 = 0x0A000001;
const PEER: u32 = 0x0A000002;
const DNS: u32 = 0x0A000003;
const UDP_PORT: u16 = 5353;
const PEER_PORT: u16 = 1234;
const MAX_PKT: usize = 2048;
const ICMP_ID: u16 = 0x5A39;

var g_out: [MAX_PKT]u8 = undefined;
var g_pkt: [MAX_PKT]u8 = undefined;
var g_pkt_len: usize = 0;
var g_done: bool = false;
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn eqBytes(a: []const u8, b: []const u8, what: []const u8) void {
    ck(a.len == b.len, what);
    var i: usize = 0;
    while (i < a.len and i < b.len) : (i += 1) ck(a[i] == b[i], what);
}

fn load16(p: []const u8, off: usize) u16 {
    return (@intCast(u16, p[off]) << 8) | @intCast(u16, p[off + 1]);
}

fn load32(p: []const u8, off: usize) u32 {
    return (@intCast(u32, p[off]) << 24) |
        (@intCast(u32, p[off + 1]) << 16) |
        (@intCast(u32, p[off + 2]) << 8) |
        @intCast(u32, p[off + 3]);
}

fn store16(p: []u8, off: usize, v: u16) void {
    p[off] = @intCast(u8, v >> 8);
    p[off + 1] = @intCast(u8, v & 0xFF);
}

fn store32(p: []u8, off: usize, v: u32) void {
    p[off] = @intCast(u8, v >> 24);
    p[off + 1] = @intCast(u8, (v >> 16) & 0xFF);
    p[off + 2] = @intCast(u8, (v >> 8) & 0xFF);
    p[off + 3] = @intCast(u8, v & 0xFF);
}

fn sumWords(data: []const u8) u32 {
    var sum: u32 = 0;
    var i: usize = 0;
    while (i + 1 < data.len) : (i += 2) {
        sum += (@intCast(u32, data[i]) << 8) | @intCast(u32, data[i + 1]);
        if (sum > 0xFFFF) sum = (sum & 0xFFFF) + (sum >> 16);
    }
    if (i < data.len) sum += @intCast(u32, data[i]) << 8;
    return sum;
}

fn foldCk(sum0: u32) u16 {
    var sum = sum0;
    while ((sum >> 16) != 0) sum = (sum & 0xFFFF) + (sum >> 16);
    return @intCast(u16, sum & 0xFFFF);
}

fn ipCk(h: []const u8) u16 {
    return ~foldCk(sumWords(h));
}

fn pseudoSum(src: u32, dst: u32, n: usize, proto: u8) u32 {
    var sum: u32 = 0;
    sum += (src >> 16) & 0xFFFF;
    sum += src & 0xFFFF;
    sum += (dst >> 16) & 0xFFFF;
    sum += dst & 0xFFFF;
    sum += @intCast(u32, proto);
    sum += @intCast(u32, n);
    return sum;
}

fn ipTotal(p: []const u8) usize {
    return @intCast(usize, load16(p, 2));
}

fn ipProto(p: []const u8) u8 {
    return p[9];
}

fn udpSeg(p: []const u8) []const u8 {
    return p[20..ipTotal(p)];
}

fn udpPayload(p: []const u8) []const u8 {
    return p[28..ipTotal(p)];
}

fn icmpMsg(p: []const u8) []const u8 {
    return p[20..ipTotal(p)];
}

fn validateIp(p: []const u8) void {
    ck(p.len >= 20, "min ip");
    ck((p[0] >> 4) == 4, "ip version");
    ck((p[0] & 0x0F) == 5, "ip ihl");
    ck(ipTotal(p) == p.len, "ip total");
    ck(foldCk(sumWords(p[0..20])) == 0xFFFF, "ip checksum");
}

fn udpCk(src: u32, dst: u32, seg: []const u8) u16 {
    return ~foldCk(pseudoSum(src, dst, seg.len, 17) + sumWords(seg));
}

fn icmpCk(msg: []const u8) u16 {
    return ~foldCk(sumWords(msg));
}

fn buildPeerUdpEx(out: []u8, src_ip: u32, dst_ip: u32, src_port: u16, dst_port: u16, payload: []const u8, bad_ck: bool) usize {
    const total = 20 + 8 + payload.len;
    var i: usize = 0;
    while (i < total) : (i += 1) out[i] = 0;
    out[0] = 0x45;
    store16(out, 2, @intCast(u16, total));
    store16(out, 4, 0xBEEF);
    store16(out, 6, 0x4000);
    out[8] = 64;
    out[9] = 17;
    store32(out, 12, src_ip);
    store32(out, 16, dst_ip);
    store16(out, 10, ipCk(out[0..20]));
    store16(out, 20, src_port);
    store16(out, 22, dst_port);
    store16(out, 24, @intCast(u16, 8 + payload.len));
    store16(out, 26, 0);
    i = 0;
    while (i < payload.len) : (i += 1) out[28 + i] = payload[i];
    store16(out, 26, udpCk(src_ip, dst_ip, out[20..total]));
    if (bad_ck) out[26] = out[26] ^ 0x01;
    return total;
}

fn buildPeerUdp(out: []u8, src_ip: u32, dst_ip: u32, src_port: u16, dst_port: u16, payload: []const u8) usize {
    return buildPeerUdpEx(out, src_ip, dst_ip, src_port, dst_port, payload, false);
}

fn buildPeerIcmp(out: []u8, src_ip: u32, dst_ip: u32, typ: u8, code: u8, id: u16, seq: u16, payload: []const u8, bad_ck: bool) usize {
    const total = 20 + 8 + payload.len;
    var i: usize = 0;
    while (i < total) : (i += 1) out[i] = 0;
    out[0] = 0x45;
    store16(out, 2, @intCast(u16, total));
    store16(out, 4, 0xBEEF);
    store16(out, 6, 0x4000);
    out[8] = 64;
    out[9] = 1;
    store32(out, 12, src_ip);
    store32(out, 16, dst_ip);
    store16(out, 10, ipCk(out[0..20]));
    out[20] = typ;
    out[21] = code;
    store16(out, 24, id);
    store16(out, 26, seq);
    i = 0;
    while (i < payload.len) : (i += 1) out[28 + i] = payload[i];
    store16(out, 22, icmpCk(out[20..total]));
    if (bad_ck) out[22] = out[22] ^ 0x01;
    return total;
}

fn drive(s: *tcp.TcpipStack, now: u64, rx: ?[]const u8) usize {
    var input = rx;
    while (true) {
        const act = tcp.tcpipPoll(s, now, input, g_out[0..]) catch @panic("poll");
        input = null;
        switch (act) {
            .send_pkt => |pkt| {
                ck(pkt.len <= MAX_PKT, "pkt cap");
                var i: usize = 0;
                while (i < pkt.len) : (i += 1) g_pkt[i] = pkt[i];
                g_pkt_len = pkt.len;
                validateIp(g_pkt[0..g_pkt_len]);
                return g_pkt_len;
            },
            .wait => return 0,
            .done => {
                g_done = true;
                return 0;
            },
            .connected => {},
            .data => {},
            .closed => {},
            .failed => {},
            else => ck(false, "unknown action"),
        }
    }
    return 0;
}

fn pollCorrupt(s: *tcp.TcpipStack, now: u64, pkt: []const u8) bool {
    const act = tcp.tcpipPoll(s, now, pkt, g_out[0..]) catch |err| {
        return err == error.Corrupt;
    };
    _ = act;
    return false;
}

fn testUdp(s: *tcp.TcpipStack, now: u64) void {
    const id = tcp.udpOpen(s, UDP_PORT) catch @panic("udp open");
    ck(id > 0, "udp id");

    const msg = "udp hello";
    tcp.udpSendTo(s, id, PEER, PEER_PORT, msg) catch @panic("udp send");
    var n = drive(s, now, null);
    ck(n > 0, "udp datagram emitted");
    ck(ipProto(g_pkt[0..n]) == 17, "udp proto");
    ck(ipTotal(g_pkt[0..n]) <= 1400, "udp <= mtu");
    ck(load32(g_pkt[0..n], 12) == LOCAL, "udp src ip");
    ck(load32(g_pkt[0..n], 16) == PEER, "udp dst ip");
    ck(load16(g_pkt[0..n], 20) == UDP_PORT, "udp src port");
    ck(load16(g_pkt[0..n], 22) == PEER_PORT, "udp dst port");
    eqBytes(udpPayload(g_pkt[0..n]), msg, "udp payload exact");
    ck(foldCk(pseudoSum(LOCAL, PEER, udpSeg(g_pkt[0..n]).len, 17) + sumWords(udpSeg(g_pkt[0..n]))) == 0xFFFF, "udp checksum");

    n = drive(s, now + 1, null);
    ck(n == 0, "udp idle after send");

    var pp: [MAX_PKT]u8 = undefined;
    var m = buildPeerUdp(pp[0..], PEER, LOCAL, PEER_PORT, UDP_PORT, "udp reply");
    n = drive(s, now + 2, pp[0..m]);
    ck(n == 0, "udp reply acked");
    var rb: [64]u8 = undefined;
    var rip: u32 = 0;
    var rport: u16 = 0;
    var rn = tcp.udpRecvFrom(s, id, rb[0..], &rip, &rport) catch @panic("udp recv");
    ck(rn == 9, "udp recv length");
    eqBytes(rb[0..rn], "udp reply", "udp reply exact");
    ck(rip == PEER, "udp reply ip");
    ck(rport == PEER_PORT, "udp reply port");

    tcp.udpSendTo(s, id, PEER, PEER_PORT, "") catch @panic("udp send zero");
    n = drive(s, now + 3, null);
    ck(n == 28, "udp zero datagram length");
    ck(udpPayload(g_pkt[0..n]).len == 0, "udp zero payload");

    m = buildPeerUdp(pp[0..], PEER, LOCAL, PEER_PORT, UDP_PORT, "");
    n = drive(s, now + 4, pp[0..m]);
    ck(n == 0, "udp zero reply acked");
    rip = 0;
    rport = 0;
    rn = tcp.udpRecvFrom(s, id, rb[0..], &rip, &rport) catch @panic("udp recv zero");
    ck(rn == 0, "udp zero recv length");
    ck(rip == PEER, "udp zero reply ip");
    ck(rport == PEER_PORT, "udp zero reply port");

    m = buildPeerUdp(pp[0..], PEER, LOCAL, PEER_PORT, UDP_PORT, "0123456789");
    n = drive(s, now + 5, pp[0..m]);
    ck(n == 0, "udp trunc reply acked");
    var small: [4]u8 = undefined;
    rn = tcp.udpRecvFrom(s, id, small[0..], &rip, &rport) catch @panic("udp recv trunc");
    ck(rn == 4, "udp truncation length");
    eqBytes(small[0..rn], "0123", "udp truncation bytes");

    var big: [1400]u8 = undefined;
    var i: usize = 0;
    while (i < big.len) : (i += 1) big[i] = 0x41;
    tcp.udpSendTo(s, id, PEER, PEER_PORT, big[0..]) catch |err| {
        ck(err == error.OutputTooSmall, "udp oversize OutputTooSmall");
    };
    tcp.udpSendTo(s, id, 0, PEER_PORT, "x") catch |err| {
        ck(err == error.NoRoute, "udp no route");
    };

    m = buildPeerUdpEx(pp[0..], PEER, LOCAL, PEER_PORT, UDP_PORT, "bad", true);
    ck(pollCorrupt(s, now + 6, pp[0..m]), "udp bad checksum Corrupt");

    var maxp: [1372]u8 = undefined;
    i = 0;
    while (i < maxp.len) : (i += 1) maxp[i] = @intCast(u8, i & 0xFF);
    tcp.udpSendTo(s, id, PEER, PEER_PORT, maxp[0..]) catch @panic("udp max send");
    n = drive(s, now + 7, null);
    ck(n == 1400, "udp max datagram 1400");
    eqBytes(udpPayload(g_pkt[0..n]), maxp[0..], "udp max payload exact");

    var bad: [64]u8 = undefined;
    m = buildPeerUdp(pp[0..], PEER, LOCAL, PEER_PORT, UDP_PORT, "ignore");
    var j: usize = 0;
    while (j < m) : (j += 1) bad[j] = pp[j];
    store32(bad[0..], 16, 0x0A0000FE);
    store16(bad[0..], 10, 0);
    store16(bad[0..], 10, ipCk(bad[0..20]));
    ck(!pollCorrupt(s, now + 8, bad[0..m]), "udp wrong dst ignored");
    const wrong_n = tcp.udpRecvFrom(s, id, rb[0..], &rip, &rport) catch @panic("udp recv wrong dst");
    ck(wrong_n == 0, "udp wrong dst no data");
}

fn icmpStart(s: *tcp.TcpipStack, ip: u32, now: u64) bool {
    const r = tcp.icmpPing(s, ip, now) catch |err| {
        return err == error.Timeout;
    };
    _ = r;
    return false;
}

fn icmpGet(s: *tcp.TcpipStack, ip: u32, now: u64) ?u32 {
    const r = tcp.icmpPing(s, ip, now) catch return null;
    return r;
}

fn icmpSeq(p: []const u8) u16 {
    return load16(p, 26);
}

fn testIcmp(s: *tcp.TcpipStack, now: u64) void {
    ck(icmpStart(s, PEER, now), "icmp start pending");
    ck(icmpGet(s, PEER, now) == null, "icmp pending rtt null");

    var n = drive(s, now, null);
    ck(n > 0, "icmp echo emitted");
    ck(ipProto(g_pkt[0..n]) == 1, "icmp proto");
    ck(g_pkt[20] == 8, "icmp echo request");
    ck(g_pkt[21] == 0, "icmp code 0");
    ck(load16(g_pkt[0..n], 24) == ICMP_ID, "icmp id");
    const seq = icmpSeq(g_pkt[0..n]);
    ck(foldCk(sumWords(icmpMsg(g_pkt[0..n]))) == 0xFFFF, "icmp request checksum");
    ck(ipTotal(g_pkt[0..n]) == 20 + 8 + 8, "icmp request length");
    ck(load32(g_pkt[0..n], 16) == PEER, "icmp dst ip");

    var pp: [MAX_PKT]u8 = undefined;
    var m = buildPeerIcmp(pp[0..], PEER, LOCAL, 0, 0, ICMP_ID, seq, "z98reply", false);
    n = drive(s, now + 7, pp[0..m]);
    ck(n == 0, "icmp reply idle");
    const rtt = icmpGet(s, PEER, now + 7);
    if (rtt) |v| { ck(v == 7, "icmp rtt 7"); } else { ck(false, "icmp rtt missing"); }

    const t2 = now + 1000;
    ck(icmpStart(s, PEER, t2), "icmp retry start");
    n = drive(s, t2, null);
    ck(n > 0, "icmp retry first send");
    const seq2 = icmpSeq(g_pkt[0..n]);
    ck(icmpGet(s, PEER, t2) == null, "icmp retry pending");
    n = drive(s, t2 + 999, null);
    ck(n == 0, "icmp retry waits");
    n = drive(s, t2 + 1000, null);
    ck(n > 0, "icmp retry second send");
    ck(icmpSeq(g_pkt[0..n]) == seq2, "icmp retry same seq");

    m = buildPeerIcmp(pp[0..], PEER, LOCAL, 0, 0, ICMP_ID, seq2, "z98reply", false);
    n = drive(s, t2 + 1004, pp[0..m]);
    ck(n == 0, "icmp retry reply idle");
    const rtt2 = icmpGet(s, PEER, t2 + 1004);
    if (rtt2) |v| { ck(v == 4, "icmp retry rtt 4"); } else { ck(false, "icmp retry rtt missing"); }

    const t3 = now + 5000;
    ck(icmpStart(s, PEER, t3), "icmp timeout start");
    n = drive(s, t3, null);
    ck(n > 0, "icmp timeout send 1");
    n = drive(s, t3 + 1000, null);
    ck(n > 0, "icmp timeout send 2");
    n = drive(s, t3 + 2000, null);
    ck(n > 0, "icmp timeout send 3");
    n = drive(s, t3 + 3000, null);
    ck(n == 0, "icmp timeout stops after max tries");
    ck(icmpGet(s, PEER, t3 + 3000) == null, "icmp timeout error");

    m = buildPeerIcmp(pp[0..], PEER, LOCAL, 0, 0, ICMP_ID, 77, "z98reply", true);
    ck(pollCorrupt(s, now + 9000, pp[0..m]), "icmp bad checksum Corrupt");

    m = buildPeerIcmp(pp[0..], PEER, LOCAL, 0, 0, 0x1234, 99, "z98reply", false);
    ck(!pollCorrupt(s, now + 9001, pp[0..m]), "icmp wrong id ignored");
}

pub fn main() void {
    var arena_buf: [1048576]u8 = undefined;
    var ar = std.arena.init(arena_buf[0..]);
    var cfg = tcp.TcpipConfig{
        .ip = LOCAL,
        .netmask = 0xFFFFFF00,
        .gateway = PEER,
        .mtu = 1400,
        .dns_server = DNS,
        .max_sockets = 2,
    };
    var st = tcp.tcpipInit(&ar, &cfg) catch @panic("tcpip init");

    testUdp(st, 1000);
    testIcmp(st, 20000);

    if (g_fail == 0) {
        std.io.write("tcpip udp ok\n");
    } else {
        std.io.write("tcpip udp FAIL\n");
    }
}
