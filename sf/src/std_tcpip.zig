// std_tcpip.zig — Z98 std lib: userspace IPv4 + TCP/UDP/DNS/ICMP stack (spec §5.8).
//
// Sans-I/O pump: `tcpipPoll` receives raw IPv4 datagrams from the driver and
// emits raw IPv4 datagrams back through `TcpipAction.send_pkt`. The driver (the
// WireGuard demo) encrypts/decrypts those datagrams; this module never touches
// a socket, the clock, or the heap.
//
// Scope: IPv4 only, TCP client only (no listen/accept), UDP, DNS A-record
// resolution and ICMP echo client; no fragment reassembly. Fixed 8 KB receive
// window, one fixed send buffer per TCP socket, simplified fixed 1 s RTO with
// Karn (retransmitted segments are never used for RTT samples; this
// implementation takes no RTT samples at all), and minimal Reno congestion
// control (slow start + AIMD). `cfg.mtu` is the authoritative maximum inner
// IPv4 datagram size (headers included); the local MSS is `mtu - 40`, and the
// effective per-socket MSS is `min(peer-advertised MSS, local MSS)`. Peer
// fragments are dropped silently per the spec.
//
// DNS and ICMP are also pump-driven. `dnsResolve`/`icmpPing` start a request and
// return `error.Timeout` while it is outstanding. `tcpipPoll` returns `.done`
// once the request reaches a terminal state; the final call then returns the
// IPv4 answer / RTT, or `error.DnsFailed` / terminal `error.Timeout`. DNS
// answers must match the query ID, source, and QNAME (case-insensitive); ICMP
// replies must come from the queried source IP. Fixed retry cadence: 1 s,
// 3 attempts (no wall clock).
//
// Errors: Corrupt (malformed/checksum-failing datagram), NoRoute, ConnRefused,
// Timeout, DnsFailed, OutOfMemory, OutputTooSmall, Closed. A connection-level
// reset/failure is surfaced as `TcpipAction.failed`, not as a poll error.

const arena_mod = @import("std_arena.zig");

pub const TcpipConfig = struct {
    ip: u32,
    netmask: u32,
    gateway: u32,
    mtu: u16,
    dns_server: u32,
    max_sockets: u32,
};

pub const TcpipError = error{
    Corrupt,
    NoRoute,
    ConnRefused,
    Timeout,
    DnsFailed,
    OutOfMemory,
    OutputTooSmall,
    Closed,
};

pub const TcpipAction = union(enum) {
    send_pkt: []const u8,
    wait: u32,
    connected: u32,
    data: u32,
    closed: u32,
    failed: u32,
    done: void,
};

// TCP policy constants (spec §5.8). TCP_MSS is retained as the historical
// default MSS name; the live send MSS is derived per stack/socket from cfg.mtu
// and the peer's SYN-ACK MSS option (see localMss/p.mss).
pub const TCP_MSS: usize = 1400;
pub const TCP_RECV_WINDOW: usize = 8192;
pub const TCP_RTO_MS: u64 = 1000;

const SEND_CAP: usize = 16384;
const IP_HDR_LEN: usize = 20;
const TCP_HDR_LEN: usize = 20;
const TCP_SYN_OPT_LEN: usize = 4;
const RECV_MASK: usize = TCP_RECV_WINDOW - 1;

const IP_PROTO_TCP: u8 = 6;
const IP_PROTO_ICMP: u8 = 1;

const IP_PROTO_UDP: u8 = 17;
const UDP_HDR_LEN: usize = 8;
pub const UDP_MAX_PAYLOAD: usize = 1472;

const DNS_QUERY_CAP: usize = 512;
const DNS_NAME_MAX: usize = 255;
const DNS_LOCAL_PORT: u16 = 40000;
const DNS_SERVER_PORT: u16 = 53;
const DNS_RETRY_MS: u64 = 1000;
const DNS_MAX_TRIES: u32 = 3;
const DNS_MAX_ANSWERS: u32 = 32;

const ICMP_ECHO_REQ: u8 = 8;
const ICMP_ECHO_REPLY: u8 = 0;
const ICMP_ID: u16 = 0x5A39;
const ICMP_PAYLOAD_LEN: usize = 8;
const ICMP_RETRY_MS: u64 = 1000;
const ICMP_MAX_TRIES: u32 = 3;
const FLAG_FIN: u8 = 0x01;
const FLAG_SYN: u8 = 0x02;
const FLAG_RST: u8 = 0x04;
const FLAG_PSH: u8 = 0x08;
const FLAG_ACK: u8 = 0x10;

const MAX_SYN_RETRIES: u32 = 8;
const MAX_DATA_RETRIES: u32 = 12;
const DEFAULT_WAIT_MS: u32 = 1000;

const TcpState = enum {
    syn_sent,
    established,
    fin_wait1,
    fin_wait2,
    closed,
};

pub const TcpSock = struct {
    in_use: bool,
    id: u32,
    state: TcpState,
    local_ip: u32,
    local_port: u16,
    remote_ip: u32,
    remote_port: u16,

    // Effective send MSS (bytes): local MSS at SYN time, then
    // min(peer-advertised MSS, local MSS) after the SYN-ACK.
    mss: u16,

    iss: u32,
    snd_una: u32,
    snd_nxt: u32,
    snd_wnd: u32,
    rcv_nxt: u32,
    rcv_app: u32,

    send_buf: [SEND_CAP]u8,
    send_head: usize,
    send_sent: usize,
    send_tail: usize,

    recv_buf: [TCP_RECV_WINDOW]u8,
    recv_seq: [TCP_RECV_WINDOW]u32,
    recv_valid: [TCP_RECV_WINDOW]u8,

    cwnd: u32,
    ssthresh: u32,
    rto_deadline: u64,
    rto_armed: bool,
    retrans_count: u32,

    need_syn: bool,
    ack_needed: bool,
    close_requested: bool,

    fin_seq: u32,
    fin_sent: bool,
    fin_acked: bool,

    peer_fin_pending: bool,
    peer_fin_received: bool,
    peer_fin_seq: u32,

    ev_connected: bool,
    ev_data: bool,
    ev_closed: bool,
    ev_failed: bool,
};

const DnsState = enum { idle, pending, done, failed };
const IcmpState = enum { idle, pending, done, failed };

pub const UdpSock = struct {
    in_use: bool,
    id: u32,
    local_ip: u32,
    local_port: u16,
    rx_valid: bool,
    rx_ip: u32,
    rx_port: u16,
    rx_len: usize,
    rx_buf: [UDP_MAX_PAYLOAD]u8,
    tx_pending: bool,
    tx_ip: u32,
    tx_port: u16,
    tx_len: usize,
    tx_buf: [UDP_MAX_PAYLOAD]u8,
};

