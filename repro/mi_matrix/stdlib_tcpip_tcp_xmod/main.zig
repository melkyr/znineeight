// stdlib_tcpip_tcp_xmod — STDLIB std_tcpip (Phase1 M7) IPv4 + TCP client fixture.
//
// Scripted packet exchange against the sans-I/O pump. Every peer datagram is
// built independently here (own IPv4/TCP checksum code) so the module's builder
// and parser are both exercised. Outgoing datagrams are validated for header
// length, IPv4 checksum, TCP pseudo-header checksum, seq/ack and payload.
//
// Scenarios:
//   - 3-way handshake (SYN with MSS option, SYN-ACK, final ACK) + connected
//   - client->peer data byte-exact (PSH|ACK seq/ack), peer->client data exact
//   - FIN close: local FIN, peer FIN|ACK, ACK, closed event
//   - RST -> failed event
//   - dropped ACK -> retransmission of the same seq after the 1 s RTO
//   - out-of-order peer segments buffered within the 8 KB window and delivered
//     in order; a segment beyond the window is not delivered; duplicates are
//     ACKed but not delivered twice
//   - cfg.mtu=1400 -> local MSS 1360 split of a 5 KB tcpSend
//     (1360/1360/1360/920), every emitted datagram <= 1400
//   - cfg.mtu=600 -> local MSS 560, 2xMSS tcpSend splits 560/560 and every
//     emitted datagram <= 600
//   - initial cwnd == MSS: with 2xMSS buffered only one segment goes out
//     before an ACK; the second is emitted after the ACK
//   - peer-advertised MSS 1200 clamps outgoing segments
//   - receive/send sequence + ACK wrap across 2^32
//   - arena OOM at init and no-free-socket -> OutOfMemory
//   - OutputTooSmall during FIN leaves the socket retryable
//   - out-of-window FIN (boundary off == 8192) rejected, then a valid FIN ->
//     closed
//   - malformed IPv4 and TCP checksums -> error.Corrupt
//
// GREEN (contract): deterministic byte-exact stdout `tcpip tcp ok\n` (RUNRC=0).
const std = @import("std");
const tcp = @import("std_tcpip.zig");

const LOCAL: u32 = 0x0A000001; // 10.0.0.1
const PEER: u32 = 0x0A000002; // 10.0.0.2
const PEER_PORT: u16 = 80;
const PEER_ISS: u32 = 0x50000000;

const MAX_PKT: usize = 2048;
const LOCAL_MSS: usize = 1360;

var g_out: [MAX_PKT]u8 = undefined;
var g_oom_buf: [262144]u8 = undefined;
var g_mtu_buf: [262144]u8 = undefined;
var g_pkt: [MAX_PKT]u8 = undefined;
var g_pkt_len: usize = 0;
var g_connected: i32 = -1;
var g_data: i32 = -1;
var g_closed: i32 = -1;
var g_failed: i32 = -1;
var g_done: bool = false;
var g_fail: u32 = 0;

const Conn = struct {
    id: u32,
    iss: u32,
    local_port: u16,
};

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

fn pseudoSum(src: u32, dst: u32, n: usize) u32 {
    var sum: u32 = 0;
    sum += (src >> 16) & 0xFFFF;
    sum += src & 0xFFFF;
    sum += (dst >> 16) & 0xFFFF;
    sum += dst & 0xFFFF;
    sum += 6;
    sum += @intCast(u32, n);
    return sum;
}

fn tcpCk(src: u32, dst: u32, seg: []const u8) u16 {
    return ~foldCk(pseudoSum(src, dst, seg.len) + sumWords(seg));
}

fn ipTotal(p: []const u8) usize {
    return @intCast(usize, load16(p, 2));
}

fn ipHdrLen(p: []const u8) usize {
    return @intCast(usize, p[0] & 0x0F) * 4;
}

fn tcpHdrLen(p: []const u8) usize {
    return @intCast(usize, p[ipHdrLen(p) + 12] >> 4) * 4;
}

fn pktSrcPort(p: []const u8) u16 {
    return load16(p, ipHdrLen(p));
}

fn pktDstPort(p: []const u8) u16 {
    return load16(p, ipHdrLen(p) + 2);
}

fn pktSeq(p: []const u8) u32 {
    return load32(p, ipHdrLen(p) + 4);
}

fn pktAck(p: []const u8) u32 {
    return load32(p, ipHdrLen(p) + 8);
}

fn pktFlags(p: []const u8) u8 {
    return p[ipHdrLen(p) + 13];
}

fn pktPayload(p: []const u8) []const u8 {
    return p[ipHdrLen(p) + tcpHdrLen(p) .. ipTotal(p)];
}

// MSS option (kind 2, len 4) from a SYN/SYN-ACK; 0 when absent.
fn pktSynMss(p: []const u8) u16 {
    const t = ipHdrLen(p);
    const end = t + tcpHdrLen(p);
    var i: usize = t + 20;
    while (i < end) {
        const kind = p[i];
        if (kind == 0) break;
        if (kind == 1) {
            i += 1;
            continue;
        }
        if (i + 1 >= end) break;
        const len: usize = @intCast(usize, p[i + 1]);
        if (len < 2 or i + len > end) break;
        if (kind == 2 and len == 4) return load16(p, i + 2);
        i += len;
    }
    return 0;
}

