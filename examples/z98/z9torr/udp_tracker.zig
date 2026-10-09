// udp_tracker.zig — z9torr M4: UDP tracker announce (BEP 15).
//
// Spec 2026-10-09 §4.3. Implements the two-step BEP 15 exchange over `std_net`
// UDP and returns the same `tracker.AnnounceResult` / `tracker.PeerAddr` shape
// the M0 HTTP tracker produces, so `main.zig` can feed either path into the M3
// scheduler unchanged.
//
// Connect request  (16 B): u64 protocol_id=0x41727101980, u32 action=0, u32 txn
// Connect response (16 B): u32 action=0, u32 txn, u64 connection_id
// Announce request (98 B): u64 connection_id, u32 action=1, u32 txn, 20B
//   info_hash, 20B peer_id, u64 downloaded, u64 left, u64 uploaded, u32 event,
//   u32 ip=0, u32 key, i32 num_want=-1, u16 port
// Announce response (>=20 B): u32 action=1, u32 txn, u32 interval, u32 leechers,
//   u32 seeders, peers: 6*N bytes (4B network-order IPv4 + 2B big-endian port)
// Error response (>=8 B): u32 action=3, u32 txn, message
//
// All multi-byte fields are BIG-ENDIAN. Every request carries a transaction id;
// a datagram is accepted only when its id matches. Requests are retried with a
// receive timeout (`udpSetTimeout`); the connect response's connection id is
// carried into the announce request.
//
// The public signature is exactly the plan's:
//   announceUdp(arena, tracker_url, info_hash, peer_id, port, stats)
// BEP 15's optional `event` field is sent as 0 (none): the pinned signature
// carries no event, and the scheduler only needs the returned peer list.
//
// Z98 rules: free functions only, no method syntax, no generics, strict
// `@intCast`, every `switch` needs `else`, string literals via
// `var s: []const u8 = "...";`. D2: the only slice types here are `[]u8` /
// `[]const u8` (primitive) and `[]tracker.PeerAddr` (named, returned by
// `tracker.parseCompactPeers`). No suspension is involved, so D3/D4 do not
// apply; every buffer is function-local.

const std = @import("std");
const std_net = @import("std_net");
const tracker = @import("tracker.zig");
const logmod = @import("log.zig");

const CONNECT_ACTION: u32 = 0;
const ANNOUNCE_ACTION: u32 = 1;
const ERROR_ACTION: u32 = 3;

// BEP 15 magic protocol id, the first 8 bytes of a connect request.
const PROTOCOL_ID: u64 = 0x41727101980;

// BEP 15 `num_want = -1` (tracker default) as its u32 bit pattern.
const NUM_WANT_ANY: u32 = 4294967295;

const CONNECT_REQ_LEN: usize = 16;
const ANNOUNCE_REQ_LEN: usize = 98;
const HASH_LEN: usize = 20;

// Fixed receive buffer: comfortably above a default announce (20 + 6*N). The
// client asks for the tracker default; a truncated datagram (not detectable on
// POSIX) simply yields a non-multiple-of-6 peer blob and `BadResponse`.
const RECV_MAX: usize = 4096;

// Retry policy: short attempts so a silent tracker fails fast rather than
// parking the (single-threaded) client.
const TIMEOUT_MS: u32 = 2000;
const MAX_ATTEMPTS: u32 = 3;
const RECV_PER_ATTEMPT: u32 = 4;

// Transaction-id generator state. A per-process counter mixed with the clock on
// first use is enough to distinguish replies from stale datagrams.
var g_txn: u32 = 0;

fn nextTxn() u32 {
    var s: u32 = g_txn;
    if (s == 0) {
        s = std.time.ticksMs() | @intCast(u32, 1);
    }
    // Wraps by C semantics after lowering (same idiom as main.makePeerId).
    s = s * @intCast(u32, 1664525) + @intCast(u32, 1013904223);
    g_txn = s;
    return s | @intCast(u32, 1);
}

fn rdU32(b: []const u8, off: usize) u32 {
    return (@intCast(u32, b[off]) << 24) | (@intCast(u32, b[off + 1]) << 16) |
        (@intCast(u32, b[off + 2]) << 8) | @intCast(u32, b[off + 3]);
}

fn rdU64(b: []const u8, off: usize) u64 {
    return (@intCast(u64, b[off]) << 56) | (@intCast(u64, b[off + 1]) << 48) |
        (@intCast(u64, b[off + 2]) << 40) | (@intCast(u64, b[off + 3]) << 32) |
        (@intCast(u64, b[off + 4]) << 24) | (@intCast(u64, b[off + 5]) << 16) |
        (@intCast(u64, b[off + 6]) << 8) | @intCast(u64, b[off + 7]);
}

fn wrU16(b: []u8, off: usize, v: u16) void {
    b[off] = @intCast(u8, (v >> 8) & @intCast(u16, 0xFF));
    b[off + 1] = @intCast(u8, v & @intCast(u16, 0xFF));
}

