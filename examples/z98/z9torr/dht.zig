// dht.zig — z9torr: bootstrap-grade Kademlia DHT (BEP 5 / KRPC) peer discovery.
//
// Scope (M4 spec §4.4): enough of BEP 5 to learn peers for one info_hash from a
// few bootstrap nodes and to answer the four KRPC queries well enough to act as
// a (non-routing-maintaining) node in a gate. No persistent routing-table
// maintenance, no bucket tree, no token validation — a bounded most-recently-
// seen node list and a small per-torrent peer list.
//
// KRPC wire shapes pinned against BEP 5:
//   * every message is one bencoded dict;
//   * keys: `t` (transaction id, opaque string), `y` ("q" query / "r"
//     response / "e" error); a query carries `q` (verb) and `a` (args dict); a
//     response carries `r` (values dict);
//   * node id = 20 bytes; compact node info = 20 id + 4 IP + 2 port = 26 bytes;
//     compact peer info = 4 IP + 2 port = 6 bytes (both network-order on the
//     wire, stored here in the same `ip_be` byte image `tracker.PeerAddr` uses);
//   * verbs: ping / find_node / get_peers / announce_peer;
//   * get_peers response carries `token` plus either `values` (list of 6-byte
//     compact peers) or `nodes` (concatenated 26-byte compact nodes).
//
// Z98 rules: free functions only, no generics/`anytype`/`@Type`, strict
// `@intCast`, every `switch` has `else`, string literals via
// `var s: []const u8 = "...";`. D2: every slice element is a primitive
// (`[]u8`) or a named type (`[]bencode.Entry`, `[]bencode.Value`,
// `[]tracker.PeerAddr`).

const std = @import("std");
const bencode = @import("std_bencode");
const std_net = @import("std_net");
const tracker = @import("tracker.zig");

pub const NODE_ID_LEN: usize = 20;
pub const COMPACT_NODE_LEN: usize = 26;
pub const COMPACT_PEER_LEN: usize = 6;
pub const TABLE_MAX: usize = 32;
pub const PEERS_MAX: usize = 64;
pub const RECV_MAX: usize = 4096;

// A routing-table entry: node id + its UDP endpoint in the shared `ip_be`
// convention (first octet in the low byte).
pub const RNode = struct {
    id: [20]u8,
    ip_be: u32,
    port: u16,
};

pub const Dht = struct {
    sock: std_net.Socket,
    id: [20]u8,
    // Bootstrap-grade routing table: most-recently-seen nodes, bounded, deduped.
    table: [TABLE_MAX]RNode,
    table_count: u32,
    // The (single) info_hash this node can answer `get_peers` for, plus the
    // peers announced for it. Download-only client: one torrent at a time.
    peer_ih: [20]u8,
    has_peer_ih: bool,
    peers: [PEERS_MAX]tracker.PeerAddr,
    peers_count: u32,
};

pub const DhtError = error{
    NetFailed,
    OutOfMemory,
    BadMessage,
};

var g_empty: [1]u8 = undefined;

fn emptyBytes() []u8 {
    return g_empty[0..0];
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

// --- canonical bencoding check (tests) --------------------------------------
//
// `std_bencode.encode` emits dict keys in insertion order, but BEP 5/BEP 10
// require canonical (strictly ascending) keys. This recursive check decodes an
// already-encoded message and verifies every dict's keys are strictly
// ascending, so a regression in any builder's insertion order fails the gate.

fn keyStrictlyLess(a: []const u8, b: []const u8) bool {
    var n: usize = a.len;
    if (b.len < n) n = b.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (a[i] != b[i]) return a[i] < b[i];
    }
    return a.len < b.len;
}

fn dictKeysSorted(entries: []bencode.Entry) bool {
    var i: usize = 1;
    while (i < entries.len) : (i += 1) {
        if (!keyStrictlyLess(entries[i - 1].key, entries[i].key)) return false;
    }
    return true;
}