fn validatePkt(p: []const u8, mtu: usize) void {
    ck(p.len >= 20, "min ip");
    ck((p[0] >> 4) == 4, "ip version");
    ck(p.len <= mtu, "emitted datagram <= cfg.mtu");
    const ihl = ipHdrLen(p);
    ck(ihl == 20, "ihl 20");
    ck(ipTotal(p) == p.len, "ip total");
    ck(foldCk(sumWords(p[0..ihl])) == 0xFFFF, "ip checksum");
    const t = ihl;
    const doff = tcpHdrLen(p);
    ck(doff >= 20 and t + doff <= p.len, "tcp doff");
    const src = load32(p, 12);
    const dst = load32(p, 16);
    const seg = p[t..p.len];
    ck(foldCk(pseudoSum(src, dst, seg.len) + sumWords(seg)) == 0xFFFF, "tcp checksum");
}

fn buildPeerEx(out: []u8, src_ip: u32, dst_ip: u32, src_port: u16, dst_port: u16, seq: u32, ack: u32, flags: u8, payload: []const u8, mss: u16) usize {
    const opt_len: usize = if (mss != 0) 4 else 0;
    const tcp_hdr = 20 + opt_len;
    const total = 20 + tcp_hdr + payload.len;
    var i: usize = 0;
    while (i < total) : (i += 1) out[i] = 0;

    out[0] = 0x45;
    store16(out, 2, @intCast(u16, total));
    store16(out, 4, 0xBEEF);
    store16(out, 6, 0x4000);
    out[8] = 64;
    out[9] = 6;
    store32(out, 12, src_ip);
    store32(out, 16, dst_ip);
    store16(out, 10, ipCk(out[0..20]));

    const t = 20;
    store16(out, t, src_port);
    store16(out, t + 2, dst_port);
    store32(out, t + 4, seq);
    store32(out, t + 8, ack);
    out[t + 12] = @intCast(u8, (tcp_hdr / 4) << 4);
    out[t + 13] = flags;
    store16(out, t + 14, 8192);
    store16(out, t + 16, 0);
    store16(out, t + 18, 0);
    if (opt_len != 0) {
        out[t + 20] = 2;
        out[t + 21] = 4;
        store16(out, t + 22, mss);
    }

    i = 0;
    while (i < payload.len) : (i += 1) out[t + tcp_hdr + i] = payload[i];
    store16(out, t + 16, tcpCk(src_ip, dst_ip, out[t..total]));
    return total;
}

fn buildPeer(out: []u8, src_ip: u32, dst_ip: u32, src_port: u16, dst_port: u16, seq: u32, ack: u32, flags: u8, payload: []const u8) usize {
    return buildPeerEx(out, src_ip, dst_ip, src_port, dst_port, seq, ack, flags, payload, 0);
}

fn resetEvents() void {
    g_connected = -1;
    g_data = -1;
    g_closed = -1;
    g_failed = -1;
    g_done = false;
}

// Pump until a datagram is emitted (returns its length) or the stack asks for
// a wait/done (returns 0). Events seen on the way are recorded.
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
                validatePkt(g_pkt[0..g_pkt_len], @intCast(usize, s.cfg.mtu));
                return g_pkt_len;
            },
            .wait => return 0,
            .connected => |id| g_connected = @intCast(i32, id),
            .data => |id| g_data = @intCast(i32, id),
            .closed => |id| g_closed = @intCast(i32, id),
            .failed => |id| g_failed = @intCast(i32, id),
            .done => {
                g_done = true;
                return 0;
            },
            else => ck(false, "unknown action"),
        }
    }
    return 0;
}

fn slotOf(s: *tcp.TcpipStack, id: u32) usize {
    var i: usize = 0;
    while (i < s.socket_count) : (i += 1) {
        if (s.sockets[i].id == id) return i;
    }
    return 0;
}

