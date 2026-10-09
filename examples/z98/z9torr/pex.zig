// pex.zig — z9torr: Peer Exchange (BEP 11) over the extension protocol (BEP 10).
//
// Scope (M4 spec §4.4): negotiate `ut_pex` via a BEP 10 extended handshake and
// feed peers named in a `ut_pex` message into the M3 `scheduler.addPeer`.
//
// Wire shapes pinned against BEP 10 / BEP 11:
//   * an "extended" wire message is id 20, then one byte `extended_id`, then a
//     bencoded payload;
//   * extended_id 0 is the extension handshake: `{"m":{"ut_pex":<id>},"v":...,
//     "p":...}`; every other extension message uses the id named in `m`;
//   * a `ut_pex` payload is `{"added":<6*N compact peers>,"added.f":<N flags>,
//     "dropped":<6*M compact peers>,"dropped.f":<M flags>}` (compact peer = 4B
//     network-order IPv4 + 2B BE port, stored here in the shared `ip_be` image).
//
// A download-only client never accepts inbound connections, so peers learned via
// PEX are only added to the scheduler's slot table (that is what M4 requires);
// a dead peer simply fails its own connect later, which the scheduler tolerates.
//
// Z98 rules: free functions only, no generics/`anytype`, strict `@intCast`,
// every `switch` has `else`, string literals via `var s: []const u8 = "...";`.
// D2: `[]u8` (primitive) and `[]bencode.Entry`/`[]bencode.Value` (named).

const std = @import("std");
const bencode = @import("std_bencode");
const tracker = @import("tracker.zig");
const scheduler = @import("scheduler.zig");
const torrent = @import("torrent.zig");
const dht = @import("dht.zig");

pub const COMPACT_PEER_LEN: usize = 6;
pub const EXT_HANDSHAKE_ID: u8 = 0;
pub const OUR_UT_PEX_ID: i64 = 1;

// Per-connection PEX negotiation state. Lives in the caller-owned `Peer`
// (D3/D4: stable address, no module globals across a suspension).
pub const PexState = struct {
    ut_pex_id: u8,
    negotiated: bool,
};

pub fn pexInit(p: *PexState) void {
    p.ut_pex_id = 0;
    p.negotiated = false;
}

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

// Value/Entry constructors. Z98 mis-lowers an inline union literal whose
// payload is a compile-time constant or a runtime slice-expression (it emits
// `payload = x` instead of `payload.bytes._0 = x`), so every union here is
// built through these runtime-parameter helpers. A fixed array of
// `bencode.Entry` is likewise always fully initialised (an `undefined` one
// lowers its union field to `= 0`).
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

fn peerFromCompact(b: []const u8) tracker.PeerAddr {
    var ip_be: u32 = @intCast(u32, b[0]) | (@intCast(u32, b[1]) << 8) |
        (@intCast(u32, b[2]) << 16) | (@intCast(u32, b[3]) << 24);
    var port: u16 = (@intCast(u16, b[4]) << 8) | @intCast(u16, b[5]);
    return tracker.PeerAddr{ .ip_be = ip_be, .port = port };
}

// Build our BEP 10 extended handshake payload (the bencoded body only; the
// caller frames it as wire id 20 + extended id 0): `{"m":{"ut_pex":1},
// "v":"z9torr","p":<listen_port>}`.
pub fn pexBuildHandshake(arena: *std.arena.Arena, listen_port: u16) []u8 {
    var m: [1]bencode.Entry = [1]bencode.Entry{
        be("ut_pex", bi(OUR_UT_PEX_ID)),
    };
    // Canonical BEP 10 handshake keys: m,p,v.
    var entries: [3]bencode.Entry = [3]bencode.Entry{
        be("m", bd(m[0..1])),
        be("p", bi(@intCast(i64, listen_port))),
        be("v", bv("z9torr")),
    };
    var root: bencode.Value = bd(entries[0..3]);
    return bencode.encode(arena, root) catch return emptyBytes();
}