fn valueCanonical(v: bencode.Value) bool {
    switch (v) {
        .dict => |es| {
            if (!dictKeysSorted(es)) return false;
            var i: usize = 0;
            while (i < es.len) : (i += 1) {
                if (!valueCanonical(es[i].value)) return false;
            }
            return true;
        },
        .list => |items| {
            var i: usize = 0;
            while (i < items.len) : (i += 1) {
                if (!valueCanonical(items[i])) return false;
            }
            return true;
        },
        else => return true,
    }
}

pub fn canonicalDicts(arena: *std.arena.Arena, bytes: []const u8) bool {
    var root = bencode.decode(arena, bytes) catch return false;
    return valueCanonical(root);
}

// --- ip_be <-> std_net.IpAddr ----------------------------------------------

fn ipBeToAddr(ip_be: u32) std_net.IpAddr {
    return std_net.IpAddr{
        .a = @intCast(u8, ip_be & @intCast(u32, 0xFF)),
        .b = @intCast(u8, (ip_be >> 8) & @intCast(u32, 0xFF)),
        .c = @intCast(u8, (ip_be >> 16) & @intCast(u32, 0xFF)),
        .d = @intCast(u8, (ip_be >> 24) & @intCast(u32, 0xFF)),
    };
}

fn addrToIpBe(addr: std_net.IpAddr) u32 {
    return @intCast(u32, addr.a) | (@intCast(u32, addr.b) << 8) |
        (@intCast(u32, addr.c) << 16) | (@intCast(u32, addr.d) << 24);
}

fn readU16BE(b: []const u8) u16 {
    return (@intCast(u16, b[0]) << 8) | @intCast(u16, b[1]);
}

// Copy the 6-byte compact peer at `b[0..6]` into `out`.
fn compactPeerAt(b: []const u8, out: *tracker.PeerAddr) void {
    var ip_be: u32 = @intCast(u32, b[0]) | (@intCast(u32, b[1]) << 8) |
        (@intCast(u32, b[2]) << 16) | (@intCast(u32, b[3]) << 24);
    out.* = tracker.PeerAddr{ .ip_be = ip_be, .port = readU16BE(b[4..6]) };
}

fn writeCompactPeer(dst: []u8, addr: tracker.PeerAddr) void {
    dst[0] = @intCast(u8, addr.ip_be & @intCast(u32, 0xFF));
    dst[1] = @intCast(u8, (addr.ip_be >> 8) & @intCast(u32, 0xFF));
    dst[2] = @intCast(u8, (addr.ip_be >> 16) & @intCast(u32, 0xFF));
    dst[3] = @intCast(u8, (addr.ip_be >> 24) & @intCast(u32, 0xFF));
    dst[4] = @intCast(u8, (addr.port >> 8) & @intCast(u16, 0xFF));
    dst[5] = @intCast(u8, addr.port & @intCast(u16, 0xFF));
}

// --- bencode helpers --------------------------------------------------------

fn dictGetBytes(entries: []bencode.Entry, key: []const u8, out: *[]const u8) bool {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eqBytes(entries[i].key, key)) {
            switch (entries[i].value) {
                .bytes => |b| {
                    out.* = b;
                    return true;
                },
                else => return false,
            }
        }
    }
    return false;
}

fn dictGetInt(entries: []bencode.Entry, key: []const u8, out: *i64) bool {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eqBytes(entries[i].key, key)) {
            switch (entries[i].value) {
                .int_val => |n| {
                    out.* = n;
                    return true;
                },
                else => return false,
            }
        }
    }
    return false;
}

fn dictGetDict(entries: []bencode.Entry, key: []const u8, out: *[]bencode.Entry) bool {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eqBytes(entries[i].key, key)) {
            switch (entries[i].value) {
                .dict => |d| {
                    out.* = d;
                    return true;
                },
                else => return false,
            }
        }
    }
    return false;
}

fn dictGetList(entries: []bencode.Entry, key: []const u8, out: *[]bencode.Value) bool {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eqBytes(entries[i].key, key)) {
            switch (entries[i].value) {
                .list => |l| {
                    out.* = l;
                    return true;
                },
                else => return false,
            }
        }
    }
    return false;
}