// peer_mss = 0 means the peer advertises no MSS option (local MSS applies).
// client_iss = 0 keeps the stack's deterministic default ISS; otherwise the
// fixture overrides it before the SYN is emitted (sequence-wrap scenarios).
fn doConnectFull(s: *tcp.TcpipStack, now: u64, peer_mss: u16, peer_iss: u32, client_iss: u32) Conn {
    resetEvents();
    const id = tcp.tcpConnect(s, PEER, PEER_PORT) catch @panic("connect");
    if (client_iss != 0) {
        const si = slotOf(s, id);
        s.sockets[si].iss = client_iss;
        s.sockets[si].snd_una = client_iss;
        s.sockets[si].snd_nxt = client_iss;
    }

    var n = drive(s, now, null);
    ck(n > 0, "syn emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x02) != 0, "syn flag");
    ck((pktFlags(g_pkt[0..n]) & 0x10) == 0, "syn no ack");
    ck(pktSrcPort(g_pkt[0..n]) >= 49152, "ephemeral port");
    ck(pktDstPort(g_pkt[0..n]) == PEER_PORT, "syn dst port");
    ck(load32(g_pkt[0..n], 16) == PEER, "syn dst ip");
    ck(pktPayload(g_pkt[0..n]).len == 0, "syn payload empty");
    const want_mss: u16 = if (s.cfg.mtu <= 40) 1 else @intCast(u16, @intCast(usize, s.cfg.mtu) - 40);
    ck(pktSynMss(g_pkt[0..n]) == want_mss, "syn advertises local MSS");

    const iss = pktSeq(g_pkt[0..n]);
    if (client_iss != 0) ck(iss == client_iss, "client iss override");
    const lp = pktSrcPort(g_pkt[0..n]);

    var pp: [MAX_PKT]u8 = undefined;
    const m = buildPeerEx(pp[0..], PEER, LOCAL, PEER_PORT, lp, peer_iss, iss +% 1, 0x12, "", peer_mss);
    resetEvents();
    n = drive(s, now + 1, pp[0..m]);
    ck(n > 0, "handshake ack emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x10) != 0, "handshake ack flag");
    ck((pktFlags(g_pkt[0..n]) & 0x02) == 0, "handshake not syn");
    ck(pktSeq(g_pkt[0..n]) == iss +% 1, "handshake seq");
    ck(pktAck(g_pkt[0..n]) == peer_iss +% 1, "handshake ack no");

    resetEvents();
    n = drive(s, now + 2, null);
    ck(n == 0, "handshake idle");
    ck(g_connected == @intCast(i32, id), "connected event");
    ck(g_failed == -1, "connected not failed");

    return Conn{ .id = id, .iss = iss, .local_port = lp };
}

fn doConnectEx(s: *tcp.TcpipStack, now: u64, peer_mss: u16) Conn {
    return doConnectFull(s, now, peer_mss, PEER_ISS, 0);
}

fn doConnect(s: *tcp.TcpipStack, now: u64) Conn {
    return doConnectFull(s, now, 0, PEER_ISS, 0);
}

fn ackPacket(pp: []u8, c: Conn, peer_seq: u32, ack: u32) usize {
    return buildPeer(pp, PEER, LOCAL, PEER_PORT, c.local_port, peer_seq, ack, 0x10, "");
}

fn testBasic(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    const msg = "GET / HTTP/1.0\r\n\r\n";
    const sent = tcp.tcpSend(s, c.id, msg) catch @panic("send basic");
    ck(sent == msg.len, "send accepted all");

    resetEvents();
    var n = drive(s, now + 10, null);
    ck(n > 0, "client data emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x18) == 0x18, "data psh|ack");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1, "data seq");
    ck(pktAck(g_pkt[0..n]) == PEER_ISS +% 1, "data ack no");
    eqBytes(pktPayload(g_pkt[0..n]), msg, "client payload exact");
    const client_seq = pktSeq(g_pkt[0..n]);

    var pp: [MAX_PKT]u8 = undefined;
    var m = ackPacket(pp[0..], c, PEER_ISS +% 1, client_seq +% @intCast(u32, msg.len));
    resetEvents();
    n = drive(s, now + 20, pp[0..m]);
    ck(n == 0, "no send after data ack");
    ck(g_failed == -1, "data ack clean");

    const reply = "HTTP/1.0 200 OK\r\n\r\nhello";
    m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, PEER_ISS +% 1, client_seq +% @intCast(u32, msg.len), 0x18, reply);
    resetEvents();
    n = drive(s, now + 30, pp[0..m]);
    ck(n > 0, "peer data acked");
    ck(pktAck(g_pkt[0..n]) == PEER_ISS +% 1 +% @intCast(u32, reply.len), "peer data ack no");

    resetEvents();
    n = drive(s, now + 31, null);
    ck(n == 0, "peer data idle");
    ck(g_data == @intCast(i32, c.id), "data event");

    var rb: [256]u8 = undefined;
    const rn = tcp.tcpRecv(s, c.id, rb[0..]) catch @panic("recv basic");
    ck(rn == reply.len, "recv length");
    eqBytes(rb[0..rn], reply, "server payload exact");

    // tcpRecv opened the window; the next pump emits a window-update ACK.
    resetEvents();
    n = drive(s, now + 32, null);
    ck(n > 0, "window update emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x10) != 0, "window update ack");

    tcp.tcpClose(s, c.id) catch @panic("close basic");
    resetEvents();
    n = drive(s, now + 40, null);
    ck(n > 0, "fin emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x01) != 0, "fin flag");
    ck(pktSeq(g_pkt[0..n]) == client_seq +% @intCast(u32, msg.len), "fin seq");
    ck(pktAck(g_pkt[0..n]) == PEER_ISS +% 1 +% @intCast(u32, reply.len), "fin ack no");
    const fin_seq = pktSeq(g_pkt[0..n]);

    const peer_fin_seq = PEER_ISS +% 1 +% @intCast(u32, reply.len);
    m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, peer_fin_seq, fin_seq +% 1, 0x11, "");
    resetEvents();
    n = drive(s, now + 50, pp[0..m]);
    ck(n > 0, "fin acked");
    ck(pktAck(g_pkt[0..n]) == peer_fin_seq +% 1, "peer fin ack no");

    resetEvents();
    n = drive(s, now + 51, null);
    ck(n == 0, "close idle");
    ck(g_closed == @intCast(i32, c.id), "closed event");
}

fn testRst(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    var pp: [MAX_PKT]u8 = undefined;
    const m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, PEER_ISS +% 1, c.iss +% 1, 0x04, "");
    resetEvents();
    const n = drive(s, now + 1, pp[0..m]);
    ck(n == 0, "rst no send");
    ck(g_failed == @intCast(i32, c.id), "rst failed event");
}

fn testRetrans(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    const msg = "retransmit";
    const sent = tcp.tcpSend(s, c.id, msg) catch @panic("send retrans");
    ck(sent == msg.len, "retrans accepted");

    resetEvents();
    var n = drive(s, now + 10, null);
    ck(n > 0, "retrans original");
    const seq = pktSeq(g_pkt[0..n]);
    eqBytes(pktPayload(g_pkt[0..n]), msg, "retrans original payload");

    // ACK never arrives: after the fixed 1 s RTO the same seq is re-sent.
    resetEvents();
    n = drive(s, now + 10 + 1000, null);
    ck(n > 0, "retrans timeout send");
    ck(pktSeq(g_pkt[0..n]) == seq, "retrans same seq");
    ck((pktFlags(g_pkt[0..n]) & 0x10) != 0, "retrans ack flag");
    eqBytes(pktPayload(g_pkt[0..n]), msg, "retrans payload exact");

    var pp: [MAX_PKT]u8 = undefined;
    const m = ackPacket(pp[0..], c, PEER_ISS +% 1, seq +% @intCast(u32, msg.len));
    resetEvents();
    n = drive(s, now + 10 + 1001, pp[0..m]);
    ck(n == 0, "retrans acked clean");
    ck(g_failed == -1, "retrans ack no fail");

    const mr = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, PEER_ISS +% 1, seq +% @intCast(u32, msg.len), 0x04, "");
    resetEvents();
    _ = drive(s, now + 10 + 1002, pp[0..mr]);
    ck(g_failed == @intCast(i32, c.id), "retrans cleanup rst");
}

fn testOoo(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    const lenA: usize = 100;
    const lenB: usize = 200;
    const base = PEER_ISS +% 1;

    var a: [100]u8 = undefined;
    var b: [200]u8 = undefined;
    var i: usize = 0;
    while (i < lenA) : (i += 1) a[i] = @intCast(u8, 0xA0 + (i & 0x0F));
    i = 0;
    while (i < lenB) : (i += 1) b[i] = @intCast(u8, 0x30 + (i & 0x0F));

    var pp: [MAX_PKT]u8 = undefined;
    // B arrives first: within the 8 KB window but out of order.
    var m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, base +% @intCast(u32, lenA), c.iss +% 1, 0x18, b[0..]);
    resetEvents();
    var n = drive(s, now + 1, pp[0..m]);
    ck(n > 0, "ooo b acked");
    ck(pktAck(g_pkt[0..n]) == base, "ooo b ack unchanged");
    resetEvents();
    n = drive(s, now + 2, null);
    ck(n == 0, "ooo b no delivery");
    ck(g_data == -1, "ooo b not delivered");

    // A fills the hole; both segments become contiguous in order (A then B).
    m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, base, c.iss +% 1, 0x18, a[0..]);
    resetEvents();
    n = drive(s, now + 3, pp[0..m]);
    ck(n > 0, "ooo a acked");
    ck(pktAck(g_pkt[0..n]) == base +% @intCast(u32, lenA + lenB), "ooo drain ack");
    resetEvents();
    n = drive(s, now + 4, null);
    ck(n == 0, "ooo drain idle");
    ck(g_data == @intCast(i32, c.id), "ooo data event");

    var rb: [400]u8 = undefined;
    const rn = tcp.tcpRecv(s, c.id, rb[0..]) catch @panic("recv ooo");
    ck(rn == lenA + lenB, "ooo recv length");
    eqBytes(rb[0..lenA], a[0..], "ooo A bytes");
    eqBytes(rb[lenA..rn], b[0..], "ooo B bytes");

    // A duplicate of already-received bytes is ACKed but never delivered again.
    m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, base, c.iss +% 1, 0x18, a[0..]);
    resetEvents();
    n = drive(s, now + 5, pp[0..m]);
    ck(n > 0, "duplicate acked");
    ck(pktAck(g_pkt[0..n]) == base +% @intCast(u32, lenA + lenB), "duplicate ack unchanged");
    resetEvents();
    n = drive(s, now + 6, null);
    ck(n == 0, "duplicate idle");
    ck(g_data == -1, "duplicate not delivered");
    var dup: [8]u8 = undefined;
    ck((tcp.tcpRecv(s, c.id, dup[0..]) catch @panic("recv dup")) == 0, "duplicate recv empty");

    // A segment wholly outside the 8 KB window must not be delivered.
    const far = base +% @intCast(u32, lenA + lenB) +% @intCast(u32, 8200);
    m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, far, c.iss +% 1, 0x18, "x");
    resetEvents();
    n = drive(s, now + 6, pp[0..m]);
    ck(n > 0, "out-of-window acked");
    ck(pktAck(g_pkt[0..n]) == base +% @intCast(u32, lenA + lenB), "out-of-window ack unchanged");
    resetEvents();
    n = drive(s, now + 7, null);
    ck(n == 0, "out-of-window idle");
    ck(g_data == -1, "out-of-window not delivered");

    const mr = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, base +% @intCast(u32, lenA + lenB), c.iss +% 1, 0x04, "");
    resetEvents();
    _ = drive(s, now + 8, pp[0..mr]);
    ck(g_failed == @intCast(i32, c.id), "ooo cleanup rst");
}