fn wrU32(b: []u8, off: usize, v: u32) void {
    b[off] = @intCast(u8, (v >> 24) & @intCast(u32, 0xFF));
    b[off + 1] = @intCast(u8, (v >> 16) & @intCast(u32, 0xFF));
    b[off + 2] = @intCast(u8, (v >> 8) & @intCast(u32, 0xFF));
    b[off + 3] = @intCast(u8, v & @intCast(u32, 0xFF));
}

fn wrU64(b: []u8, off: usize, v: u64) void {
    b[off] = @intCast(u8, (v >> 56) & @intCast(u64, 0xFF));
    b[off + 1] = @intCast(u8, (v >> 48) & @intCast(u64, 0xFF));
    b[off + 2] = @intCast(u8, (v >> 40) & @intCast(u64, 0xFF));
    b[off + 3] = @intCast(u8, (v >> 32) & @intCast(u64, 0xFF));
    b[off + 4] = @intCast(u8, (v >> 24) & @intCast(u64, 0xFF));
    b[off + 5] = @intCast(u8, (v >> 16) & @intCast(u64, 0xFF));
    b[off + 6] = @intCast(u8, (v >> 8) & @intCast(u64, 0xFF));
    b[off + 7] = @intCast(u8, v & @intCast(u64, 0xFF));
}

// Parse `udp://host[:port][/path]`. `host_start`/`host_len` delimit the host
// inside `url`; `port` defaults to 80 when omitted. Returns false on a missing/
// wrong scheme or an empty host / non-numeric port.
fn parseUdpUrl(url: []const u8, host_start: *usize, host_len: *usize, port: *u16) bool {
    var pre: []const u8 = "udp://";
    if (url.len <= pre.len) return false;
    var i: usize = 0;
    while (i < pre.len) : (i += 1) {
        if (url[i] != pre[i]) return false;
    }
    var hb: usize = pre.len;
    i = hb;
    while (i < url.len and url[i] != ':' and url[i] != '/') : (i += 1) {}
    if (i == hb) return false;
    host_start.* = hb;
    host_len.* = i - hb;

    var p: u16 = 80;
    if (i < url.len and url[i] == ':') {
        i += 1;
        var ps: usize = i;
        var v: u32 = 0;
        while (i < url.len and url[i] >= '0' and url[i] <= '9') : (i += 1) {
            v = v * @intCast(u32, 10) + @intCast(u32, url[i] - '0');
            if (v > 65535) return false;
        }
        if (i == ps) return false;
        p = @intCast(u16, v);
    }
    port.* = p;
    return true;
}

// `std_net.resolve` returns the network-order IPv4 image; `udpSendTo` wants the
// dotted-quad struct. Convert between the two conventions (see std_net's
// `ipToU32`/`resolve`).
fn ipBeToAddr(ip_be: u32) std_net.IpAddr {
    return std_net.IpAddr{
        .a = @intCast(u8, ip_be & @intCast(u32, 0xFF)),
        .b = @intCast(u8, (ip_be >> 8) & @intCast(u32, 0xFF)),
        .c = @intCast(u8, (ip_be >> 16) & @intCast(u32, 0xFF)),
        .d = @intCast(u8, (ip_be >> 24) & @intCast(u32, 0xFF)),
    };
}

// One bounded receive. Returns null on any error (a timeout is folded in: the
// caller retries the whole request rather than distinguishing error classes).
fn recvOne(sock: *std_net.Socket, buf: []u8, out_addr: *std_net.IpAddr, out_port: *u16) ?usize {
    var n: usize = std_net.udpRecvFrom(sock, buf, out_addr, out_port) catch {
        return null;
    };
    return n;
}

// Send `req` and wait for a matching response. On success `resp_len.*` is the
// datagram length and `resp` holds the raw bytes. An action-3 error datagram
// stores its message and returns `FailureReason`. Timeout after all attempts is
// `HttpFailed`.
fn exchange(sock: *std_net.Socket, addr: std_net.IpAddr, port: u16, req: []const u8, want_action: u32, txn: u32, resp: []u8, resp_len: *usize) tracker.TrackerError!void {
    var attempt: u32 = 0;
    while (attempt < MAX_ATTEMPTS) : (attempt += 1) {
        std_net.udpSendTo(sock, addr, port, req) catch {
            // send error: fall through to the next attempt
            continue;
        };
        var got: bool = false;
        var tries: u32 = 0;
        while (tries < RECV_PER_ATTEMPT and !got) : (tries += 1) {
            var fa: std_net.IpAddr = undefined;
            var fp: u16 = 0;
            if (recvOne(sock, resp, &fa, &fp)) |n| {
                if (n >= 8) {
                    var action: u32 = rdU32(resp, 0);
                    var rt: u32 = rdU32(resp, 4);
                    if (rt == txn) {
                        if (action == ERROR_ACTION) {
                            var msg: []const u8 = resp[8..n];
                            tracker.storeFailureReason(msg);
                            return error.FailureReason;
                        }
                        if (action == want_action) {
                            resp_len.* = n;
                            got = true;
                        }
                    }
                }
            } else {
                // timeout/error: stop receiving on this attempt
                tries = RECV_PER_ATTEMPT;
            }
        }
        if (got) return;
    }
    return error.HttpFailed;
}