// Value/Entry constructors. Z98 cannot zero-initialise a fixed array of
// `bencode.Entry` (its union `value` field lowers to `= 0`), so every Entry
// array below is built with a full array literal instead of `undefined`.
fn bv(b: []const u8) bencode.Value {
    return bencode.Value{ .bytes = b };
}

fn bi(n: i64) bencode.Value {
    return bencode.Value{ .int_val = n };
}

fn bd(entries: []bencode.Entry) bencode.Value {
    return bencode.Value{ .dict = entries };
}

fn be(k: []const u8, v: bencode.Value) bencode.Entry {
    return bencode.Entry{ .key = k, .value = v };
}

fn allocValues(arena: *std.arena.Arena, n: usize) DhtError![]bencode.Value {
    var raw = std.arena.alloc(arena, n * @sizeOf(bencode.Value)) catch return error.OutOfMemory;
    return @ptrCast([*]bencode.Value, raw)[0..n];
}

// --- node / peer table ------------------------------------------------------

pub fn dhtAddNode(d: *Dht, id: []const u8, ip_be: u32, port: u16) bool {
    if (id.len != NODE_ID_LEN) return false;
    var i: u32 = 0;
    while (i < d.table_count) : (i += 1) {
        var u: usize = @intCast(usize, i);
        if (d.table[u].ip_be == ip_be and d.table[u].port == port) return false;
    }
    if (d.table_count >= @intCast(u32, TABLE_MAX)) return false;
    var ui: usize = @intCast(usize, d.table_count);
    var k: usize = 0;
    while (k < NODE_ID_LEN) : (k += 1) {
        d.table[ui].id[k] = id[k];
    }
    d.table[ui].ip_be = ip_be;
    d.table[ui].port = port;
    d.table_count += 1;
    return true;
}

pub fn dhtAddPeer(d: *Dht, ip_be: u32, port: u16) bool {
    var i: u32 = 0;
    while (i < d.peers_count) : (i += 1) {
        var u: usize = @intCast(usize, i);
        if (d.peers[u].ip_be == ip_be and d.peers[u].port == port) return false;
    }
    if (d.peers_count >= @intCast(u32, PEERS_MAX)) return false;
    var ui: usize = @intCast(usize, d.peers_count);
    d.peers[ui] = tracker.PeerAddr{ .ip_be = ip_be, .port = port };
    d.peers_count += 1;
    return true;
}

// Bind the node's UDP socket (port 0 = any ephemeral port) and seed its id.
pub fn dhtInit(d: *Dht, port: u16, id: [20]u8) DhtError!void {
    d.sock = std_net.udpBind(port) catch return error.NetFailed;
    var i: usize = 0;
    while (i < NODE_ID_LEN) : (i += 1) {
        d.id[i] = id[i];
        d.peer_ih[i] = 0;
    }
    d.table_count = 0;
    d.peers_count = 0;
    d.has_peer_ih = false;
}

// --- KRPC query builders ----------------------------------------------------

fn wrapQuery(arena: *std.arena.Arena, tid: []const u8, verb: []const u8, a_entries: []bencode.Entry) []u8 {
    // BEP 5 requires canonical bencoding: dict keys strictly ascending. The
    // encoder emits insertion order, so insert in sorted order (a,q,t,y).
    var entries: [4]bencode.Entry = [4]bencode.Entry{
        be("a", bd(a_entries)),
        be("q", bv(verb)),
        be("t", bv(tid)),
        be("y", bv("q")),
    };
    var root: bencode.Value = bd(entries[0..4]);
    return bencode.encode(arena, root) catch return emptyBytes();
}

pub fn makePing(arena: *std.arena.Arena, tid: []const u8, id: []const u8) []u8 {
    var a: [1]bencode.Entry = [1]bencode.Entry{
        be("id", bv(id)),
    };
    return wrapQuery(arena, tid, "ping", a[0..1]);
}

