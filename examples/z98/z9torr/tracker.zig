// tracker.zig — z9torr: HTTP tracker announce (query + bencoded response).
//
// Blueprint Stage 5, spec 2026-10-08 §3/§4.3/§6/§8. Builds the announce query,
// performs the HTTP GET via `std_http.get`, decodes the bencoded body with
// `std_bencode.decode`, and returns the compact peer list.
//
// Query (binding, brief):
//   info_hash=<enc>&peer_id=<enc>&port=<p>&uploaded=<u>&downloaded=<d>
//   &left=<l>&compact=1[&event=started|completed]
// `info_hash` and `peer_id` are 20 raw bytes and MUST be percent-encoded
// (every byte outside `[A-Za-z0-9._~-]` -> `%XX`); `left` is derived as
// `total_length - downloaded` (clamped at 0). `event` is derived from `stats`:
// nothing downloaded -> `started`, all downloaded -> `completed`, else omitted.
//
// Response: HTTP 200 with a bencoded dict. A top-level `failure reason` key is
// a tracker failure, not a success (`TrackerError.FailureReason`; the string is
// copied into a module buffer and exposed via `failureReason`). Compact `peers`
// is a `bytes` value of length `6*N`: each 6 bytes are a 4-byte network-order
// IPv4 address plus a 2-byte big-endian port. The IP is stored as `ip_be: u32`
// in the same representation `std_net.resolve`/`connectToIp` use (the four
// network-order bytes assembled little-endian, i.e. `b0 | b1<<8 | b2<<16 |
// b3<<24`), so it can be handed straight to the peer connect path. N=0 is
// allowed (empty peer list).
//
// Z98 rules (spec §5): no method syntax (free functions taking self), no
// generics, strict `@intCast`, `switch` needs `else`, string literals via
// `var s: []const u8 = "...";`. D2: every slice here is `[]u8`/`[]const u8`
// (primitive element) or `[]PeerAddr`/`[]bencode.Entry` (named struct element);
// no `[]synthetic`.

const std = @import("std");
const std_http = @import("std_http.zig");
const bencode = @import("std_bencode.zig");
const parse = @import("std_parse.zig");
const torrentlib = @import("torrent.zig");

pub const PeerId = [20]u8;

// Network-order IPv4 + host-order port (the port is re-ordered by the connect
// path via htons). See the header for the `ip_be` representation.
pub const PeerAddr = struct { ip_be: u32, port: u16 };

// Spec §6 `Stats`. M2 has no stats module yet, so the tracker owns the type it
// consumes; M3 relocates it to `stats.zig` (M3 Task 1) and may alias this.
pub const Stats = struct {
    downloaded: u64,
    uploaded: u64,
    left: u64,
    peer_count: u32,
    down_rate: u32,
    up_rate: u32,
    started_ms: u32,
    window_down: [5]u32,
    window_up: [5]u32,
    window_idx: u32,
};

pub const AnnounceResult = struct {
    interval: u32,
    min_interval: u32,
    peers: []PeerAddr,
    complete: u32,
    incomplete: u32,
    tracker_id: ?[]const u8,
};

// Spec §8 taxonomy. `HttpFailed` is any transport/HTTP-layer failure;
// `BadResponse` is a non-200 status or a malformed/unsupported body;
// `FailureReason` is a bencoded tracker failure (string via `failureReason`).
pub const TrackerError = error{
    HttpFailed,
    BadResponse,
    FailureReason,
    OutOfMemory,
};

// Tracker responses are small; a short timeout keeps the client lively.
const ANNOUNCE_TIMEOUT_MS: u32 = 15000;

const HASH_LEN: usize = 20;
const PEER_ENTRY_LEN: usize = 6;
const FAILURE_MAX: usize = 256;

// Last `failure reason` string (copied; no arena lifetime dependency). Reset
// each `announce`; read with `failureReason`.
var g_failure_buf: [FAILURE_MAX]u8 = undefined;
var g_failure_len: usize = 0;

pub fn failureReason() []const u8 {
    return g_failure_buf[0..g_failure_len];
}

fn storeFailureReason(s: []const u8) void {
    var n: usize = s.len;
    if (n > FAILURE_MAX) n = FAILURE_MAX;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        g_failure_buf[i] = s[i];
    }
    g_failure_len = n;
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn findEntry(entries: []bencode.Entry, key: []const u8) ?usize {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eqBytes(entries[i].key, key)) return i;
    }
    return null;
}

fn intToU32(v: i64, out: *u32) bool {
    if (v < 0) return false;
    if (v > 4294967295) return false;
    out.* = @intCast(u32, v);
    return true;
}

// `started` on the first announce (nothing downloaded yet), `completed` once
// every byte is present, otherwise no event.
fn eventName(t: torrentlib.Torrent, stats: Stats) []const u8 {
    if (stats.downloaded == 0) {
        var started: []const u8 = "started";
        return started;
    }
    if (stats.downloaded >= t.total_length) {
        var completed: []const u8 = "completed";
        return completed;
    }
    var none: []const u8 = "";
    return none;
}

fn allocPeers(arena: *std.arena.Arena, n: usize) TrackerError![]PeerAddr {
    var raw = std.arena.alloc(arena, n * @sizeOf(PeerAddr)) catch return error.OutOfMemory;
    return @ptrCast([*]PeerAddr, raw)[0..n];
}

fn appendStr(b: *std.buf.Buf, s: []const u8) TrackerError!void {
    std.buf.append(b, s) catch return error.OutOfMemory;
}

