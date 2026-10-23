const std = @import("std");
const tcp = @import("std_tcpip.zig");

const LOCAL: u32 = 0x0A000001;
const PEER: u32 = 0x0A000002;
const DNS: u32 = 0x0A000003;
const DNS_PORT: u16 = 40000;
const MAX_PKT: usize = 2048;

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

fn buildPeerUdp(out: []u8, src_ip: u32, dst_ip: u32, src_port: u16, dst_port: u16, payload: []const u8) usize {
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

fn dnsNameWire(out: []u8, off: usize, name: []const u8) usize {
    var n = off;
    var i: usize = 0;
    while (i < name.len) {
        var j = i;
        while (j < name.len and name[j] != '.') j += 1;
        const l = j - i;
        if (l == 0) {
            if (j == name.len) break;
            return 0;
        }
        out[n] = @intCast(u8, l);
        n += 1;
        var k: usize = 0;
        while (k < l) : (k += 1) out[n + k] = name[i + k];
        n += l;
        i = j;
        if (i < name.len and name[i] == '.') i += 1;
        if (i == name.len) break;
    }
    out[n] = 0;
    return n + 1;
}

fn buildDnsQuery(out: []u8, id: u16, name: []const u8) usize {
    store16(out, 0, id);
    store16(out, 2, 0x0100);
    store16(out, 4, 1);
    store16(out, 6, 0);
    store16(out, 8, 0);
    store16(out, 10, 0);
    var n = dnsNameWire(out, 12, name);
    if (n == 0) return 0;
    store16(out, n, 1);
    store16(out, n + 2, 1);
    return n + 4;
}

fn buildDnsResp(out: []u8, id: u16, name: []const u8, ip: u32, flags: u16, ancount: u16, rdlen: u16, actual: usize, trunc: bool) usize {
    store16(out, 0, id);
    store16(out, 2, flags);
    store16(out, 4, 1);
    store16(out, 6, ancount);
    store16(out, 8, 0);
    store16(out, 10, 0);
    var n = dnsNameWire(out, 12, name);
    if (n == 0) return 0;
    store16(out, n, 1);
    store16(out, n + 2, 1);
    n += 4;
    var a: u16 = 0;
    while (a < ancount) : (a += 1) {
        out[n] = 0xC0;
        out[n + 1] = 0x0C;
        n += 2;
        store16(out, n, 1);
        store16(out, n + 2, 1);
        store32(out, n + 4, 300);
        store16(out, n + 8, rdlen);
        n += 10;
        store32(out, n, ip);
        n += actual;
    }
    if (trunc and n > 2) n -= 2;
    return n;
}

fn buildDnsRespDiffName(out: []u8, id: u16, qname: []const u8, ans_name: []const u8, ip: u32) usize {
    store16(out, 0, id);
    store16(out, 2, 0x8180);
    store16(out, 4, 1);
    store16(out, 6, 1);
    store16(out, 8, 0);
    store16(out, 10, 0);
    var n = dnsNameWire(out, 12, qname);
    if (n == 0) return 0;
    store16(out, n, 1);
    store16(out, n + 2, 1);
    n += 4;
    n = dnsNameWire(out, n, ans_name);
    if (n == 0) return 0;
    store16(out, n, 1);
    store16(out, n + 2, 1);
    store32(out, n + 4, 300);
    store16(out, n + 8, 4);
    n += 10;
    store32(out, n, ip);
    return n + 4;
}

fn buildDnsRespCname(out: []u8, id: u16, qname: []const u8, target: []const u8) usize {
    store16(out, 0, id);
    store16(out, 2, 0x8180);
    store16(out, 4, 1);
    store16(out, 6, 1);
    store16(out, 8, 0);
    store16(out, 10, 0);
    var n = dnsNameWire(out, 12, qname);
    if (n == 0) return 0;
    store16(out, n, 1);
    store16(out, n + 2, 1);
    n += 4;
    out[n] = 0xC0;
    out[n + 1] = 0x0C;
    n += 2;
    store16(out, n, 5);
    store16(out, n + 2, 1);
    store32(out, n + 4, 300);
    const rdpos = n + 8;
    const rstart = n + 10;
    const rend = dnsNameWire(out, rstart, target);
    if (rend == 0) return 0;
    store16(out, rdpos, @intCast(u16, rend - rstart));
    return rend;
}

fn checkQuery(p: []const u8, name: []const u8) u16 {
    ck(ipProto(p) == 17, "dns proto udp");
    ck(load16(p, 20) == DNS_PORT, "dns source port");
    ck(load16(p, 22) == 53, "dns destination port");
    ck(load32(p, 12) == LOCAL, "dns source ip");
    ck(load32(p, 16) == DNS, "dns destination ip");
    const seg = udpSeg(p);
    ck(foldCk(pseudoSum(LOCAL, DNS, seg.len, 17) + sumWords(seg)) == 0xFFFF, "dns udp checksum");
    const payload = udpPayload(p);
    const id = load16(payload, 0);
    var exp: [512]u8 = undefined;
    const el = buildDnsQuery(exp[0..], id, name);
    ck(el > 0, "expected dns query");
    eqBytes(payload, exp[0..el], "dns query byte-exact");
    return id;
}

fn dnsStart(s: *tcp.TcpipStack, name: []const u8) bool {
    var ip: u32 = 0;
    tcp.dnsResolve(s, name, &ip) catch |err| {
        return err == error.Timeout;
    };
    return false;
}

fn dnsGet(s: *tcp.TcpipStack, name: []const u8) ?u32 {
    var ip: u32 = 0;
    tcp.dnsResolve(s, name, &ip) catch return null;
    return ip;
}

fn dnsFailed(s: *tcp.TcpipStack, name: []const u8) bool {
    var ip: u32 = 0;
    tcp.dnsResolve(s, name, &ip) catch |err| {
        return err == error.DnsFailed;
    };
    return false;
}

fn testQueryAnswer(s: *tcp.TcpipStack, now: u64) void {
    ck(dnsStart(s, "example.com"), "dns start pending");
    ck(dnsGet(s, "example.com") == null, "dns pending get null");

    var n = drive(s, now, null);
    ck(n > 0, "dns query emitted");
    ck(n <= 1400, "dns query <= mtu");
    const id = checkQuery(g_pkt[0..n], "example.com");

    var rp: [MAX_PKT]u8 = undefined;
    var m = buildDnsResp(rp[0..], id, "example.com", 0x0A000009, 0x8180, 1, 4, 4, false);
    var pp: [MAX_PKT]u8 = undefined;
    var pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 1, pp[0..pl]);
    ck(n == 0, "dns answer no send");
    ck(g_done, "dns success terminal done");
    const ip = dnsGet(s, "example.com");
    if (ip) |v| { ck(v == 0x0A000009, "dns A record parsed"); } else { ck(false, "dns A record missing"); }

    ck(dnsStart(s, "two.example"), "dns second start");
    n = drive(s, now + 2, null);
    ck(n > 0, "dns second query emitted");
    const id2 = checkQuery(g_pkt[0..n], "two.example");
    m = buildDnsResp(rp[0..], id2, "two.example", 0x0A00000A, 0x8180, 1, 4, 4, false);
    pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 3, pp[0..pl]);
    ck(n == 0, "dns second answer no send");
    ck(g_done, "dns second terminal done");
    const ip2 = dnsGet(s, "two.example");
    if (ip2) |v| { ck(v == 0x0A00000A, "dns second A record"); } else { ck(false, "dns second A record missing"); }

    ck(dnsStart(s, "case.example"), "dns case start");
    n = drive(s, now + 4, null);
    ck(n > 0, "dns case query emitted");
    const id3 = checkQuery(g_pkt[0..n], "case.example");
    m = buildDnsResp(rp[0..], id3, "CASE.EXAMPLE", 0x0A000010, 0x8180, 1, 4, 4, false);
    pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 5, pp[0..pl]);
    ck(n == 0, "dns case answer no send");
    ck(g_done, "dns case terminal done");
    const ip3 = dnsGet(s, "case.example");
    if (ip3) |v| { ck(v == 0x0A000010, "dns case-insensitive QNAME"); } else { ck(false, "dns case answer missing"); }
}