pub fn makeFindNode(arena: *std.arena.Arena, tid: []const u8, id: []const u8, target: []const u8) []u8 {
    var a: [2]bencode.Entry = [2]bencode.Entry{
        be("id", bv(id)),
        be("target", bv(target)),
    };
    return wrapQuery(arena, tid, "find_node", a[0..2]);
}

pub fn makeGetPeers(arena: *std.arena.Arena, tid: []const u8, id: []const u8, info_hash: []const u8) []u8 {
    var a: [2]bencode.Entry = [2]bencode.Entry{
        be("id", bv(id)),
        be("info_hash", bv(info_hash)),
    };
    return wrapQuery(arena, tid, "get_peers", a[0..2]);
}

pub fn makeAnnouncePeer(arena: *std.arena.Arena, tid: []const u8, id: []const u8, info_hash: []const u8, port: u16, token: []const u8) []u8 {
    // Sorted: id, implied_port, info_hash, port, token.
    var a: [5]bencode.Entry = [5]bencode.Entry{
        be("id", bv(id)),
        be("implied_port", bi(0)),
        be("info_hash", bv(info_hash)),
        be("port", bi(@intCast(i64, port))),
        be("token", bv(token)),
    };
    return wrapQuery(arena, tid, "announce_peer", a[0..5]);
}

// --- KRPC response builders -------------------------------------------------

fn wrapResponse(arena: *std.arena.Arena, tid: []const u8, r_entries: []bencode.Entry) []u8 {
    // Canonical response keys: r,t,y.
    var entries: [3]bencode.Entry = [3]bencode.Entry{
        be("r", bd(r_entries)),
        be("t", bv(tid)),
        be("y", bv("r")),
    };
    var root: bencode.Value = bd(entries[0..3]);
    return bencode.encode(arena, root) catch return emptyBytes();
}

fn buildIdResp(arena: *std.arena.Arena, d: *Dht, tid: []const u8) []u8 {
    var r: [1]bencode.Entry = [1]bencode.Entry{
        be("id", bv(d.id[0..])),
    };
    return wrapResponse(arena, tid, r[0..1]);
}

// Concatenate the routing table into 26-byte compact node records in `dst`;
// returns the byte length written.
fn packNodes(d: *Dht, dst: []u8) usize {
    var n: usize = 0;
    var i: u32 = 0;
    while (i < d.table_count) : (i += 1) {
        var u: usize = @intCast(usize, i);
        var off: usize = n * COMPACT_NODE_LEN;
        var k: usize = 0;
        while (k < NODE_ID_LEN) : (k += 1) {
            dst[off + k] = d.table[u].id[k];
        }
        dst[off + 20] = @intCast(u8, d.table[u].ip_be & @intCast(u32, 0xFF));
        dst[off + 21] = @intCast(u8, (d.table[u].ip_be >> 8) & @intCast(u32, 0xFF));
        dst[off + 22] = @intCast(u8, (d.table[u].ip_be >> 16) & @intCast(u32, 0xFF));
        dst[off + 23] = @intCast(u8, (d.table[u].ip_be >> 24) & @intCast(u32, 0xFF));
        dst[off + 24] = @intCast(u8, (d.table[u].port >> 8) & @intCast(u16, 0xFF));
        dst[off + 25] = @intCast(u8, d.table[u].port & @intCast(u16, 0xFF));
        n += 1;
    }
    return n * COMPACT_NODE_LEN;
}

fn buildNodesResp(arena: *std.arena.Arena, d: *Dht, tid: []const u8) []u8 {
    var nbuf: [TABLE_MAX * COMPACT_NODE_LEN]u8 = undefined;
    var len: usize = packNodes(d, nbuf[0..]);
    var r: [2]bencode.Entry = [2]bencode.Entry{
        be("id", bv(d.id[0..])),
        be("nodes", bv(nbuf[0..len])),
    };
    return wrapResponse(arena, tid, r[0..2]);
}