pub const TcpipStack = struct {
    cfg: TcpipConfig,
    arena: *arena_mod.Arena,
    sockets: [*]TcpSock,
    socket_count: usize,
    ip_id: u16,
    next_id: u32,
    udp_sockets: [*]UdpSock,
    udp_count: usize,
    dns_state: DnsState,
    dns_id: u16,
    dns_query_id: u16,
    dns_query: [DNS_QUERY_CAP]u8,
    dns_query_len: usize,
    dns_qname_len: usize,
    dns_result_ip: u32,
    dns_tries: u32,
    dns_sent: bool,
    dns_next_ms: u64,
    icmp_state: IcmpState,
    icmp_ip: u32,
    icmp_seq: u16,
    icmp_tries: u32,
    icmp_sent: bool,
    icmp_next_ms: u64,
    icmp_last_sent_ms: u64,
    icmp_rtt: u32,
};

fn zeroSock(p: *TcpSock) void {
    var raw: [*]u8 = @ptrCast([*]u8, p);
    var i: usize = 0;
    while (i < @sizeOf(TcpSock)) : (i += 1) raw[i] = 0;
    p.state = .closed;
}

fn zeroUdp(p: *UdpSock) void {
    var raw: [*]u8 = @ptrCast([*]u8, p);
    var i: usize = 0;
    while (i < @sizeOf(UdpSock)) : (i += 1) raw[i] = 0;
    p.in_use = false;
    p.rx_valid = false;
    p.tx_pending = false;
}

pub fn tcpipInit(arena: *arena_mod.Arena, cfg: *TcpipConfig) !*TcpipStack {
    var count: usize = @intCast(usize, cfg.max_sockets);
    if (count == 0) count = 1;

    const stack_raw = arena_mod.alloc(arena, @sizeOf(TcpipStack)) catch return error.OutOfMemory;
    var s: *TcpipStack = @ptrCast(*TcpipStack, stack_raw);
    const socks_raw = arena_mod.alloc(arena, count * @sizeOf(TcpSock)) catch return error.OutOfMemory;
    var socks: [*]TcpSock = @ptrCast([*]TcpSock, socks_raw);
    const udp_raw = arena_mod.alloc(arena, count * @sizeOf(UdpSock)) catch return error.OutOfMemory;
    var udp: [*]UdpSock = @ptrCast([*]UdpSock, udp_raw);

    s.cfg = cfg.*;
    if (s.cfg.mtu == 0) s.cfg.mtu = 1400;
    s.arena = arena;
    s.sockets = socks;
    s.socket_count = count;
    s.ip_id = 1;
    s.next_id = 1;
    s.udp_sockets = udp;
    s.udp_count = count;
    s.dns_state = .idle;
    s.dns_id = 0x4D37;
    s.dns_query_id = 0;
    s.dns_query_len = 0;
    s.dns_qname_len = 0;
    s.dns_result_ip = 0;
    s.dns_tries = 0;
    s.dns_sent = false;
    s.dns_next_ms = 0;
    s.icmp_state = .idle;
    s.icmp_ip = 0;
    s.icmp_seq = 0;
    s.icmp_tries = 0;
    s.icmp_sent = false;
    s.icmp_next_ms = 0;
    s.icmp_last_sent_ms = 0;
    s.icmp_rtt = 0;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        zeroSock(&socks[i]);
        zeroUdp(&udp[i]);
    }
    return s;
}

// Local MSS: cfg.mtu is the maximum inner IPv4 datagram (20-byte IPv4 header +
// 20-byte TCP header + payload), so the largest safe TCP payload is mtu - 40.
fn localMss(s: *TcpipStack) u16 {
    if (s.cfg.mtu <= 40) return 1;
    return @intCast(u16, @intCast(usize, s.cfg.mtu) - 40);
}

// Parse the MSS option (kind 2, length 4) from a SYN/SYN-ACK. Returns 0 when
// the option is absent or malformed.
fn parseMssOption(tcp: []const u8, doff: usize) u16 {
    var i: usize = TCP_HDR_LEN;
    while (i < doff) {
        const kind = tcp[i];
        if (kind == 0) break;
        if (kind == 1) {
            i += 1;
            continue;
        }
        if (i + 1 >= doff) break;
        const len: usize = @intCast(usize, tcp[i + 1]);
        if (len < 2 or i + len > doff) break;
        if (kind == 2 and len == 4) return load16be(tcp, i + 2);
        i += len;
    }
    return 0;
}

fn load16be(p: []const u8, off: usize) u16 {
    return (@intCast(u16, p[off]) << 8) | @intCast(u16, p[off + 1]);
}

fn load32be(p: []const u8, off: usize) u32 {
    return (@intCast(u32, p[off]) << 24) |
        (@intCast(u32, p[off + 1]) << 16) |
        (@intCast(u32, p[off + 2]) << 8) |
        @intCast(u32, p[off + 3]);
}

fn store16be(p: []u8, off: usize, v: u16) void {
    p[off] = @intCast(u8, v >> 8);
    p[off + 1] = @intCast(u8, v & 0xFF);
}