fn testMss(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    var data: [5000]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) data[i] = @intCast(u8, (i * 31 + 7) & 0xFF);

    const sent = tcp.tcpSend(s, c.id, data[0..]) catch @panic("send mss");
    ck(sent == data.len, "mss send accepted all");
    // Close while the whole 5 KB is still queued: the pending data must drain
    // before FIN, not be dropped/stranded by close_requested.
    tcp.tcpClose(s, c.id) catch @panic("close mss");

    var pp: [MAX_PKT]u8 = undefined;
    var off: usize = 0;
    var segs: usize = 0;
    var have_ack = false;
    var ack_len: usize = 0;
    var peer_seq = PEER_ISS +% 1;

    while (off < data.len) {
        resetEvents();
        var n: usize = 0;
        if (have_ack) {
            n = drive(s, now + @intCast(u64, segs) + 10, pp[0..ack_len]);
        } else {
            n = drive(s, now + @intCast(u64, segs) + 10, null);
        }
        have_ack = false;
        ck(n > 0, "mss segment emitted");

        var want: usize = data.len - off;
        if (want > LOCAL_MSS) want = LOCAL_MSS;
        ck(pktPayload(g_pkt[0..n]).len == want, "mss segment size");
        ck(pktSeq(g_pkt[0..n]) == c.iss +% 1 +% @intCast(u32, off), "mss segment seq");
        eqBytes(pktPayload(g_pkt[0..n]), data[off .. off + want], "mss segment bytes");

        ack_len = ackPacket(pp[0..], c, peer_seq, pktSeq(g_pkt[0..n]) +% @intCast(u32, want));
        have_ack = true;
        off += want;
        segs += 1;
    }

    ck(segs == 4, "mss 4 segments");
    ck(off == 5000, "mss covered 5000");

    resetEvents();
    var n = drive(s, now + 100, pp[0..ack_len]);
    ck(n > 0, "mss fin emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x01) != 0, "mss fin flag");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1 +% 5000, "mss fin seq");
    const fin_seq = pktSeq(g_pkt[0..n]);

    const mf = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, peer_seq, fin_seq +% 1, 0x11, "");
    resetEvents();
    n = drive(s, now + 101, pp[0..mf]);
    ck(n > 0, "mss fin acked");
    ck(pktAck(g_pkt[0..n]) == peer_seq +% 1, "mss peer fin ack");
    resetEvents();
    n = drive(s, now + 102, null);
    ck(n == 0, "mss close idle");
    ck(g_closed == @intCast(i32, c.id), "mss closed event");
}