// Parse "a.b.c.d[:port]" into a `PeerAddr` (ip_be image); default port 6881.
fn parsePeerSpec(s: []const u8) ?tracker.PeerAddr {
    var colon: usize = s.len;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == ':') {
            colon = i;
            break;
        }
    }
    var ip: [4]u8 = [4]u8{ 0, 0, 0, 0 };
    var val: u32 = 0;
    var oct: usize = 0;
    var seen: bool = false;
    i = 0;
    while (i < colon) : (i += 1) {
        var c: u8 = s[i];
        if (c >= '0' and c <= '9') {
            val = val * 10 + @intCast(u32, c - '0');
            if (val > 255) return null;
            seen = true;
        } else if (c == '.') {
            if (!seen or oct >= 4) return null;
            ip[oct] = @intCast(u8, val);
            oct += 1;
            val = 0;
            seen = false;
        } else {
            return null;
        }
    }
    if (!seen or oct != 3) return null;
    ip[3] = @intCast(u8, val);

    var port: u16 = 6881;
    if (colon < s.len) {
        var ps: []const u8 = s[colon + 1 ..];
        var pv: u32 = 0;
        var any: bool = false;
        var j: usize = 0;
        while (j < ps.len) : (j += 1) {
            var c2: u8 = ps[j];
            if (c2 < '0' or c2 > '9') return null;
            pv = pv * 10 + @intCast(u32, c2 - '0');
            if (pv > 65535) return null;
            any = true;
        }
        if (!any) return null;
        port = @intCast(u16, pv);
    }
    var ip_be: u32 = @intCast(u32, ip[0]) | (@intCast(u32, ip[1]) << 8) |
        (@intCast(u32, ip[2]) << 16) | (@intCast(u32, ip[3]) << 24);
    return tracker.PeerAddr{ .ip_be = ip_be, .port = port };
}

// Build a one-peer `ut_pex` body (canonical `{"added":<6 bytes>}`) from an
// "ip[:port]" spec. Used to send PEX and by the tier_pex injection hook.
pub fn pexBuildUtPex(arena: *std.arena.Arena, spec: []const u8) []u8 {
    if (parsePeerSpec(spec)) |a| {
        var added: [6]u8 = undefined;
        added[0] = @intCast(u8, a.ip_be & @intCast(u32, 0xFF));
        added[1] = @intCast(u8, (a.ip_be >> 8) & @intCast(u32, 0xFF));
        added[2] = @intCast(u8, (a.ip_be >> 16) & @intCast(u32, 0xFF));
        added[3] = @intCast(u8, (a.ip_be >> 24) & @intCast(u32, 0xFF));
        added[4] = @intCast(u8, (a.port >> 8) & @intCast(u16, 0xFF));
        added[5] = @intCast(u8, a.port & @intCast(u16, 0xFF));
        var entries: [1]bencode.Entry = [1]bencode.Entry{
            be("added", bv(added[0..6])),
        };
        var root: bencode.Value = bd(entries[0..1]);
        return bencode.encode(arena, root) catch return emptyBytes();
    }
    return emptyBytes();
}

// Parse a BEP 10 extension handshake body and adopt the peer's `ut_pex` id.
pub fn pexParseHandshake(arena: *std.arena.Arena, p: *PexState, body: []const u8) void {
    var root = bencode.decode(arena, body) catch return;
    var top: []bencode.Entry = undefined;
    switch (root) {
        .dict => |e| {
            top = e;
        },
        else => return,
    }
    var m: []bencode.Entry = undefined;
    if (!dictGetDict(top, "m", &m)) return;
    var v: i64 = 0;
    if (dictGetInt(m, "ut_pex", &v)) {
        if (v > 0 and v < 256) {
            p.ut_pex_id = @intCast(u8, v);
            p.negotiated = true;
        }
    }
}