fn store32be(p: []u8, off: usize, v: u32) void {
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

fn foldChecksum(sum0: u32) u16 {
    var sum = sum0;
    while ((sum >> 16) != 0) sum = (sum & 0xFFFF) + (sum >> 16);
    return @intCast(u16, sum & 0xFFFF);
}

// One's-complement checksum of an IPv4 header (checksum field should be zero
// on entry). A valid header with its checksum in place folds to 0xFFFF.
pub fn ipv4Checksum(header: []const u8) u16 {
    return ~foldChecksum(sumWords(header));
}

fn ipv4HeaderValid(header: []const u8) bool {
    return foldChecksum(sumWords(header)) == 0xFFFF;
}

fn pseudoSum(src: u32, dst: u32, seg_len: usize) u32 {
    var sum: u32 = 0;
    sum += (src >> 16) & 0xFFFF;
    sum += src & 0xFFFF;
    sum += (dst >> 16) & 0xFFFF;
    sum += dst & 0xFFFF;
    sum += IP_PROTO_TCP;
    sum += @intCast(u32, seg_len);
    return sum;
}

fn tcpChecksum(src: u32, dst: u32, seg: []const u8) u16 {
    return ~foldChecksum(pseudoSum(src, dst, seg.len) + sumWords(seg));
}

fn tcpChecksumValid(src: u32, dst: u32, seg: []const u8) bool {
    return foldChecksum(pseudoSum(src, dst, seg.len) + sumWords(seg)) == 0xFFFF;
}

fn seqLess(a: u32, b: u32) bool {
    return @bitCast(i32, a -% b) < 0;
}

fn sameSubnet(s: *TcpipStack, dst: u32) bool {
    return (dst & s.cfg.netmask) == (s.cfg.ip & s.cfg.netmask);
}

fn routeOk(s: *TcpipStack, dst: u32) bool {
    if (dst == 0) return false;
    if (sameSubnet(s, dst)) return true;
    return s.cfg.gateway != 0;
}

fn getSock(s: *TcpipStack, id: u32) ?*TcpSock {
    var i: usize = 0;
    while (i < s.socket_count) : (i += 1) {
        if (s.sockets[i].in_use and s.sockets[i].id == id) return &s.sockets[i];
    }
    return null;
}

fn compactSend(p: *TcpSock) void {
    if (p.send_head == 0) return;
    if (p.send_head == p.send_tail) {
        p.send_head = 0;
        p.send_sent = 0;
        p.send_tail = 0;
        return;
    }
    const n = p.send_tail - p.send_head;
    var i: usize = 0;
    while (i < n) : (i += 1) p.send_buf[i] = p.send_buf[p.send_head + i];
    p.send_tail = n;
    p.send_sent -= p.send_head;
    p.send_head = 0;
}

// Advertised receive window: free space in the 8 KB app/reassembly ring.
fn recvWindow(p: *TcpSock) u16 {
    var end = p.rcv_nxt;
    if (p.peer_fin_received) end = p.peer_fin_seq;
    const outstanding = end -% p.rcv_app;
    if (outstanding >= TCP_RECV_WINDOW) return 0;
    return @intCast(u16, TCP_RECV_WINDOW - @intCast(usize, outstanding));
}

fn failSock(p: *TcpSock) void {
    p.state = .closed;
    p.ev_failed = true;
    p.ev_closed = false;
    p.ev_connected = false;
    p.ev_data = false;
    p.close_requested = false;
}

// Append newly-contiguous bytes to the app-visible range and finish a pending
// peer FIN when its sequence is reached. Returns true iff new data bytes became
// contiguous.
fn drainRecv(p: *TcpSock) bool {
    var any = false;
    while (true) {
        if (p.peer_fin_pending and !p.peer_fin_received and p.rcv_nxt == p.peer_fin_seq) {
            p.peer_fin_pending = false;
            p.peer_fin_received = true;
            p.rcv_nxt +%= 1;
            p.ack_needed = true;
            p.ev_closed = true;
            continue;
        }
        const idx = @intCast(usize, p.rcv_nxt) & RECV_MASK;
        if (p.recv_valid[idx] == 0 or p.recv_seq[idx] != p.rcv_nxt) break;
        p.recv_valid[idx] = 0;
        p.rcv_nxt +%= 1;
        any = true;
    }
    if (any) p.ev_data = true;
    return any;
}

fn recvSegment(p: *TcpSock, seq0: u32, data: []const u8) bool {
    if (data.len == 0) return false;

    var seq = seq0;
    var d = data;
    var dlen = data.len;

    const outstanding = p.rcv_nxt -% p.rcv_app;
    if (outstanding >= TCP_RECV_WINDOW) return false;
    const free = TCP_RECV_WINDOW - @intCast(usize, outstanding);

    // Trim bytes already received, then enforce the advertised window.
    if (seqLess(seq, p.rcv_nxt)) {
        const trim = p.rcv_nxt -% seq;
        if (trim >= @intCast(u32, dlen)) return false;
        const t = @intCast(usize, trim);
        seq = p.rcv_nxt;
        d = data[t..];
        dlen = d.len;
    }

    const off = seq -% p.rcv_nxt;
    if (off >= @intCast(u32, free)) return false;
    var cap: usize = free - @intCast(usize, off);
    var n: usize = dlen;
    if (n > cap) n = cap;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const s_i = seq +% @intCast(u32, i);
        const idx = @intCast(usize, s_i) & RECV_MASK;
        p.recv_buf[idx] = d[i];
        p.recv_seq[idx] = s_i;
        p.recv_valid[idx] = 1;
    }

    if (off == 0) return drainRecv(p);
    return false;
}

fn handleFin(p: *TcpSock, fin_seq: u32) void {
    p.ack_needed = true;
    if (p.peer_fin_received or p.peer_fin_pending) return;
    if (seqLess(fin_seq, p.rcv_nxt)) return; // stale duplicate FIN

    // Only accept a FIN whose sequence lies inside the advertised 8 KB receive
    // window. An out-of-window FIN must not poison peer_fin_pending.
    const outstanding = p.rcv_nxt -% p.rcv_app;
    if (outstanding >= TCP_RECV_WINDOW) return;
    const free = TCP_RECV_WINDOW - @intCast(usize, outstanding);
    const off = fin_seq -% p.rcv_nxt;
    if (off >= @intCast(u32, free)) return;

    p.peer_fin_pending = true;
    p.peer_fin_seq = fin_seq;
    if (p.rcv_nxt == fin_seq) _ = drainRecv(p);
}

fn handleAck(p: *TcpSock, ack: u32, wnd: u16, now_ms: u64) void {
    if (seqLess(ack, p.snd_una)) {
        p.snd_wnd = @intCast(u32, wnd);
        return;
    }
    if (seqLess(p.snd_nxt, ack)) return;

    p.snd_wnd = @intCast(u32, wnd);
    const acked = ack -% p.snd_una;
    if (acked == 0) return;

    var data_acked = acked;
    var fin_just_acked = false;
    if (p.fin_sent and !seqLess(ack, p.fin_seq +% 1)) {
        data_acked = p.fin_seq -% p.snd_una;
        fin_just_acked = true;
    }

    var advance: usize = @intCast(usize, data_acked);
    const buffered = p.send_sent - p.send_head;
    if (advance > buffered) advance = buffered;
    p.send_head += advance;
    if (p.send_head == p.send_tail) {
        p.send_head = 0;
        p.send_sent = 0;
        p.send_tail = 0;
    } else if (p.send_sent < p.send_head) {
        p.send_sent = p.send_head;
    }

    p.snd_una = ack;
    if (fin_just_acked) p.fin_acked = true;

    // Minimal Reno: slow start below ssthresh, additive increase above it.
    if (advance > 0) {
        const a: u32 = @intCast(u32, advance);
        if (p.cwnd < p.ssthresh) {
            p.cwnd += a;
        } else {
            const m = @intCast(u32, p.mss);
            var inc: u32 = (m * m) / p.cwnd;
            if (inc == 0) inc = 1;
            p.cwnd += inc;
        }
        if (p.cwnd > 65535) p.cwnd = 65535;
    }

    if (p.fin_acked and p.state == .fin_wait1) p.state = .fin_wait2;

    p.retrans_count = 0;
    if (p.snd_una == p.snd_nxt) {
        p.rto_armed = false;
    } else {
        p.rto_deadline = now_ms + TCP_RTO_MS;
        p.rto_armed = true;
    }
}