// Map the shared `AnnounceEvent` onto the BEP 15 event codes. The two
// numberings are OPPOSITE for the meaningful values (BEP 15: 0=none,
// 1=completed, 2=started, 3=stopped), so this is an explicit map — never a raw
// enum cast.
fn bep15Event(event: tracker.AnnounceEvent) u32 {
    switch (event) {
        .started => return 2,
        .completed => return 1,
        else => return 0,
    }
}

pub fn announceUdp(arena: *std.arena.Arena, tracker_url: []const u8, info_hash: []const u8, peer_id: []const u8, port: u16, event: tracker.AnnounceEvent, stats: tracker.Stats) tracker.TrackerError!tracker.AnnounceResult {
    tracker.clearFailureReason();

    if (info_hash.len < HASH_LEN or peer_id.len < HASH_LEN) return error.BadResponse;

    var hs: usize = 0;
    var hl: usize = 0;
    var tport: u16 = 0;
    if (!parseUdpUrl(tracker_url, &hs, &hl, &tport)) return error.BadResponse;

    var ip_be: u32 = std_net.resolve(tracker_url[hs .. hs + hl]) catch {
        return error.HttpFailed;
    };
    var addr: std_net.IpAddr = ipBeToAddr(ip_be);

    var sock: std_net.Socket = std_net.udpBind(0) catch {
        return error.HttpFailed;
    };
    std_net.udpSetTimeout(&sock, TIMEOUT_MS) catch {
        std_net.close(sock);
        return error.HttpFailed;
    };

    // --- connect: obtain the 64-bit connection id ---------------------------
    var conn_id: u64 = 0;
    {
        var creq: [CONNECT_REQ_LEN]u8 = undefined;
        var ctxn: u32 = nextTxn();
        wrU64(creq[0..], 0, PROTOCOL_ID);
        wrU32(creq[0..], 8, CONNECT_ACTION);
        wrU32(creq[0..], 12, ctxn);
        var cresp: [RECV_MAX]u8 = undefined;
        var clen: usize = 0;
        exchange(&sock, addr, tport, creq[0..], CONNECT_ACTION, ctxn, cresp[0..], &clen) catch |e| {
            std_net.close(sock);
            return e;
        };
        if (clen < 16) {
            std_net.close(sock);
            return error.BadResponse;
        }
        conn_id = rdU64(cresp[0..], 8);
    }
    logmod.s("udp tracker connect ok");
    logmod.nl();

    // --- announce: send the compact request, parse compact peers ------------
    var areq: [ANNOUNCE_REQ_LEN]u8 = undefined;
    var atxn: u32 = nextTxn();
    wrU64(areq[0..], 0, conn_id);
    wrU32(areq[0..], 8, ANNOUNCE_ACTION);
    wrU32(areq[0..], 12, atxn);
    var hi: usize = 0;
    while (hi < HASH_LEN) : (hi += 1) {
        areq[16 + hi] = info_hash[hi];
        areq[36 + hi] = peer_id[hi];
    }
    wrU64(areq[0..], 56, stats.downloaded);
    wrU64(areq[0..], 64, stats.left);
    wrU64(areq[0..], 72, stats.uploaded);
    wrU32(areq[0..], 80, bep15Event(event));
    wrU32(areq[0..], 84, 0); // ip = 0 (use source address)
    wrU32(areq[0..], 88, nextTxn()); // key
    wrU32(areq[0..], 92, NUM_WANT_ANY);
    wrU16(areq[0..], 96, port);

    var aresp: [RECV_MAX]u8 = undefined;
    var alen: usize = 0;
    exchange(&sock, addr, tport, areq[0..], ANNOUNCE_ACTION, atxn, aresp[0..], &alen) catch |e| {
        std_net.close(sock);
        return e;
    };
    std_net.close(sock);

    if (alen < 20) return error.BadResponse;

    var result: tracker.AnnounceResult = undefined;
    result.interval = rdU32(aresp[0..], 8);
    result.min_interval = 0;
    result.incomplete = rdU32(aresp[0..], 12); // leechers
    result.complete = rdU32(aresp[0..], 16); // seeders
    result.tracker_id = null;
    result.peers = try tracker.parseCompactPeers(arena, aresp[20..alen]);

    logmod.s("udp announce peers=");
    logmod.u32v(@intCast(u32, result.peers.len));
    logmod.s(" interval=");
    logmod.u32v(result.interval);
    logmod.nl();
    return result;
}