fn buildGetPeersResp(arena: *std.arena.Arena, d: *Dht, tid: []const u8, info_hash: []const u8) []u8 {
    var token: []const u8 = "z9t0";

    var serve_peers: bool = d.has_peer_ih and eqBytes(info_hash, d.peer_ih[0..]) and d.peers_count > 0;
    if (serve_peers) {
        var cbuf: [PEERS_MAX * COMPACT_PEER_LEN]u8 = undefined;
        var vals: []bencode.Value = allocValues(arena, @intCast(usize, d.peers_count)) catch return emptyBytes();
        var n: usize = 0;
        var i: u32 = 0;
        while (i < d.peers_count and n < PEERS_MAX) : (i += 1) {
            var u: usize = @intCast(usize, i);
            var off: usize = n * COMPACT_PEER_LEN;
            writeCompactPeer(cbuf[off .. off + COMPACT_PEER_LEN], d.peers[u]);
            vals[n] = bv(cbuf[off .. off + COMPACT_PEER_LEN]);
            n += 1;
        }
        var r: [3]bencode.Entry = [3]bencode.Entry{
            be("id", bv(d.id[0..])),
            be("token", bv(token)),
            be("values", bencode.Value{ .list = vals[0..n] }),
        };
        return wrapResponse(arena, tid, r[0..3]);
    }
    // No peers for this info_hash: return the closest nodes we know, plus the
    // token a subsequent announce_peer would need (BEP 5). Sorted: id,nodes,token.
    var nbuf: [TABLE_MAX * COMPACT_NODE_LEN]u8 = undefined;
    var len: usize = packNodes(d, nbuf[0..]);
    var rn: [3]bencode.Entry = [3]bencode.Entry{
        be("id", bv(d.id[0..])),
        be("nodes", bv(nbuf[0..len])),
        be("token", bv(token)),
    };
    return wrapResponse(arena, tid, rn[0..3]);
}

// --- datagram handling ------------------------------------------------------

// Handle one received KRPC datagram. Returns true when `out_resp` holds a
// bencoded response to send back to `from`/`from_port` (the caller owns the
// send). A response datagram (y == "r") is accepted into the routing table and
// returns false.
pub fn handleDatagram(arena: *std.arena.Arena, d: *Dht, data: []const u8, from: std_net.IpAddr, from_port: u16, out_resp: *[]u8) bool {
    var root = bencode.decode(arena, data) catch return false;
    var top: []bencode.Entry = undefined;
    switch (root) {
        .dict => |e| {
            top = e;
        },
        else => return false,
    }

    var y: []const u8 = "";
    if (!dictGetBytes(top, "y", &y)) return false;

    var tid: []const u8 = "";
    if (!dictGetBytes(top, "t", &tid)) return false;

    if (!(y.len == 1 and y[0] == 'q')) {
        // Response/error: learn the node if it named itself.
        var r: []bencode.Entry = undefined;
        if (dictGetDict(top, "r", &r)) {
            var nid: []const u8 = "";
            if (dictGetBytes(r, "id", &nid)) {
                _ = dhtAddNode(d, nid, addrToIpBe(from), from_port);
            }
        }
        return false;
    }

    var q: []const u8 = "";
    if (!dictGetBytes(top, "q", &q)) return false;
    var a: []bencode.Entry = undefined;
    if (!dictGetDict(top, "a", &a)) return false;

    // The sender's own id (if present) seeds our bounded routing table.
    var nid: []const u8 = "";
    if (dictGetBytes(a, "id", &nid)) {
        _ = dhtAddNode(d, nid, addrToIpBe(from), from_port);
    }

    if (eqBytes(q, "ping")) {
        out_resp.* = buildIdResp(arena, d, tid);
        return true;
    }
    if (eqBytes(q, "find_node")) {
        out_resp.* = buildNodesResp(arena, d, tid);
        return true;
    }
    if (eqBytes(q, "get_peers")) {
        var ih: []const u8 = "";
        if (!dictGetBytes(a, "info_hash", &ih)) return false;
        out_resp.* = buildGetPeersResp(arena, d, tid, ih);
        return true;
    }
    if (eqBytes(q, "announce_peer")) {
        var ih: []const u8 = "";
        _ = dictGetBytes(a, "info_hash", &ih);
        var port_v: i64 = 0;
        _ = dictGetInt(a, "port", &port_v);
        var implied: i64 = 0;
        _ = dictGetInt(a, "implied_port", &implied);
        var announced_port: u16 = 0;
        if (implied != 0) {
            announced_port = from_port;
        } else if (port_v > 0 and port_v <= 65535) {
            announced_port = @intCast(u16, port_v);
        }
        if (ih.len == NODE_ID_LEN) {
            var k: usize = 0;
            while (k < NODE_ID_LEN) : (k += 1) {
                d.peer_ih[k] = ih[k];
            }
            d.has_peer_ih = true;
        }
        if (announced_port != 0) {
            _ = dhtAddPeer(d, addrToIpBe(from), announced_port);
        }
        out_resp.* = buildIdResp(arena, d, tid);
        return true;
    }
    return false;
}