fn buildSegment(s: *TcpipStack, p: *TcpSock, out: []u8, seq: u32, ack: u32, flags: u8, payload: []const u8, with_mss: bool) ![]const u8 {
    const tcp_hdr: usize = if (with_mss) TCP_HDR_LEN + TCP_SYN_OPT_LEN else TCP_HDR_LEN;
    const total = IP_HDR_LEN + tcp_hdr + payload.len;
    // cfg.mtu includes the IPv4 and TCP headers: never emit a larger datagram.
    if (total > @intCast(usize, s.cfg.mtu)) return error.OutputTooSmall;
    if (out.len < total) return error.OutputTooSmall;

    var i: usize = 0;
    while (i < total) : (i += 1) out[i] = 0;

    out[0] = 0x45;
    out[1] = 0;
    store16be(out, 2, @intCast(u16, total));
    store16be(out, 4, s.ip_id);
    s.ip_id +%= 1;
    store16be(out, 6, 0x4000); // don't fragment
    out[8] = 64;
    out[9] = IP_PROTO_TCP;
    store32be(out, 12, p.local_ip);
    store32be(out, 16, p.remote_ip);
    store16be(out, 10, ipv4Checksum(out[0..IP_HDR_LEN]));

    const t = IP_HDR_LEN;
    store16be(out, t, p.local_port);
    store16be(out, t + 2, p.remote_port);
    store32be(out, t + 4, seq);
    store32be(out, t + 8, ack);
    out[t + 12] = @intCast(u8, (tcp_hdr / 4) << 4);
    out[t + 13] = flags;
    store16be(out, t + 14, recvWindow(p));
    store16be(out, t + 16, 0);
    store16be(out, t + 18, 0);
    if (with_mss) {
        out[t + 20] = 2;
        out[t + 21] = 4;
        store16be(out, t + 22, p.mss);
    }

    i = 0;
    while (i < payload.len) : (i += 1) out[t + tcp_hdr + i] = payload[i];

    store16be(out, t + 16, tcpChecksum(p.local_ip, p.remote_ip, out[t..total]));
    return out[0..total];
}

fn processTcp(s: *TcpipStack, p: *TcpSock, now_ms: u64, tcp: []const u8, doff: usize) void {
    const seq = load32be(tcp, 4);
    const ack = load32be(tcp, 8);
    const flags = tcp[13];
    const wnd = load16be(tcp, 14);
    const dlen = tcp.len - doff;

    if (p.state == .syn_sent) {
        if ((flags & FLAG_RST) != 0) {
            failSock(p);
            return;
        }
        if ((flags & FLAG_SYN) != 0 and (flags & FLAG_ACK) != 0) {
            if (ack != p.iss +% 1) return;
            p.snd_una = p.iss +% 1;
            p.snd_nxt = p.iss +% 1;
            p.rcv_nxt = seq +% 1;
            p.rcv_app = p.rcv_nxt;
            p.snd_wnd = @intCast(u32, wnd);
            const local = localMss(s);
            const peer_mss = parseMssOption(tcp, doff);
            if (peer_mss != 0 and peer_mss < local) {
                p.mss = peer_mss;
            } else {
                p.mss = local;
            }
            p.cwnd = @intCast(u32, p.mss);
            p.ssthresh = 65535;
            p.state = .established;
            p.need_syn = false;
            p.ack_needed = true;
            p.ev_connected = true;
            p.rto_armed = false;
            p.retrans_count = 0;
        }
        return;
    }

    if (p.state == .closed) return;
    if ((flags & FLAG_RST) != 0) {
        failSock(p);
        return;
    }
    if ((flags & FLAG_SYN) != 0) return;

    if ((flags & FLAG_ACK) != 0) handleAck(p, ack, wnd, now_ms);

    if (dlen > 0) {
        if (recvSegment(p, seq, tcp[doff..])) p.ev_data = true;
        p.ack_needed = true;
    }
    if ((flags & FLAG_FIN) != 0) {
        handleFin(p, seq +% @intCast(u32, dlen));
    }
}

fn processPacket(s: *TcpipStack, now_ms: u64, rx: []const u8) !void {
    if (rx.len < IP_HDR_LEN) return error.Corrupt;
    if ((rx[0] >> 4) != 4) return error.Corrupt;

    const ihl: usize = @intCast(usize, rx[0] & 0x0F) * 4;
    if (ihl < IP_HDR_LEN or ihl > rx.len) return error.Corrupt;
    const total: usize = @intCast(usize, load16be(rx, 2));
    if (total < ihl or total > rx.len) return error.Corrupt;
    if (!ipv4HeaderValid(rx[0..ihl])) return error.Corrupt;

    // Fragment (MF set or non-zero offset): never reassemble, just drop.
    const frag = load16be(rx, 6);
    if ((frag & 0x3FFF) != 0) return;

    const dst_ip = load32be(rx, 16);
    if (dst_ip != s.cfg.ip) return;
    const src_ip = load32be(rx, 12);

    if (rx[9] == IP_PROTO_UDP) {
        try processUdp(s, src_ip, rx[ihl..total]);
        return;
    }
    if (rx[9] == IP_PROTO_ICMP) {
        try processIcmp(s, src_ip, now_ms, rx[ihl..total]);
        return;
    }
    if (rx[9] != IP_PROTO_TCP) return;

    const tcp = rx[ihl..total];
    if (tcp.len < TCP_HDR_LEN) return error.Corrupt;
    const doff: usize = @intCast(usize, tcp[12] >> 4) * 4;
    if (doff < TCP_HDR_LEN or doff > tcp.len) return error.Corrupt;
    if (!tcpChecksumValid(src_ip, dst_ip, tcp)) return error.Corrupt;

    const src_port = load16be(tcp, 0);
    const dst_port = load16be(tcp, 2);

    var i: usize = 0;
    while (i < s.socket_count) : (i += 1) {
        const p = &s.sockets[i];
        if (!p.in_use) continue;
        if (p.local_port != dst_port or p.remote_port != src_port or p.remote_ip != src_ip) continue;
        processTcp(s, p, now_ms, tcp, doff);
        return;
    }
}

pub fn tcpConnect(s: *TcpipStack, dst_ip: u32, dst_port: u16) !u32 {
    if (!routeOk(s, dst_ip)) return error.NoRoute;

    var i: usize = 0;
    while (i < s.socket_count) : (i += 1) {
        if (!s.sockets[i].in_use) {
            const p = &s.sockets[i];
            zeroSock(p);
            p.in_use = true;
            p.id = s.next_id;
            s.next_id +%= 1;
            if (s.next_id == 0) s.next_id = 1;
            p.state = .syn_sent;
            p.local_ip = s.cfg.ip;
            p.local_port = @intCast(u16, 49152 + @intCast(u32, i));
            p.remote_ip = dst_ip;
            p.remote_port = dst_port;
            p.mss = localMss(s);
            p.iss = 0x12340000 + (p.id *% 0x101);
            p.snd_una = p.iss;
            p.snd_nxt = p.iss;
            p.snd_wnd = @intCast(u32, TCP_RECV_WINDOW);
            p.rcv_nxt = 0;
            p.rcv_app = 0;
            p.cwnd = @intCast(u32, p.mss);
            p.ssthresh = 65535;
            p.need_syn = true;
            return p.id;
        }
    }
    return error.OutOfMemory;
}