fn testPeerMss(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnectEx(s, now, 1200);
    var data: [1300]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) data[i] = @intCast(u8, (i * 17 + 3) & 0xFF);
    const sent = tcp.tcpSend(s, c.id, data[0..]) catch @panic("send peer mss");
    ck(sent == data.len, "peer mss send accepted");

    var pp: [MAX_PKT]u8 = undefined;
    resetEvents();
    var n = drive(s, now + 10, null);
    ck(n > 0, "peer mss first segment");
    ck(pktPayload(g_pkt[0..n]).len == 1200, "peer mss clamps to 1200");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1, "peer mss first seq");
    eqBytes(pktPayload(g_pkt[0..n]), data[0..1200], "peer mss first bytes");

    var m = ackPacket(pp[0..], c, PEER_ISS +% 1, pktSeq(g_pkt[0..n]) +% 1200);
    resetEvents();
    n = drive(s, now + 11, pp[0..m]);
    ck(n > 0, "peer mss second segment");
    ck(pktPayload(g_pkt[0..n]).len == 100, "peer mss tail 100");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1 +% 1200, "peer mss tail seq");
    eqBytes(pktPayload(g_pkt[0..n]), data[1200..1300], "peer mss tail bytes");

    m = ackPacket(pp[0..], c, PEER_ISS +% 1, pktSeq(g_pkt[0..n]) +% 100);
    resetEvents();
    n = drive(s, now + 12, pp[0..m]);
    ck(n == 0, "peer mss acked clean");

    const mr = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, PEER_ISS +% 1, c.iss +% 1 +% 1300, 0x04, "");
    resetEvents();
    _ = drive(s, now + 13, pp[0..mr]);
    ck(g_failed == @intCast(i32, c.id), "peer mss cleanup rst");
}