// Parse a KRPC response: fold any `nodes` into the routing table and copy any
// compact `values` peers into `out_peers`. When `expected_tid` is non-empty the
// response's `t` must equal it (BEP 5 transaction matching). Returns the peer
// count written.
pub fn parseResponse(arena: *std.arena.Arena, d: *Dht, data: []const u8, expected_tid: []const u8, out_peers: []tracker.PeerAddr) u32 {
    var root = bencode.decode(arena, data) catch return 0;
    var top: []bencode.Entry = undefined;
    switch (root) {
        .dict => |e| {
            top = e;
        },
        else => return 0,
    }
    var y: []const u8 = "";
    if (!dictGetBytes(top, "y", &y)) return 0;
    if (!(y.len == 1 and y[0] == 'r')) return 0;
    if (expected_tid.len > 0) {
        var rtid: []const u8 = "";
        if (!dictGetBytes(top, "t", &rtid)) return 0;
        if (!eqBytes(rtid, expected_tid)) return 0;
    }
    var r: []bencode.Entry = undefined;
    if (!dictGetDict(top, "r", &r)) return 0;

    var nodes: []const u8 = "";
    if (dictGetBytes(r, "nodes", &nodes)) {
        var n: usize = 0;
        while (n + COMPACT_NODE_LEN <= nodes.len) : (n += COMPACT_NODE_LEN) {
            var id: []const u8 = nodes[n .. n + NODE_ID_LEN];
            var ip_be: u32 = @intCast(u32, nodes[n + 20]) | (@intCast(u32, nodes[n + 21]) << 8) |
                (@intCast(u32, nodes[n + 22]) << 16) | (@intCast(u32, nodes[n + 23]) << 24);
            var port: u16 = readU16BE(nodes[n + 24 .. n + 26]);
            _ = dhtAddNode(d, id, ip_be, port);
        }
    }

    var count: u32 = 0;
    var items: []bencode.Value = undefined;
    if (dictGetList(r, "values", &items)) {
        var i: usize = 0;
        while (i < items.len and @intCast(usize, count) < out_peers.len) : (i += 1) {
            switch (items[i]) {
                .bytes => |b| {
                    if (b.len == COMPACT_PEER_LEN) {
                        var addr: tracker.PeerAddr = undefined;
                        compactPeerAt(b, &addr);
                        out_peers[@intCast(usize, count)] = addr;
                        count += 1;
                    }
                },
                else => {},
            }
        }
    }
    return count;
}

// --- high-level bootstrap discovery ----------------------------------------

fn parseU16(s: []const u8) ?u16 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        var c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > @intCast(u64, 65535)) return null;
    }
    return @intCast(u16, v);
}