pub fn tcpSend(s: *TcpipStack, sock: u32, data: []const u8) !usize {
    const p = getSock(s, sock) orelse return error.Closed;
    if (p.state != .established or p.close_requested) return error.Closed;
    if (data.len == 0) return 0;

    if (p.send_tail == SEND_CAP) compactSend(p);
    var space = SEND_CAP - p.send_tail;
    var n = data.len;
    if (n > space) n = space;
    var i: usize = 0;
    while (i < n) : (i += 1) p.send_buf[p.send_tail + i] = data[i];
    p.send_tail += n;
    return n;
}

pub fn tcpRecv(s: *TcpipStack, sock: u32, out: []u8) !usize {
    const p = getSock(s, sock) orelse return error.Closed;
    var end = p.rcv_nxt;
    if (p.peer_fin_received) end = p.peer_fin_seq;
    const avail = end -% p.rcv_app;
    if (avail == 0 or out.len == 0) return 0;

    var n: usize = @intCast(usize, avail);
    if (n > out.len) n = out.len;

    var idx = @intCast(usize, p.rcv_app) & RECV_MASK;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = p.recv_buf[idx];
        idx = (idx + 1) & RECV_MASK;
        p.rcv_app +%= 1;
    }
    p.ack_needed = true;
    return n;
}

pub fn tcpClose(s: *TcpipStack, sock: u32) !void {
    const p = getSock(s, sock) orelse return error.Closed;
    if (p.state == .established) {
        p.close_requested = true;
    } else if (p.state == .syn_sent) {
        failSock(p);
    }
}

// RTO timeout: halve ssthresh (floor 2*MSS) and restart in slow start.
fn onRto(p: *TcpSock) void {
    const m = @intCast(u32, p.mss);
    var ss = p.cwnd / 2;
    const floor: u32 = m * 2;
    if (ss < floor) ss = floor;
    p.ssthresh = ss;
    p.cwnd = m;
}

fn serveSend(s: *TcpipStack, p: *TcpSock, now_ms: u64, out: []u8) !?[]const u8 {
    if (p.ev_failed) return null;

    if (p.need_syn) {
        const pkt = try buildSegment(s, p, out, p.iss, 0, FLAG_SYN, out[0..0], true);
        p.need_syn = false;
        p.rto_deadline = now_ms + TCP_RTO_MS;
        p.rto_armed = true;
        p.retrans_count = 0;
        return pkt;
    }

    if (p.ack_needed) {
        const pkt = try buildSegment(s, p, out, p.snd_nxt, p.rcv_nxt, FLAG_ACK, out[0..0], false);
        p.ack_needed = false;
        return pkt;
    }

    // A graceful close never retransmits after the final ACK is sent.
    if (p.state == .closed) return null;

    if (p.rto_armed and now_ms >= p.rto_deadline) {
        if (p.state == .syn_sent) {
            if (p.retrans_count >= MAX_SYN_RETRIES) {
                failSock(p);
                return null;
            }
            const pkt = try buildSegment(s, p, out, p.iss, 0, FLAG_SYN, out[0..0], true);
            p.retrans_count += 1;
            p.rto_deadline = now_ms + TCP_RTO_MS;
            return pkt;
        }
        if (p.send_head < p.send_sent) {
            if (p.retrans_count >= MAX_DATA_RETRIES) {
                failSock(p);
                return null;
            }
            var n = p.send_sent - p.send_head;
            const mss: usize = @intCast(usize, p.mss);
            if (n > mss) n = mss;
            onRto(p);
            const pkt = try buildSegment(s, p, out, p.snd_una, p.rcv_nxt, FLAG_ACK | FLAG_PSH, p.send_buf[p.send_head .. p.send_head + n], false);
            p.retrans_count += 1;
            p.rto_deadline = now_ms + TCP_RTO_MS;
            return pkt;
        }
        if (p.fin_sent and !p.fin_acked) {
            if (p.retrans_count >= MAX_DATA_RETRIES) {
                failSock(p);
                return null;
            }
            onRto(p);
            const pkt = try buildSegment(s, p, out, p.fin_seq, p.rcv_nxt, FLAG_FIN | FLAG_ACK, out[0..0], false);
            p.retrans_count += 1;
            p.rto_deadline = now_ms + TCP_RTO_MS;
            return pkt;
        }
        p.rto_armed = false;
    }

    if (p.state == .established and p.send_sent < p.send_tail) {
        var limit = p.cwnd;
        if (p.snd_wnd < limit) limit = p.snd_wnd;
        const flight = p.snd_nxt -% p.snd_una;
        if (flight < limit) {
            var win = limit - flight;
            var n = p.send_tail - p.send_sent;
            const mss: usize = @intCast(usize, p.mss);
            if (n > mss) n = mss;
            if (n > @intCast(usize, win)) n = @intCast(usize, win);
            if (n > 0) {
                const pkt = try buildSegment(s, p, out, p.snd_nxt, p.rcv_nxt, FLAG_ACK | FLAG_PSH, p.send_buf[p.send_sent .. p.send_sent + n], false);
                p.send_sent += n;
                p.snd_nxt +%= @intCast(u32, n);
                if (!p.rto_armed) {
                    p.rto_deadline = now_ms + TCP_RTO_MS;
                    p.rto_armed = true;
                    p.retrans_count = 0;
                }
                return pkt;
            }
        }
    }

    if (p.state == .established and (p.close_requested or p.peer_fin_received) and p.send_sent == p.send_tail) {
        // Build first: OutputTooSmall must leave the socket retryable, with no
        // fin_wait1/fin_sent/snd_nxt mutation.
        const fin_seq = p.snd_nxt;
        const pkt = try buildSegment(s, p, out, fin_seq, p.rcv_nxt, FLAG_FIN | FLAG_ACK, out[0..0], false);
        p.state = .fin_wait1;
        p.close_requested = false;
        p.fin_seq = fin_seq;
        p.snd_nxt = fin_seq +% 1;
        p.fin_sent = true;
        if (!p.rto_armed) {
            p.rto_deadline = now_ms + TCP_RTO_MS;
            p.rto_armed = true;
            p.retrans_count = 0;
        }
        return pkt;
    }

    return null;
}

fn serveEvent(p: *TcpSock) ?TcpipAction {
    if (p.ev_failed) {
        const id = p.id;
        p.ev_failed = false;
        p.in_use = false;
        return TcpipAction{ .failed = id };
    }

    if (p.ev_closed) {
        if (p.peer_fin_received and p.rcv_app != p.peer_fin_seq) {
            const avail = p.peer_fin_seq -% p.rcv_app;
            if (avail != 0) {
                p.ev_data = false;
                return TcpipAction{ .data = p.id };
            }
        }
        const id = p.id;
        p.ev_closed = false;
        p.in_use = false;
        return TcpipAction{ .closed = id };
    }

    if (p.ev_connected) {
        p.ev_connected = false;
        return TcpipAction{ .connected = p.id };
    }

    if (p.ev_data) {
        var end = p.rcv_nxt;
        if (p.peer_fin_received) end = p.peer_fin_seq;
        if ((end -% p.rcv_app) != 0) {
            p.ev_data = false;
            return TcpipAction{ .data = p.id };
        }
        p.ev_data = false;
    }

    return null;
}