fn testMtu600(now: u64) void {
    var a = std.arena.init(g_mtu_buf[0..]);
    var cfg = tcp.TcpipConfig{
        .ip = LOCAL,
        .netmask = 0xFFFFFF00,
        .gateway = PEER,
        .mtu = 600,
        .dns_server = 0x0A000003,
        .max_sockets = 1,
    };
    const s = tcp.tcpipInit(&a, &cfg) catch @panic("mtu600 init");
    const c = doConnect(s, now); // SYN MSS option is asserted as mtu - 40 = 560

    const si = slotOf(s, c.id);
    ck(s.sockets[si].cwnd == 560, "mtu600 initial cwnd 560");

    var data: [1120]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) data[i] = @intCast(u8, (i * 13 + 5) & 0xFF);
    const sent = tcp.tcpSend(s, c.id, data[0..]) catch @panic("mtu600 send");
    ck(sent == data.len, "mtu600 send accepted 2xMSS");

    var pp: [MAX_PKT]u8 = undefined;
    resetEvents();
    var n = drive(s, now + 10, null);
    ck(n > 0, "mtu600 first segment");
    ck(n <= 600, "mtu600 datagram <= 600");
    ck(pktPayload(g_pkt[0..n]).len == 560, "mtu600 first 560");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1, "mtu600 first seq");
    eqBytes(pktPayload(g_pkt[0..n]), data[0..560], "mtu600 first bytes");
    const first_seq = pktSeq(g_pkt[0..n]);

    var m = ackPacket(pp[0..], c, PEER_ISS +% 1, first_seq +% 560);
    resetEvents();
    n = drive(s, now + 11, pp[0..m]);
    ck(n > 0, "mtu600 second segment");
    ck(n <= 600, "mtu600 second datagram <= 600");
    ck(pktPayload(g_pkt[0..n]).len == 560, "mtu600 second 560");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1 +% 560, "mtu600 second seq");
    eqBytes(pktPayload(g_pkt[0..n]), data[560..1120], "mtu600 second bytes");

    m = ackPacket(pp[0..], c, PEER_ISS +% 1, c.iss +% 1 +% 1120);
    resetEvents();
    n = drive(s, now + 12, pp[0..m]);
    ck(n == 0, "mtu600 acked clean");

    const mr = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, PEER_ISS +% 1, c.iss +% 1 +% 1120, 0x04, "");
    resetEvents();
    _ = drive(s, now + 13, pp[0..mr]);
    ck(g_failed == @intCast(i32, c.id), "mtu600 cleanup rst");
}

fn testCwnd(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    const si = slotOf(s, c.id);
    ck(s.sockets[si].cwnd == @intCast(u32, LOCAL_MSS), "initial cwnd == MSS");

    const len: usize = 2 * LOCAL_MSS;
    var data: [2 * LOCAL_MSS]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) data[i] = @intCast(u8, (i * 29 + 11) & 0xFF);
    const sent = tcp.tcpSend(s, c.id, data[0..]) catch @panic("cwnd send");
    ck(sent == len, "cwnd send accepted 2xMSS");

    // Initial cwnd == 1 MSS: only one segment may go out before an ACK.
    resetEvents();
    var n = drive(s, now + 10, null);
    ck(n > 0, "cwnd first segment");
    ck(pktPayload(g_pkt[0..n]).len == LOCAL_MSS, "cwnd first MSS");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1, "cwnd first seq");
    const first_seq = pktSeq(g_pkt[0..n]);

    resetEvents();
    n = drive(s, now + 11, null);
    ck(n == 0, "cwnd holds second segment before ACK");
    ck(g_failed == -1, "cwnd no failure before ACK");

    var pp: [MAX_PKT]u8 = undefined;
    const m = ackPacket(pp[0..], c, PEER_ISS +% 1, first_seq +% @intCast(u32, LOCAL_MSS));
    resetEvents();
    n = drive(s, now + 12, pp[0..m]);
    ck(n > 0, "cwnd second segment after ACK");
    ck(pktPayload(g_pkt[0..n]).len == LOCAL_MSS, "cwnd second MSS");
    ck(pktSeq(g_pkt[0..n]) == first_seq +% @intCast(u32, LOCAL_MSS), "cwnd second seq");
    eqBytes(pktPayload(g_pkt[0..n]), data[LOCAL_MSS..], "cwnd second bytes");

    const mr = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, PEER_ISS +% 1, c.iss +% 1 +% @intCast(u32, len), 0x04, "");
    resetEvents();
    _ = drive(s, now + 13, pp[0..mr]);
    ck(g_failed == @intCast(i32, c.id), "cwnd cleanup rst");
}

fn finOtsProbe(s: *tcp.TcpipStack, now: u64) bool {
    var tiny: [16]u8 = undefined;
    const act = tcp.tcpipPoll(s, now, null, tiny[0..]) catch |err| {
        return err == error.OutputTooSmall;
    };
    _ = act;
    return false;
}