fn testMismatch(s: *tcp.TcpipStack, now: u64) void {
    ck(dnsStart(s, "id.example"), "dns mismatch start");
    var n = drive(s, now, null);
    ck(n > 0, "dns mismatch query");
    const id = checkQuery(g_pkt[0..n], "id.example");

    var rp: [MAX_PKT]u8 = undefined;
    var pp: [MAX_PKT]u8 = undefined;
    var m = buildDnsResp(rp[0..], id +% 1, "id.example", 0x0A00000B, 0x8180, 1, 4, 4, false);
    var pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 1, pp[0..pl]);
    ck(n == 0, "dns mismatched id ignored");
    ck(!g_done, "dns bad id not terminal");
    ck(dnsGet(s, "id.example") == null, "dns still pending after bad id");

    m = buildDnsResp(rp[0..], id, "id.example", 0x0A00000B, 0x8180, 1, 4, 4, false);
    pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 2, pp[0..pl]);
    ck(n == 0, "dns correct id no send");
    ck(g_done, "dns correct id terminal done");
    const ip = dnsGet(s, "id.example");
    if (ip) |v| { ck(v == 0x0A00000B, "dns correct id answer"); } else { ck(false, "dns correct id answer missing"); }
}

fn testQname(s: *tcp.TcpipStack, now: u64) void {
    ck(dnsStart(s, "qname.example"), "dns qname start");
    var n = drive(s, now, null);
    ck(n > 0, "dns qname query");
    const id = checkQuery(g_pkt[0..n], "qname.example");

    var rp: [MAX_PKT]u8 = undefined;
    var pp: [MAX_PKT]u8 = undefined;
    const m = buildDnsRespDiffName(rp[0..], id, "qname.example", "evil.example", 0x0A00000F);
    const pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 1, pp[0..pl]);
    ck(n == 0, "dns qname mismatch consumed");
    ck(g_done, "dns qname mismatch terminal done");
    ck(dnsFailed(s, "qname.example"), "dns qname mismatch DnsFailed");
}