pub fn tcpipPoll(s: *TcpipStack, now_ms: u64, rx_ip: ?[]const u8, out: []u8) !TcpipAction {
    if (rx_ip) |rx| try processPacket(s, now_ms, rx);

    var i: usize = 0;
    while (i < s.socket_count) : (i += 1) {
        const p = &s.sockets[i];
        if (!p.in_use) continue;
        const maybe = try serveSend(s, p, now_ms, out);
        if (maybe) |pkt| return TcpipAction{ .send_pkt = pkt };
    }

    if (try serveUdp(s, now_ms, out)) |pkt| return TcpipAction{ .send_pkt = pkt };
    if (try serveDns(s, now_ms, out)) |pkt| return TcpipAction{ .send_pkt = pkt };
    if (try serveIcmp(s, now_ms, out)) |pkt| return TcpipAction{ .send_pkt = pkt };

    i = 0;
    while (i < s.socket_count) : (i += 1) {
        const p = &s.sockets[i];
        if (!p.in_use) continue;
        if (serveEvent(p)) |act| return act;
    }

    if (s.dns_state == .done or s.dns_state == .failed or s.icmp_state == .done or s.icmp_state == .failed) {
        return TcpipAction{ .done = {} };
    }

    var any = false;
    var have_timer = false;
    var next_ms: u64 = 0;
    i = 0;
    while (i < s.socket_count) : (i += 1) {
        const p = &s.sockets[i];
        if (!p.in_use) continue;
        any = true;
        if (p.rto_armed) {
            if (!have_timer or p.rto_deadline < next_ms) {
                next_ms = p.rto_deadline;
                have_timer = true;
            }
        }
    }

    i = 0;
    while (i < s.udp_count) : (i += 1) {
        if (s.udp_sockets[i].in_use) {
            any = true;
            break;
        }
    }

    if (s.dns_state == .pending) {
        any = true;
        const deadline = if (s.dns_sent) s.dns_next_ms else now_ms;
        if (!have_timer or deadline < next_ms) {
            next_ms = deadline;
            have_timer = true;
        }
    }

    if (s.icmp_state == .pending) {
        any = true;
        const deadline = if (s.icmp_sent) s.icmp_next_ms else now_ms;
        if (!have_timer or deadline < next_ms) {
            next_ms = deadline;
            have_timer = true;
        }
    }

    if (!any) return TcpipAction{ .done = {} };
    if (have_timer) {
        if (next_ms <= now_ms) return TcpipAction{ .wait = 1 };
        var d = next_ms - now_ms;
        if (d > DEFAULT_WAIT_MS) d = DEFAULT_WAIT_MS;
        return TcpipAction{ .wait = @intCast(u32, d) };
    }
    return TcpipAction{ .wait = DEFAULT_WAIT_MS };
}

fn getUdp(s: *TcpipStack, id: u32) ?*UdpSock {
    var i: usize = 0;
    while (i < s.udp_count) : (i += 1) {
        if (s.udp_sockets[i].in_use and s.udp_sockets[i].id == id) return &s.udp_sockets[i];
    }
    return null;
}

fn writeIpv4Header(s: *TcpipStack, out: []u8, total: usize, proto: u8, dst_ip: u32) void {
    out[0] = 0x45;
    out[1] = 0;
    store16be(out, 2, @intCast(u16, total));
    store16be(out, 4, s.ip_id);
    s.ip_id +%= 1;
    store16be(out, 6, 0x4000);
    out[8] = 64;
    out[9] = proto;
    store32be(out, 12, s.cfg.ip);
    store32be(out, 16, dst_ip);
    store16be(out, 10, ipv4Checksum(out[0..IP_HDR_LEN]));
}

fn pseudoSumFor(src: u32, dst: u32, seg_len: usize, proto: u8) u32 {
    var sum: u32 = 0;
    sum += (src >> 16) & 0xFFFF;
    sum += src & 0xFFFF;
    sum += (dst >> 16) & 0xFFFF;
    sum += dst & 0xFFFF;
    sum += @intCast(u32, proto);
    sum += @intCast(u32, seg_len);
    return sum;
}

fn udpChecksum(src: u32, dst: u32, seg: []const u8) u16 {
    return ~foldChecksum(pseudoSumFor(src, dst, seg.len, IP_PROTO_UDP) + sumWords(seg));
}

fn udpChecksumValid(src: u32, dst: u32, seg: []const u8) bool {
    if (load16be(seg, 6) == 0) return true;
    return foldChecksum(pseudoSumFor(src, dst, seg.len, IP_PROTO_UDP) + sumWords(seg)) == 0xFFFF;
}

fn buildUdpPacket(s: *TcpipStack, out: []u8, dst_ip: u32, dst_port: u16, local_port: u16, payload: []const u8) ![]const u8 {
    const total = IP_HDR_LEN + UDP_HDR_LEN + payload.len;
    if (total > @intCast(usize, s.cfg.mtu)) return error.OutputTooSmall;
    if (out.len < total) return error.OutputTooSmall;
    if (UDP_HDR_LEN + payload.len > 65535) return error.OutputTooSmall;

    var i: usize = 0;
    while (i < total) : (i += 1) out[i] = 0;
    writeIpv4Header(s, out, total, IP_PROTO_UDP, dst_ip);

    const u = IP_HDR_LEN;
    store16be(out, u, local_port);
    store16be(out, u + 2, dst_port);
    store16be(out, u + 4, @intCast(u16, UDP_HDR_LEN + payload.len));

    i = 0;
    while (i < payload.len) : (i += 1) out[u + UDP_HDR_LEN + i] = payload[i];

    var ck = udpChecksum(s.cfg.ip, dst_ip, out[u..total]);
    if (ck == 0) ck = 0xFFFF;
    store16be(out, u + 6, ck);
    return out[0..total];
}

fn buildIcmpPacket(s: *TcpipStack, out: []u8, seq: u16) ![]const u8 {
    const total = IP_HDR_LEN + 8 + ICMP_PAYLOAD_LEN;
    if (total > @intCast(usize, s.cfg.mtu)) return error.OutputTooSmall;
    if (out.len < total) return error.OutputTooSmall;

    var i: usize = 0;
    while (i < total) : (i += 1) out[i] = 0;
    writeIpv4Header(s, out, total, IP_PROTO_ICMP, s.icmp_ip);

    const m = IP_HDR_LEN;
    out[m] = ICMP_ECHO_REQ;
    out[m + 1] = 0;
    store16be(out, m + 4, ICMP_ID);
    store16be(out, m + 6, seq);
    i = 0;
    while (i < ICMP_PAYLOAD_LEN) : (i += 1) out[m + 8 + i] = @intCast(u8, (0x50 + i) & 0xFF);
    store16be(out, m + 2, ipv4Checksum(out[m..total]));
    return out[0..total];
}