fn testFinOts(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    tcp.tcpClose(s, c.id) catch @panic("close fin ots");
    ck(finOtsProbe(s, now + 10), "fin output-too-small");

    // The failed FIN build must not consume state: the retry emits the same FIN.
    resetEvents();
    var n = drive(s, now + 11, null);
    ck(n > 0, "fin retry emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x01) != 0, "fin retry flag");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1, "fin retry seq unchanged");
    const fin_seq = pktSeq(g_pkt[0..n]);

    var pp: [MAX_PKT]u8 = undefined;
    const peer_fin = PEER_ISS +% 1;
    const m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, peer_fin, fin_seq +% 1, 0x11, "");
    resetEvents();
    n = drive(s, now + 12, pp[0..m]);
    ck(n > 0, "fin retry acked");
    ck(pktAck(g_pkt[0..n]) == peer_fin +% 1, "fin retry peer ack");
    resetEvents();
    n = drive(s, now + 13, null);
    ck(n == 0, "fin retry close idle");
    ck(g_closed == @intCast(i32, c.id), "fin retry closed event");
}

fn testFinWindow(s: *tcp.TcpipStack, now: u64) void {
    const c = doConnect(s, now);
    const valid_fin = PEER_ISS +% 1;
    // Exactly one past the 8 KB window: off == 8192 must be rejected.
    const bad_fin = valid_fin +% @intCast(u32, 8192);
    var pp: [MAX_PKT]u8 = undefined;

    // Boundary-outside FIN must be ACKed but must not poison peer_fin_pending.
    var m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, bad_fin, c.iss +% 1, 0x11, "");
    resetEvents();
    var n = drive(s, now + 10, pp[0..m]);
    ck(n > 0, "bad fin acked");
    ck(pktAck(g_pkt[0..n]) == valid_fin, "bad fin ack unchanged");
    resetEvents();
    n = drive(s, now + 11, null);
    ck(n == 0, "bad fin idle");
    ck(g_closed == -1, "bad fin not closed");

    // The later valid FIN is accepted and completes the close.
    m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, valid_fin, c.iss +% 1, 0x11, "");
    resetEvents();
    n = drive(s, now + 12, pp[0..m]);
    ck(n > 0, "valid fin acked");
    ck(pktAck(g_pkt[0..n]) == valid_fin +% 1, "valid fin ack no");

    resetEvents();
    n = drive(s, now + 13, null);
    ck(n > 0, "passive fin emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x01) != 0, "passive fin flag");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1, "passive fin seq");

    resetEvents();
    n = drive(s, now + 14, null);
    ck(n == 0, "valid fin close idle");
    ck(g_closed == @intCast(i32, c.id), "valid fin closed event");
}

fn testWrap(s: *tcp.TcpipStack, now: u64) void {
    const CLIENT_WRAP: u32 = 0xFFFFFFF0;
    const PEER_WRAP: u32 = 0xFFFFFF00;
    const c = doConnectFull(s, now, 0, PEER_WRAP, CLIENT_WRAP);
    const pbase = PEER_WRAP +% 1;

    var data: [300]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) data[i] = @intCast(u8, 0xC0 + (i & 0x1F));

    var pp: [MAX_PKT]u8 = undefined;
    var m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, pbase, c.iss +% 1, 0x18, data[0..]);
    resetEvents();
    var n = drive(s, now + 10, pp[0..m]);
    ck(n > 0, "wrap peer data acked");
    ck(pktAck(g_pkt[0..n]) == pbase +% 300, "wrap peer ack wraps");
    resetEvents();
    n = drive(s, now + 11, null);
    ck(n == 0, "wrap peer data idle");
    ck(g_data == @intCast(i32, c.id), "wrap peer data event");

    var rb: [300]u8 = undefined;
    const rn = tcp.tcpRecv(s, c.id, rb[0..]) catch @panic("recv wrap");
    ck(rn == 300, "wrap recv length");
    eqBytes(rb[0..rn], data[0..], "wrap peer bytes exact");

    resetEvents();
    n = drive(s, now + 12, null);
    ck(n > 0, "wrap window update");

    var msg: [32]u8 = undefined;
    i = 0;
    while (i < msg.len) : (i += 1) msg[i] = @intCast(u8, 0x40 + i);
    const sent = tcp.tcpSend(s, c.id, msg[0..]) catch @panic("send wrap");
    ck(sent == msg.len, "wrap send accepted");

    resetEvents();
    n = drive(s, now + 13, null);
    ck(n > 0, "wrap client data emitted");
    ck(pktSeq(g_pkt[0..n]) == c.iss +% 1, "wrap client seq");
    eqBytes(pktPayload(g_pkt[0..n]), msg[0..], "wrap client bytes exact");
    const dseq = pktSeq(g_pkt[0..n]);
    const dend = dseq +% 32;

    m = ackPacket(pp[0..], c, pbase +% 300, dend);
    resetEvents();
    n = drive(s, now + 14, pp[0..m]);
    ck(n == 0, "wrap client acked clean");

    tcp.tcpClose(s, c.id) catch @panic("close wrap");
    resetEvents();
    n = drive(s, now + 15, null);
    ck(n > 0, "wrap fin emitted");
    ck((pktFlags(g_pkt[0..n]) & 0x01) != 0, "wrap fin flag");
    ck(pktSeq(g_pkt[0..n]) == dend, "wrap fin seq");
    const fin_seq = pktSeq(g_pkt[0..n]);

    const peer_fin = pbase +% 300;
    m = buildPeer(pp[0..], PEER, LOCAL, PEER_PORT, c.local_port, peer_fin, fin_seq +% 1, 0x11, "");
    resetEvents();
    n = drive(s, now + 16, pp[0..m]);
    ck(n > 0, "wrap fin acked");
    ck(pktAck(g_pkt[0..n]) == peer_fin +% 1, "wrap peer fin ack");
    resetEvents();
    n = drive(s, now + 17, null);
    ck(n == 0, "wrap close idle");
    ck(g_closed == @intCast(i32, c.id), "wrap closed event");
}