// Parse a `ut_pex` body and add every `added` peer to the scheduler. Returns the
// number of peers actually accepted (duplicates/dead slots rejected). `dropped`
// is validated but is a no-op: the download-only scheduler has no
// remove-by-address API and the recent-address ring already suppresses re-adds.
pub fn pexParseUtPex(arena: *std.arena.Arena, s: *scheduler.Scheduler, body: []const u8) u32 {
    var root = bencode.decode(arena, body) catch return 0;
    var top: []bencode.Entry = undefined;
    switch (root) {
        .dict => |e| {
            top = e;
        },
        else => return 0,
    }

    var added: []const u8 = "";
    if (!dictGetBytes(top, "added", &added)) {
        // Still recognized as a ut_pex message (maybe drop-only); nothing to add.
        var dropped_only: []const u8 = "";
        _ = dictGetBytes(top, "dropped", &dropped_only);
        return 0;
    }
    var addedf: []const u8 = "";
    _ = dictGetBytes(top, "added.f", &addedf);

    var n: u32 = 0;
    var off: usize = 0;
    while (off + COMPACT_PEER_LEN <= added.len) : (off += COMPACT_PEER_LEN) {
        var addr: tracker.PeerAddr = peerFromCompact(added[off .. off + COMPACT_PEER_LEN]);
        if (addr.port == 0) continue;
        if (scheduler.addPeer(s, addr)) n += 1;
    }
    return n;
}

// Dispatch one extended message body (the bytes after the extended-id byte is
// NOT done here; `payload` is the full `Message.payload`: [extended_id, body...]).
// extended_id 0 negotiates; a subsequent message equal to the negotiated ut_pex
// id is parsed and fed to the scheduler. Returns the number of peers added.
pub fn pexOnExtended(arena: *std.arena.Arena, p: *PexState, s: *scheduler.Scheduler, payload: []const u8) u32 {
    if (payload.len < 1) return 0;
    var ext_id: u8 = payload[0];
    var body: []const u8 = payload[1..];
    if (ext_id == EXT_HANDSHAKE_ID) {
        pexParseHandshake(arena, p, body);
        return 0;
    }
    if (p.negotiated and ext_id == p.ut_pex_id) {
        return pexParseUtPex(arena, s, body);
    }
    return 0;
}

// Test hook: as if a peer had negotiated ut_pex and sent a one-peer `ut_pex`
// naming `spec` ("ip[:port]"). Feeds the scheduler exactly as a received
// message would, so tests/tier_pex.sh can prove PEX-learned peers are dialed.
pub fn pexInjectPeer(arena: *std.arena.Arena, p: *PexState, s: *scheduler.Scheduler, spec: []const u8) u32 {
    var body: []u8 = pexBuildUtPex(arena, spec);
    if (body.len == 0) return 0;
    p.negotiated = true;
    if (p.ut_pex_id == 0) p.ut_pex_id = 1;
    return pexParseUtPex(arena, s, body);
}

// --- in-process self-test (tier_pex) ----------------------------------------

var g_test_buf: [2097152]u8 = undefined;
var g_hashes: [120]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "pex selftest: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
}

fn makeTorrent() torrent.Torrent {
    var ih: [20]u8 = undefined;
    var z: usize = 0;
    while (z < 20) : (z += 1) ih[z] = 0;
    z = 0;
    while (z < 120) : (z += 1) g_hashes[z] = 0;
    var alist: [8][]const u8 = undefined;
    var e: []const u8 = "";
    z = 0;
    while (z < 8) : (z += 1) alist[z] = e;
    return torrent.Torrent{
        .announce = e,
        .announce_list = alist,
        .announce_count = 0,
        .info_hash = ih,
        .name = "pex",
        .piece_length = 1024,
        .piece_hashes = g_hashes[0..],
        .total_length = 6144,
    };
}

// Build a `[extended_id, body...]` buffer in `dst`, returning the used length.
fn extMessage(dst: []u8, ext_id: u8, body: []const u8) usize {
    dst[0] = ext_id;
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        dst[1 + i] = body[i];
    }
    return 1 + body.len;
}