fn queryBootstrap(arena: *std.arena.Arena, d: *Dht, hostport: []const u8, info_hash: []const u8, out_peers: []tracker.PeerAddr) u32 {
    if (out_peers.len == 0) return 0;
    var colon: usize = hostport.len;
    var i: usize = 0;
    while (i < hostport.len) : (i += 1) {
        if (hostport[i] == ':') {
            colon = i;
            break;
        }
    }
    var host: []const u8 = hostport[0..colon];
    var port: u16 = 6881;
    if (colon < hostport.len) {
        if (parseU16(hostport[colon + 1 ..])) |p| port = p;
    }
    if (host.len == 0) return 0;
    var ip_be: u32 = std_net.resolve(host) catch return 0;

    var tid: [4]u8 = [4]u8{ 'z', '9', 'd', '0' };
    var q: []u8 = makeGetPeers(arena, tid[0..], d.id[0..], info_hash);
    if (q.len == 0) return 0;
    std_net.udpSendTo(&d.sock, ipBeToAddr(ip_be), port, q) catch return 0;

    var buf: [RECV_MAX]u8 = undefined;
    var fa: std_net.IpAddr = undefined;
    var fp: u16 = 0;
    var n: usize = 0;
    n = std_net.udpRecvFrom(&d.sock, buf[0..], &fa, &fp) catch return 0;
    // Bootstrap-grade: accept only a reply from the queried endpoint whose
    // transaction id matches the query (BEP 5). No retry loop.
    if (addrToIpBe(fa) != ip_be or fp != port) return 0;
    return parseResponse(arena, d, buf[0..n], tid[0..], out_peers);
}

// Discover peers for `info_hash` from a comma-separated `host[:port]` list.
// Binds an ephemeral UDP socket; returns the number of peers written to `out`.
pub fn dhtDiscover(arena: *std.arena.Arena, bootstrap: []const u8, self_id: [20]u8, info_hash: []const u8, out: []tracker.PeerAddr) u32 {
    if (out.len == 0 or bootstrap.len == 0) return 0;
    var d: Dht = undefined;
    dhtInit(&d, 0, self_id) catch return 0;
    std_net.udpSetTimeout(&d.sock, 1500) catch {};
    var total: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= bootstrap.len) : (i += 1) {
        if (i == bootstrap.len or bootstrap[i] == ',') {
            var tok: []const u8 = bootstrap[start..i];
            start = i + 1;
            if (tok.len > 0 and total < out.len) {
                total += @intCast(usize, queryBootstrap(arena, &d, tok, info_hash, out[total..]));
            }
        }
    }
    std_net.close(d.sock);
    return @intCast(u32, total);
}

// --- in-process self-test (tier_dht) ----------------------------------------

var g_test_buf: [262144]u8 = undefined;

fn fillId(id: *[20]u8, seed: u32) void {
    var st: u32 = seed;
    if (st == 0) st = 1;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        st = st *% @intCast(u32, 1664525) +% @intCast(u32, 1013904223);
        id[i] = @intCast(u8, (st >> 16) & @intCast(u32, 0xFF));
    }
}

fn envU16(name: []const u8, def: u16) u16 {
    if (std.os.env(name)) |sv| {
        if (parseU16(sv)) |v| return v;
    }
    return def;
}

fn fail(msg: []const u8) void {
    var p: []const u8 = "dht selftest: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
}