fn initOom(cfg: *tcp.TcpipConfig) bool {
    var tiny: [64]u8 = undefined;
    var a = std.arena.init(tiny[0..]);
    const p = tcp.tcpipInit(&a, cfg) catch |err| {
        return err == error.OutOfMemory;
    };
    _ = p;
    return false;
}

fn noFreeSocket() bool {
    var a = std.arena.init(g_oom_buf[0..]);
    var cfg = tcp.TcpipConfig{
        .ip = LOCAL,
        .netmask = 0xFFFFFF00,
        .gateway = PEER,
        .mtu = 1400,
        .dns_server = 0x0A000003,
        .max_sockets = 1,
    };
    const s = tcp.tcpipInit(&a, &cfg) catch return false;
    const id1 = tcp.tcpConnect(s, PEER, PEER_PORT) catch return false;
    _ = id1;
    const id2 = tcp.tcpConnect(s, PEER, PEER_PORT) catch |err| {
        return err == error.OutOfMemory;
    };
    _ = id2;
    return false;
}

fn testAllocFailures() void {
    var cfg = tcp.TcpipConfig{
        .ip = LOCAL,
        .netmask = 0xFFFFFF00,
        .gateway = PEER,
        .mtu = 1400,
        .dns_server = 0x0A000003,
        .max_sockets = 2,
    };
    ck(initOom(&cfg), "init arena oom");
    ck(noFreeSocket(), "no free socket oom");
}

fn pollCorrupt(s: *tcp.TcpipStack, now: u64, pkt: []const u8) bool {
    const act = tcp.tcpipPoll(s, now, pkt, g_out[0..]) catch |err| {
        if (err == error.Corrupt) return true;
        return false;
    };
    _ = act;
    return false;
}

fn noRoute(s: *tcp.TcpipStack) bool {
    const id = tcp.tcpConnect(s, 0, 80) catch |err| {
        return err == error.NoRoute;
    };
    _ = id;
    return false;
}

fn copyPkt(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn testChecksums(s: *tcp.TcpipStack, now: u64) void {
    var p: [64]u8 = undefined;
    const m = buildPeer(p[0..], PEER, LOCAL, PEER_PORT, 1234, 1, 1, 0x04, "");

    // Valid packet is accepted (no matching socket, so simply ignored).
    ck(!pollCorrupt(s, now, p[0..m]), "valid packet not corrupt");

    var bad: [64]u8 = undefined;
    copyPkt(bad[0..], p[0..m]);
    bad[10] = bad[10] ^ 0x01;
    ck(pollCorrupt(s, now, bad[0..m]), "bad ip checksum -> Corrupt");

    copyPkt(bad[0..], p[0..m]);
    const t = ipHdrLen(bad[0..m]);
    bad[t + 16] = bad[t + 16] ^ 0x01;
    ck(pollCorrupt(s, now, bad[0..m]), "bad tcp checksum -> Corrupt");
}

pub fn main() void {
    var arena_buf: [1048576]u8 = undefined;
    var ar = std.arena.init(arena_buf[0..]);
    var cfg = tcp.TcpipConfig{
        .ip = LOCAL,
        .netmask = 0xFFFFFF00,
        .gateway = PEER,
        .mtu = 1400,
        .dns_server = 0x0A000003,
        .max_sockets = 2,
    };
    var st = tcp.tcpipInit(&ar, &cfg) catch @panic("tcpip init");

    ck(noRoute(st), "no route to 0");

    testBasic(st, 1000);
    testRst(st, 10000);
    testRetrans(st, 20000);
    testOoo(st, 30000);
    testMss(st, 40000);
    testMtu600(42000);
    testPeerMss(st, 45000);
    testCwnd(st, 47000);
    testFinOts(st, 50000);
    testFinWindow(st, 60000);
    testWrap(st, 70000);
    testAllocFailures();
    testChecksums(st, 80000);

    if (g_fail == 0) {
        std.io.write("tcpip tcp ok\n");
    } else {
        std.io.write("tcpip tcp FAIL\n");
    }
}