fn testCname(s: *tcp.TcpipStack, now: u64) void {
    ck(dnsStart(s, "alias.example"), "dns cname start");
    var n = drive(s, now, null);
    ck(n > 0, "dns cname query");
    const id = checkQuery(g_pkt[0..n], "alias.example");

    var rp: [MAX_PKT]u8 = undefined;
    var pp: [MAX_PKT]u8 = undefined;
    const m = buildDnsRespCname(rp[0..], id, "alias.example", "real.example");
    const pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 1, pp[0..pl]);
    ck(n == 0, "dns cname consumed");
    ck(g_done, "dns cname terminal done");
    ck(dnsFailed(s, "alias.example"), "dns cname DnsFailed");
}

fn testMalformed(s: *tcp.TcpipStack, now: u64) void {
    var rp: [MAX_PKT]u8 = undefined;
    var pp: [MAX_PKT]u8 = undefined;

    ck(dnsStart(s, "none.example"), "dns no-answer start");
    var n = drive(s, now, null);
    ck(n > 0, "dns no-answer query");
    var id = checkQuery(g_pkt[0..n], "none.example");
    var m = buildDnsResp(rp[0..], id, "none.example", 0, 0x8180, 0, 0, 0, false);
    var pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 1, pp[0..pl]);
    ck(n == 0, "dns no-answer consumed");
    ck(g_done, "dns no-answer terminal done");
    ck(dnsFailed(s, "none.example"), "dns no-answer DnsFailed");

    ck(dnsStart(s, "rdlen.example"), "dns rdlen start");
    n = drive(s, now + 2, null);
    ck(n > 0, "dns rdlen query");
    id = checkQuery(g_pkt[0..n], "rdlen.example");
    m = buildDnsResp(rp[0..], id, "rdlen.example", 0x0A00000C, 0x8180, 1, 3, 3, false);
    pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 3, pp[0..pl]);
    ck(n == 0, "dns rdlen consumed");
    ck(g_done, "dns rdlen terminal done");
    ck(dnsFailed(s, "rdlen.example"), "dns rdlen DnsFailed");

    ck(dnsStart(s, "trunc.example"), "dns truncated start");
    n = drive(s, now + 4, null);
    ck(n > 0, "dns truncated query");
    id = checkQuery(g_pkt[0..n], "trunc.example");
    m = buildDnsResp(rp[0..], id, "trunc.example", 0x0A00000D, 0x8180, 1, 4, 4, true);
    pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 5, pp[0..pl]);
    ck(n == 0, "dns truncated consumed");
    ck(g_done, "dns truncated terminal done");
    ck(dnsFailed(s, "trunc.example"), "dns truncated DnsFailed");

    ck(dnsStart(s, "rcode.example"), "dns rcode start");
    n = drive(s, now + 6, null);
    ck(n > 0, "dns rcode query");
    id = checkQuery(g_pkt[0..n], "rcode.example");
    m = buildDnsResp(rp[0..], id, "rcode.example", 0x0A00000E, 0x8183, 1, 4, 4, false);
    pl = buildPeerUdp(pp[0..], DNS, LOCAL, 53, DNS_PORT, rp[0..m]);
    g_done = false;
    n = drive(s, now + 7, pp[0..pl]);
    ck(n == 0, "dns rcode consumed");
    ck(g_done, "dns rcode terminal done");
    ck(dnsFailed(s, "rcode.example"), "dns rcode DnsFailed");
}