fn processDnsAnswer(s: *TcpipStack, payload: []const u8) void {
    var ip: u32 = 0;
    const expected = s.dns_query[12 .. 12 + s.dns_qname_len];
    const r = parseDnsAnswer(payload, s.dns_query_id, expected, &ip);
    if (r == DnsParse.ok) {
        s.dns_result_ip = ip;
        s.dns_state = DnsState.done;
    } else if (r == DnsParse.failed) {
        s.dns_state = DnsState.failed;
    }
}

fn processUdp(s: *TcpipStack, src_ip: u32, udp: []const u8) !void {
    if (udp.len < UDP_HDR_LEN) return error.Corrupt;
    const ulen: usize = @intCast(usize, load16be(udp, 4));
    if (ulen < UDP_HDR_LEN or ulen > udp.len) return error.Corrupt;

    const seg = udp[0..ulen];
    if (!udpChecksumValid(src_ip, s.cfg.ip, seg)) return error.Corrupt;

    const src_port = load16be(seg, 0);
    const dst_port = load16be(seg, 2);
    const payload = seg[UDP_HDR_LEN..];

    if (dst_port == DNS_LOCAL_PORT and src_ip == s.cfg.dns_server and src_port == DNS_SERVER_PORT and s.dns_state == .pending) {
        processDnsAnswer(s, payload);
        return;
    }

    var i: usize = 0;
    while (i < s.udp_count) : (i += 1) {
        const p = &s.udp_sockets[i];
        if (!p.in_use or p.local_port != dst_port) continue;
        var n = payload.len;
        if (n > UDP_MAX_PAYLOAD) n = UDP_MAX_PAYLOAD;
        var k: usize = 0;
        while (k < n) : (k += 1) p.rx_buf[k] = payload[k];
        p.rx_valid = true;
        p.rx_ip = src_ip;
        p.rx_port = src_port;
        p.rx_len = n;
        return;
    }
}

fn processIcmp(s: *TcpipStack, src_ip: u32, now_ms: u64, icmp: []const u8) !void {
    if (icmp.len < 8) return error.Corrupt;
    if (foldChecksum(sumWords(icmp)) != 0xFFFF) return error.Corrupt;
    if (icmp[0] != ICMP_ECHO_REPLY or icmp[1] != 0) return;

    if (s.icmp_state != .pending) return;
    if (src_ip != s.icmp_ip) return;
    if (load16be(icmp, 4) != ICMP_ID) return;
    if (load16be(icmp, 6) != s.icmp_seq) return;

    var rtt: u32 = 0;
    if (now_ms >= s.icmp_last_sent_ms) {
        const d = now_ms - s.icmp_last_sent_ms;
        if (d > 0xFFFFFFFF) {
            rtt = 0xFFFFFFFF;
        } else {
            rtt = @intCast(u32, d);
        }
    }
    s.icmp_rtt = rtt;
    s.icmp_state = .done;
}

fn serveUdp(s: *TcpipStack, now_ms: u64, out: []u8) !?[]const u8 {
    _ = now_ms;
    var i: usize = 0;
    while (i < s.udp_count) : (i += 1) {
        const p = &s.udp_sockets[i];
        if (!p.in_use or !p.tx_pending) continue;
        const pkt = try buildUdpPacket(s, out, p.tx_ip, p.tx_port, p.local_port, p.tx_buf[0..p.tx_len]);
        p.tx_pending = false;
        return pkt;
    }
    return null;
}

fn serveDns(s: *TcpipStack, now_ms: u64, out: []u8) !?[]const u8 {
    if (s.dns_state != .pending) return null;

    if (!s.dns_sent) {
        const pkt = try buildUdpPacket(s, out, s.cfg.dns_server, DNS_SERVER_PORT, DNS_LOCAL_PORT, s.dns_query[0..s.dns_query_len]);
        s.dns_sent = true;
        s.dns_tries = 1;
        s.dns_next_ms = now_ms + DNS_RETRY_MS;
        return pkt;
    }

    if (now_ms >= s.dns_next_ms) {
        if (s.dns_tries >= DNS_MAX_TRIES) {
            s.dns_state = .failed;
            return null;
        }
        const pkt = try buildUdpPacket(s, out, s.cfg.dns_server, DNS_SERVER_PORT, DNS_LOCAL_PORT, s.dns_query[0..s.dns_query_len]);
        s.dns_tries += 1;
        s.dns_next_ms = now_ms + DNS_RETRY_MS;
        return pkt;
    }
    return null;
}

fn serveIcmp(s: *TcpipStack, now_ms: u64, out: []u8) !?[]const u8 {
    if (s.icmp_state != .pending) return null;

    if (!s.icmp_sent) {
        const pkt = try buildIcmpPacket(s, out, s.icmp_seq);
        s.icmp_sent = true;
        s.icmp_tries = 1;
        s.icmp_last_sent_ms = now_ms;
        s.icmp_next_ms = now_ms + ICMP_RETRY_MS;
        return pkt;
    }

    if (now_ms >= s.icmp_next_ms) {
        if (s.icmp_tries >= ICMP_MAX_TRIES) {
            s.icmp_state = .failed;
            return null;
        }
        const pkt = try buildIcmpPacket(s, out, s.icmp_seq);
        s.icmp_tries += 1;
        s.icmp_last_sent_ms = now_ms;
        s.icmp_next_ms = now_ms + ICMP_RETRY_MS;
        return pkt;
    }
    return null;
}

pub fn udpOpen(s: *TcpipStack, local_port: u16) !u32 {
    var i: usize = 0;
    while (i < s.udp_count) : (i += 1) {
        if (!s.udp_sockets[i].in_use) {
            const p = &s.udp_sockets[i];
            zeroUdp(p);
            p.in_use = true;
            p.id = s.next_id;
            s.next_id +%= 1;
            if (s.next_id == 0) s.next_id = 1;
            p.local_ip = s.cfg.ip;
            if (local_port == 0) {
                p.local_port = @intCast(u16, (49152 + @intCast(u32, i)) & 0xFFFF);
            } else {
                p.local_port = local_port;
            }
            return p.id;
        }
    }
    return error.OutOfMemory;
}

pub fn udpSendTo(s: *TcpipStack, sock: u32, ip: u32, port: u16, data: []const u8) !void {
    const p = getUdp(s, sock) orelse return error.Closed;
    if (!routeOk(s, ip)) return error.NoRoute;
    if (data.len > UDP_MAX_PAYLOAD) return error.OutputTooSmall;
    if (IP_HDR_LEN + UDP_HDR_LEN + data.len > @intCast(usize, s.cfg.mtu)) return error.OutputTooSmall;
    if (p.tx_pending) return error.OutputTooSmall;

    var i: usize = 0;
    while (i < data.len) : (i += 1) p.tx_buf[i] = data[i];
    p.tx_len = data.len;
    p.tx_ip = ip;
    p.tx_port = port;
    p.tx_pending = true;
}