fn appendByte(b: *std.buf.Buf, c: u8) TrackerError!void {
    std.buf.appendByte(b, c) catch return error.OutOfMemory;
}

pub fn announce(arena: *std.arena.Arena, t: torrentlib.Torrent, peer_id: PeerId, port: u16, stats: Stats) TrackerError!AnnounceResult {
    g_failure_len = 0;

    var enc_ih: []u8 = std_http.percentEncode(arena, t.info_hash[0..HASH_LEN]) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.HttpFailed;
    };
    var enc_pid: []u8 = std_http.percentEncode(arena, peer_id[0..HASH_LEN]) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.HttpFailed;
    };

    var left: u64 = 0;
    if (stats.downloaded < t.total_length) {
        left = t.total_length - stats.downloaded;
    }

    var b = std.buf.init(arena);
    try appendStr(&b, t.announce);
    try appendByte(&b, '?');
    try appendStr(&b, "info_hash=");
    try appendStr(&b, enc_ih);
    try appendStr(&b, "&peer_id=");
    try appendStr(&b, enc_pid);
    try appendStr(&b, "&port=");
    var nbuf: [24]u8 = undefined;
    try appendStr(&b, parse.utoa(nbuf[0..], @intCast(u32, port)));
    try appendStr(&b, "&uploaded=");
    try appendStr(&b, parse.utoa64(nbuf[0..], stats.uploaded));
    try appendStr(&b, "&downloaded=");
    try appendStr(&b, parse.utoa64(nbuf[0..], stats.downloaded));
    try appendStr(&b, "&left=");
    try appendStr(&b, parse.utoa64(nbuf[0..], left));
    try appendStr(&b, "&compact=1");
    var ev: []const u8 = eventName(t, stats);
    if (ev.len > 0) {
        try appendStr(&b, "&event=");
        try appendStr(&b, ev);
    }
    var url: []u8 = std.buf.slice(&b);

    var resp: std_http.Response = std_http.get(arena, url, ANNOUNCE_TIMEOUT_MS) catch {
        return error.HttpFailed;
    };
    if (resp.status != 200) return error.BadResponse;

    var top: bencode.Value = bencode.decode(arena, resp.body) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.BadResponse;
    };
    var entries: []bencode.Entry = undefined;
    switch (top) {
        .dict => |d| {
            entries = d;
        },
        else => return error.BadResponse,
    }

    // A `failure reason` at HTTP 200 is a tracker failure, not a success.
    if (findEntry(entries, "failure reason")) |fi| {
        switch (entries[fi].value) {
            .bytes => |fr| {
                storeFailureReason(fr);
            },
            else => {},
        }
        return error.FailureReason;
    }

    var result: AnnounceResult = undefined;
    result.interval = 0;
    result.min_interval = 0;
    result.complete = 0;
    result.incomplete = 0;
    result.tracker_id = null;

    if (findEntry(entries, "interval")) |ii| {
        switch (entries[ii].value) {
            .int_val => |n| {
                if (!intToU32(n, &result.interval)) return error.BadResponse;
            },
            else => return error.BadResponse,
        }
    }
    if (findEntry(entries, "min_interval")) |mi| {
        switch (entries[mi].value) {
            .int_val => |n| {
                if (!intToU32(n, &result.min_interval)) return error.BadResponse;
            },
            else => return error.BadResponse,
        }
    }
    if (findEntry(entries, "complete")) |ci| {
        switch (entries[ci].value) {
            .int_val => |n| {
                if (!intToU32(n, &result.complete)) return error.BadResponse;
            },
            else => return error.BadResponse,
        }
    }
    if (findEntry(entries, "incomplete")) |ui| {
        switch (entries[ui].value) {
            .int_val => |n| {
                if (!intToU32(n, &result.incomplete)) return error.BadResponse;
            },
            else => return error.BadResponse,
        }
    }
    if (findEntry(entries, "tracker id")) |ti| {
        switch (entries[ti].value) {
            .bytes => |tid| {
                result.tracker_id = tid;
            },
            else => return error.BadResponse,
        }
    }

    // Compact peers: required, a byte string of exactly 6*N bytes.
    var pidx: usize = 0;
    if (findEntry(entries, "peers")) |pi| {
        pidx = pi;
    } else {
        return error.BadResponse;
    }
    var pbytes: []const u8 = undefined;
    switch (entries[pidx].value) {
        .bytes => |pb| {
            pbytes = pb;
        },
        else => return error.BadResponse,
    }
    if (pbytes.len % PEER_ENTRY_LEN != 0) return error.BadResponse;

    var count: usize = pbytes.len / PEER_ENTRY_LEN;
    result.peers = try allocPeers(arena, count);
    var k: usize = 0;
    while (k < count) : (k += 1) {
        var off: usize = k * PEER_ENTRY_LEN;
        var b0: u32 = @intCast(u32, pbytes[off]);
        var b1: u32 = @intCast(u32, pbytes[off + 1]);
        var b2: u32 = @intCast(u32, pbytes[off + 2]);
        var b3: u32 = @intCast(u32, pbytes[off + 3]);
        var ip_be: u32 = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
        var p: u16 = (@intCast(u16, pbytes[off + 4]) << 8) | @intCast(u16, pbytes[off + 5]);
        result.peers[k] = PeerAddr{ .ip_be = ip_be, .port = p };
    }
    return result;
}