fn testRetry(s: *tcp.TcpipStack, now: u64) void {
    ck(dnsStart(s, "retry.example"), "dns retry start");
    var n = drive(s, now, null);
    ck(n > 0, "dns retry send 1");
    const id = checkQuery(g_pkt[0..n], "retry.example");
    var first: [MAX_PKT]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) first[i] = g_pkt[i];

    n = drive(s, now + 999, null);
    ck(n == 0, "dns retry wait before interval");
    n = drive(s, now + 1000, null);
    ck(n > 0, "dns retry send 2");
    ck(checkQuery(g_pkt[0..n], "retry.example") == id, "dns retry id stable");
    eqBytes(udpPayload(first[0..]), udpPayload(g_pkt[0..n]), "dns retry bytes stable");

    n = drive(s, now + 1999, null);
    ck(n == 0, "dns retry wait 2");
    n = drive(s, now + 2000, null);
    ck(n > 0, "dns retry send 3");
    ck(checkQuery(g_pkt[0..n], "retry.example") == id, "dns retry id stable 3");

    g_done = false;
    n = drive(s, now + 3000, null);
    ck(n == 0, "dns retry stops after max tries");
    ck(g_done, "dns timeout terminal done");
    ck(dnsFailed(s, "retry.example"), "dns timeout DnsFailed");
    g_done = false;
    n = drive(s, now + 3001, null);
    ck(n == 0, "dns no fresh query after terminal");
    ck(g_done, "dns idle done after terminal consume");
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

    testQueryAnswer(st, 1000);
    testMismatch(st, 10000);
    testQname(st, 15000);
    testCname(st, 18000);
    testMalformed(st, 20000);
    testRetry(st, 30000);

    if (g_fail == 0) {
        std.io.write("tcpip dns ok\n");
    } else {
        std.io.write("tcpip dns FAIL\n");
    }
}