pub fn selfTest() i32 {
    var arena: std.arena.Arena = std.arena.init(g_test_buf[0..]);
    var t: torrent.Torrent = makeTorrent();
    var s: scheduler.Scheduler = scheduler.schedulerInit(&arena, t, 8) catch {
        fail("schedulerInit");
        return 1;
    };
    var p: PexState = undefined;
    pexInit(&p);

    // 0. F1: emitted extended dicts must be canonically keyed. Decode each
    //    builder's bytes independently and verify strictly-ascending keys.
    var hsbuilt: []u8 = pexBuildHandshake(&arena, 6881);
    var upbuilt: []u8 = pexBuildUtPex(&arena, "127.0.0.1:6881");
    if (!dht.canonicalDicts(&arena, hsbuilt) or !dht.canonicalDicts(&arena, upbuilt)) {
        fail("emitted PEX dict not canonical");
        return 1;
    }

    // 1. BEP 10 handshake negotiates ut_pex = 3 and adds no peers.
    var hs_body: []const u8 = "d1:md6:ut_pexi3ee1:v6:z9torre";
    var msgbuf: [256]u8 = undefined;
    var hs_len: usize = extMessage(msgbuf[0..], EXT_HANDSHAKE_ID, hs_body);
    var added0: u32 = pexOnExtended(&arena, &p, &s, msgbuf[0..hs_len]);
    if (added0 != 0) {
        fail("handshake added peers");
        return 1;
    }
    if (!p.negotiated or p.ut_pex_id != 3) {
        fail("ut_pex id not negotiated");
        return 1;
    }
    if (s.active_peer_count != 0) {
        fail("handshake should leave the scheduler empty");
        return 1;
    }

    // 2. A ut_pex message with two `added` peers must add both.
    var added: [12]u8 = undefined;
    added[0] = 127;
    added[1] = 0;
    added[2] = 0;
    added[3] = 1;
    added[4] = @intCast(u8, 0x15);
    added[5] = @intCast(u8, 0xB3); // 127.0.0.1:5555
    added[6] = 10;
    added[7] = 0;
    added[8] = 0;
    added[9] = 1;
    added[10] = @intCast(u8, 0x1A);
    added[11] = @intCast(u8, 0x0A); // 10.0.0.1:6666
    var flags: [2]u8 = [2]u8{ 0, 0 };
    var entries: [3]bencode.Entry = [3]bencode.Entry{
        be("added", bv(added[0..12])),
        be("added.f", bv(flags[0..2])),
        be("dropped", bv("")),
    };
    var root: bencode.Value = bd(entries[0..3]);
    var body: []u8 = bencode.encode(&arena, root) catch {
        fail("encode ut_pex");
        return 1;
    };
    if (body.len + 1 > msgbuf.len) {
        fail("ut_pex too large for scratch");
        return 1;
    }
    if (!dht.canonicalDicts(&arena, body)) {
        fail("ut_pex added/added.f/dropped not canonical");
        return 1;
    }
    var up_len: usize = extMessage(msgbuf[0..], p.ut_pex_id, body);
    var added1: u32 = pexOnExtended(&arena, &p, &s, msgbuf[0..up_len]);
    if (added1 != 2) {
        fail("ut_pex did not add two peers");
        return 1;
    }
    if (s.active_peer_count != 2) {
        fail("scheduler active count != 2");
        return 1;
    }

    // 3. Re-sending the same message is deduped: zero new peers.
    var added2: u32 = pexOnExtended(&arena, &p, &s, msgbuf[0..up_len]);
    if (added2 != 0 or s.active_peer_count != 2) {
        fail("duplicate ut_pex not deduped");
        return 1;
    }

    // 4. A drop-only ut_pex adds nothing and keeps the two peers (no-op drops).
    var dentries: [1]bencode.Entry = [1]bencode.Entry{
        be("dropped", bv(added[0..12])),
    };
    var droot: bencode.Value = bd(dentries[0..1]);
    var dbody: []u8 = bencode.encode(&arena, droot) catch {
        fail("encode drop-only ut_pex");
        return 1;
    };
    var dlen: usize = extMessage(msgbuf[0..], p.ut_pex_id, dbody);
    var added3: u32 = pexOnExtended(&arena, &p, &s, msgbuf[0..dlen]);
    if (added3 != 0 or s.active_peer_count != 2) {
        fail("drop-only ut_pex changed the scheduler");
        return 1;
    }

    // 5. An un-negotiated extension id is ignored.
    var added4: u32 = pexOnExtended(&arena, &p, &s, msgbuf[0..up_len]);
    msgbuf[0] = 9;
    added4 = pexOnExtended(&arena, &p, &s, msgbuf[0..up_len]);
    if (added4 != 0 or s.active_peer_count != 2) {
        fail("unknown extension id changed the scheduler");
        return 1;
    }

    var ok: []const u8 = "pex selftest: PASS (handshake + ut_pex added/dropped feed addPeer)\n";
    std.io.write(ok);
    return 0;
}