pub fn udpRecvFrom(s: *TcpipStack, sock: u32, out: []u8, ip: *u32, port: *u16) !usize {
    const p = getUdp(s, sock) orelse return error.Closed;
    if (!p.rx_valid) {
        ip.* = 0;
        port.* = 0;
        return 0;
    }

    var n = p.rx_len;
    if (n > out.len) n = out.len;
    var i: usize = 0;
    while (i < n) : (i += 1) out[i] = p.rx_buf[i];
    p.rx_valid = false;
    ip.* = p.rx_ip;
    port.* = p.rx_port;
    return n;
}

fn dnsLower(c: u8) u8 {
    if (c >= 65 and c <= 90) return c + 32;
    return c;
}

fn dnsNameMatches(msg: []const u8, off: *usize, expected: []const u8) bool {
    var p = off.*;
    var ep: usize = 0;
    var jumps: u32 = 0;
    var have_end = false;
    var end_off: usize = 0;
    while (true) {
        if (p >= msg.len) return false;
        const b = msg[p];
        if ((b & 0xC0) == 0xC0) {
            if (p + 1 >= msg.len) return false;
            const ptr = (@intCast(usize, b & 0x3F) << 8) | @intCast(usize, msg[p + 1]);
            if (ptr >= p or ptr >= msg.len) return false;
            if (!have_end) {
                end_off = p + 2;
                have_end = true;
            }
            p = ptr;
            jumps += 1;
            if (jumps > 16) return false;
            continue;
        }
        if ((b & 0xC0) != 0) return false;
        if (ep >= expected.len) return false;
        if (expected[ep] != b) return false;
        const l = @intCast(usize, b);
        p += 1;
        ep += 1;
        if (l == 0) {
            if (!have_end) {
                end_off = p;
                have_end = true;
            }
            off.* = end_off;
            return ep == expected.len;
        }
        if (p + l > msg.len) return false;
        if (ep + l > expected.len) return false;
        var k: usize = 0;
        while (k < l) : (k += 1) {
            if (dnsLower(msg[p + k]) != dnsLower(expected[ep + k])) return false;
        }
        p += l;
        ep += l;
    }
    return false;
}

const DnsParse = enum { ignored, ok, failed };

fn parseDnsAnswer(msg: []const u8, expect_id: u16, expected: []const u8, out_ip: *u32) DnsParse {
    if (msg.len < 12) return .failed;
    if (load16be(msg, 0) != expect_id) return .ignored;

    const flags = load16be(msg, 2);
    if ((flags & 0x8000) == 0) return .ignored;
    if ((flags & 0x000F) != 0) return .failed;

    const qd = load16be(msg, 4);
    const an = load16be(msg, 6);
    if (qd != 1) return .failed;

    var off: usize = 12;
    if (!dnsNameMatches(msg, &off, expected)) return .failed;
    if (off + 4 > msg.len) return .failed;
    if (load16be(msg, off) != 1) return .failed;
    if (load16be(msg, off + 2) != 1) return .failed;
    off += 4;

    if (an == 0) return .failed;

    var found = false;
    var i: u32 = 0;
    while (i < an and i < DNS_MAX_ANSWERS) : (i += 1) {
        if (!dnsNameMatches(msg, &off, expected)) return .failed;
        if (off + 10 > msg.len) return .failed;
        const atype = load16be(msg, off);
        const aclass = load16be(msg, off + 2);
        const rdlen: usize = @intCast(usize, load16be(msg, off + 8));
        off += 10;
        if (off + rdlen > msg.len) return .failed;
        if (atype == 1 and aclass == 1 and rdlen == 4) {
            if (!found) {
                out_ip.* = load32be(msg, off);
                found = true;
            }
        }
        off += rdlen;
    }

    if (!found) return .failed;
    return .ok;
}

fn dnsBuildQuery(s: *TcpipStack, name: []const u8) !void {
    var n: usize = 12;
    var wire: usize = 0;
    var i: usize = 0;
    while (i < name.len) {
        var j = i;
        while (j < name.len and name[j] != '.') j += 1;
        const l = j - i;
        if (l == 0) {
            if (j == name.len) break;
            return error.DnsFailed;
        }
        if (l > 63) return error.DnsFailed;
        if (n + 1 + l + 1 + 4 > DNS_QUERY_CAP) return error.DnsFailed;
        if (wire + 1 + l + 1 > DNS_NAME_MAX) return error.DnsFailed;
        s.dns_query[n] = @intCast(u8, l);
        n += 1;
        var k: usize = 0;
        while (k < l) : (k += 1) s.dns_query[n + k] = name[i + k];
        n += l;
        wire += 1 + l;
        i = j;
        if (i < name.len and name[i] == '.') i += 1;
        if (i == name.len) break;
    }
    if (n == 12) return error.DnsFailed;

    s.dns_query[n] = 0;
    n += 1;
    s.dns_qname_len = n - 12;
    store16be(s.dns_query[0..], n, 1);
    store16be(s.dns_query[0..], n + 2, 1);
    n += 4;

    s.dns_id +%= 1;
    if (s.dns_id == 0) s.dns_id = 1;
    const id = s.dns_id;
    store16be(s.dns_query[0..], 0, id);
    store16be(s.dns_query[0..], 2, 0x0100);
    store16be(s.dns_query[0..], 4, 1);
    store16be(s.dns_query[0..], 6, 0);
    store16be(s.dns_query[0..], 8, 0);
    store16be(s.dns_query[0..], 10, 0);

    s.dns_query_id = id;
    s.dns_query_len = n;
    s.dns_result_ip = 0;
}

pub fn dnsResolve(s: *TcpipStack, name: []const u8, out_ip: *u32) !void {
    if (s.dns_state == .done) {
        out_ip.* = s.dns_result_ip;
        s.dns_state = .idle;
        return;
    }
    if (s.dns_state == .failed) {
        s.dns_state = .idle;
        return error.DnsFailed;
    }
    if (s.dns_state == .pending) return error.Timeout;
    if (!routeOk(s, s.cfg.dns_server)) return error.NoRoute;

    try dnsBuildQuery(s, name);
    s.dns_state = .pending;
    s.dns_sent = false;
    s.dns_tries = 0;
    s.dns_next_ms = 0;
    return error.Timeout;
}

pub fn icmpPing(s: *TcpipStack, ip: u32, now_ms: u64) !u32 {
    if (s.icmp_state == .done) {
        const rtt = s.icmp_rtt;
        s.icmp_state = .idle;
        return rtt;
    }
    if (s.icmp_state == .failed) {
        s.icmp_state = .idle;
        return error.Timeout;
    }
    if (s.icmp_state == .pending) return error.Timeout;
    if (!routeOk(s, ip)) return error.NoRoute;

    s.icmp_ip = ip;
    s.icmp_seq +%= 1;
    if (s.icmp_seq == 0) s.icmp_seq = 1;
    s.icmp_state = .pending;
    s.icmp_sent = false;
    s.icmp_tries = 0;
    s.icmp_last_sent_ms = now_ms;
    s.icmp_next_ms = now_ms;
    s.icmp_rtt = 0;
    return error.Timeout;
}