// Two in-process DHT nodes: B knows a peer for an info_hash; A sends get_peers
// to B over real loopback UDP and must learn that peer from B's response.
pub fn selfTest() i32 {
    if (std_net.init() != 0) {
        fail("net init");
        return 1;
    }
    var port_a: u16 = envU16("Z9TORR_DHT_PORT_A", 6977);
    var port_b: u16 = envU16("Z9TORR_DHT_PORT_B", 6978);
    var arena: std.arena.Arena = std.arena.init(g_test_buf[0..]);

    var id_a: [20]u8 = undefined;
    var id_b: [20]u8 = undefined;
    fillId(&id_a, 11);
    fillId(&id_b, 22);

    var da: Dht = undefined;
    var db: Dht = undefined;
    dhtInit(&da, port_a, id_a) catch {
        fail("bind A");
        return 1;
    };
    dhtInit(&db, port_b, id_b) catch {
        fail("bind B");
        return 1;
    };
    std_net.udpSetTimeout(&da.sock, 2000) catch {};
    std_net.udpSetTimeout(&db.sock, 2000) catch {};

    var ih: [20]u8 = undefined;
    fillId(&ih, 77);
    var k: usize = 0;
    while (k < NODE_ID_LEN) : (k += 1) {
        db.peer_ih[k] = ih[k];
    }
    db.has_peer_ih = true;

    var want: tracker.PeerAddr = tracker.PeerAddr{ .ip_be = @intCast(u32, 0x0100007F), .port = 6881 };
    if (!dhtAddPeer(&db, want.ip_be, want.port)) {
        fail("register peer at B");
        return 1;
    }

    // 0. F1: every emitted KRPC dict must be canonically keyed (strictly
    //    ascending). Independently decode each builder's bytes and check.
    var c_tid: [4]u8 = [4]u8{ 'c', 'a', 'n', '0' };
    var cp: []u8 = makePing(&arena, c_tid[0..], da.id[0..]);
    var cf: []u8 = makeFindNode(&arena, c_tid[0..], da.id[0..], ih[0..]);
    var ca: []u8 = makeAnnouncePeer(&arena, c_tid[0..], da.id[0..], ih[0..], 6881, "z9t0");
    if (!canonicalDicts(&arena, cp) or !canonicalDicts(&arena, cf) or !canonicalDicts(&arena, ca)) {
        fail("a KRPC query builder emitted non-canonical keys");
        return 1;
    }

    // 1. A -> B: get_peers.
    var tid: [4]u8 = [4]u8{ 't', 'e', 's', 't' };
    var q: []u8 = makeGetPeers(&arena, tid[0..], da.id[0..], ih[0..]);
    if (!canonicalDicts(&arena, q)) {
        fail("get_peers query not canonical");
        return 1;
    }
    std_net.udpSendTo(&da.sock, ipBeToAddr(@intCast(u32, 0x0100007F)), port_b, q) catch {
        fail("send A->B");
        return 1;
    };

    var buf: [RECV_MAX]u8 = undefined;
    var fa: std_net.IpAddr = undefined;
    var fp: u16 = 0;
    const n = std_net.udpRecvFrom(&db.sock, buf[0..], &fa, &fp) catch {
        fail("recv at B");
        return 1;
    };
    if (n == 0) {
        fail("empty datagram at B");
        return 1;
    }

    // 2. B handles the query and replies to A.
    var resp: []u8 = undefined;
    if (!handleDatagram(&arena, &db, buf[0..n], fa, fp, &resp)) {
        fail("B produced no get_peers response");
        return 1;
    }
    if (!canonicalDicts(&arena, resp)) {
        fail("get_peers response not canonical");
        return 1;
    }
    std_net.udpSendTo(&db.sock, fa, fp, resp) catch {
        fail("send B->A");
        return 1;
    };

    // 3. A receives and parses; must learn the registered peer.
    var fa2: std_net.IpAddr = undefined;
    var fp2: u16 = 0;
    const n2 = std_net.udpRecvFrom(&da.sock, buf[0..], &fa2, &fp2) catch {
        fail("recv at A");
        return 1;
    };
    var got_raw = std.arena.alloc(&arena, PEERS_MAX * @sizeOf(tracker.PeerAddr)) catch {
        fail("alloc result peers");
        return 1;
    };
    var got: []tracker.PeerAddr = @ptrCast([*]tracker.PeerAddr, got_raw)[0..PEERS_MAX];
    // Pass the query's tid: the response must match it (BEP 5 transaction).
    const ng = parseResponse(&arena, &da, buf[0..n2], tid[0..], got);
    if (ng < 1) {
        fail("A learned no peer from get_peers values (or tid mismatch)");
        return 1;
    }
    if (got[0].ip_be != want.ip_be or got[0].port != want.port) {
        fail("A learned a different peer");
        return 1;
    }

    std_net.close(da.sock);
    std_net.close(db.sock);
    std_net.cleanup();
    var ok: []const u8 = "dht selftest: PASS (get_peers two-node discovery)\n";
    std.io.write(ok);
    return 0;
}
