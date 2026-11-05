// pack.zig -- Git pack v2 / idx v2 reader.
//
// The idx is loaded whole (it is a compact lookup table); the pack itself is
// never mapped or slurped: every access goes through a 1 MiB sliding window
// over std_file seek/read.  A single entry's compressed payload is copied
// through that window into one arena scratch buffer bounded by the entry's
// declared uncompressed size (deflate can expand at most a little), and
// inflateZlib's `used` reports the exact end of the stream.
//
// idx v2 layout: magic ff 74 4f 63, version 2, 256-entry fanout, sorted 20-byte
// names, CRC32 table, 31-bit offsets (MSB = large-offset indirection), 8-byte
// large offsets, pack SHA-1, idx SHA-1.  Both trailer checksums are verified.
//
// pack v2 layout: "PACK", version 2, object count, entry*, pack SHA-1.  Entry
// headers carry a 3-bit type and a base-128 size; OFS_DELTA adds Git's
// relative-offset encoding, REF_DELTA a 20-byte base id.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const crypto = @import("std_crypto.zig");
const deflate = @import("std_deflate.zig");

pub const ObjectId = [20]u8;

pub const Kind = enum(u8) {
    commit = 1,
    tree = 2,
    blob = 3,
    tag = 4,
    ofs_delta = 6,
    ref_delta = 7,
};

const WINDOW_SIZE: usize = 1024 * 1024;
const MAX_U64: u64 = 0xFFFFFFFFFFFFFFFF;
const MAX_U32: u64 = 0xFFFFFFFF;

pub const Idx = struct {
    data: []const u8,
    names_off: usize,
    crc_off: usize,
    offs_off: usize,
    large_off: usize,
    large_end: usize,
    count: usize,
    pack_id: ObjectId,
};

pub const Pack = struct {
    file: file_mod.File,
    file_size: u64,
    idx: Idx,
    win: []u8,
    win_start: u64,
    win_len: usize,
    count: u32,
};

pub const RawEntry = struct {
    kind: Kind,
    size: u64,
    base_off: u64,
    base_id: ObjectId,
    payload: []u8,
    payload_off: u64,
    payload_len: usize,
};

fn be32(b: []const u8, off: usize) u32 {
    var v: u32 = @intCast(u32, b[off]);
    v = (v << 8) | @intCast(u32, b[off + 1]);
    v = (v << 8) | @intCast(u32, b[off + 2]);
    v = (v << 8) | @intCast(u32, b[off + 3]);
    return v;
}

fn be64(b: []const u8, off: usize) u64 {
    var v: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        v = (v << 8) | @intCast(u64, b[off + i]);
    }
    return v;
}

fn addU64(a: u64, b: u64) !u64 {
    if (a > MAX_U64 - b) return error.Corrupt;
    return a + b;
}

fn mulU64(a: u64, b: u64) !u64 {
    if (a != 0 and b > MAX_U64 / a) return error.Corrupt;
    return a * b;
}

fn copyBytes(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn endsWith(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        if (s[s.len - suffix.len + i] != suffix[i]) return false;
    }
    return true;
}

fn sha1Slice(data: []const u8, out: *ObjectId) void {
    var h = crypto.sha1Init();
    crypto.sha1Update(&h, data);
    crypto.sha1Final(&h, out);
}

pub fn idxLoad(arena: *arena_mod.Arena, path: []const u8) !Idx {
    const data = file_mod.readAll(arena, path) catch return error.OpenFailed;
    if (data.len < 8 + 256 * 4 + 40) return error.Corrupt;
    if (data[0] != 0xFF or data[1] != 't' or data[2] != 'O' or data[3] != 'c') {
        return error.Corrupt;
    }
    if (be32(data, 4) != 2) return error.Corrupt;

    var trailer: ObjectId = undefined;
    sha1Slice(data[0 .. data.len - 20], &trailer);
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (trailer[i] != data[data.len - 20 + i]) return error.Corrupt;
    }

    const count: usize = @intCast(usize, be32(data, 8 + 255 * 4));
    const names_off: usize = 8 + 256 * 4;
    const names_bytes: u64 = try mulU64(@intCast(u64, count), 20);
    const crc_off64: u64 = try addU64(@intCast(u64, names_off), names_bytes);
    const crc_bytes: u64 = try mulU64(@intCast(u64, count), 4);
    const offs_off64: u64 = try addU64(crc_off64, crc_bytes);
    const offs_bytes: u64 = try mulU64(@intCast(u64, count), 4);
    const large_off64: u64 = try addU64(offs_off64, offs_bytes);
    const min_end: u64 = try addU64(large_off64, 40);
    if (min_end > @intCast(u64, data.len)) return error.Corrupt;

    var pack_id: ObjectId = undefined;
    i = 0;
    while (i < 20) : (i += 1) pack_id[i] = data[data.len - 40 + i];

    var prev: u32 = 0;
    i = 0;
    while (i < 256) : (i += 1) {
        const v = be32(data, 8 + i * 4);
        if (v < prev) return error.Corrupt;
        if (@intCast(u64, v) > @intCast(u64, count)) return error.Corrupt;
        prev = v;
    }
    if (@intCast(usize, prev) != count) return error.Corrupt;

    // Every 31-bit offset that uses the MSB indirection must address an
    // in-bounds 8-byte large-offset slot; validate once so a lookup can never
    // silently treat a truncated table as "not found".
    i = 0;
    while (i < count) : (i += 1) {
        const raw = be32(data, @intCast(usize, offs_off64) + i * 4);
        if ((raw & 0x80000000) != 0) {
            const li: u64 = @intCast(u64, raw & 0x7FFFFFFF);
            const pos = try addU64(large_off64, try mulU64(li, 8));
            const end = try addU64(pos, 8);
            if (end > @intCast(u64, data.len - 40)) return error.Corrupt;
        }
    }

    return Idx{
        .data = data,
        .names_off = names_off,
        .crc_off = @intCast(usize, crc_off64),
        .offs_off = @intCast(usize, offs_off64),
        .large_off = @intCast(usize, large_off64),
        .large_end = data.len - 40,
        .count = count,
        .pack_id = pack_id,
    };
}

fn nameAt(idx: *const Idx, i: usize) []const u8 {
    const off = idx.names_off + i * 20;
    return idx.data[off .. off + 20];
}

fn nameCmpId(name: []const u8, id: ObjectId) i32 {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (name[i] < id[i]) return -1;
        if (name[i] > id[i]) return 1;
    }
    return 0;
}

// Returns the pack offset for `id`, or null.  The fanout narrows the search to
// the entries whose first byte matches, then a binary search compares the full
// sorted 20-byte names.
pub fn idxFind(idx: *const Idx, id: ObjectId) ?u64 {
    const c: usize = @intCast(usize, id[0]);
    var lo: u32 = 0;
    if (c != 0) lo = be32(idx.data, 8 + (c - 1) * 4);
    const hi: u32 = be32(idx.data, 8 + c * 4);
    if (hi < lo) return null;
    var a: usize = @intCast(usize, lo);
    var b: usize = @intCast(usize, hi);
    while (a < b) {
        const mid: usize = a + (b - a) / 2;
        if (mid >= idx.count) return null;
        const cmp = nameCmpId(nameAt(idx, mid), id);
        if (cmp == 0) return idxOffsetAt(idx, mid);
        if (cmp < 0) {
            a = mid + 1;
        } else {
            b = mid;
        }
    }
    return null;
}

fn idxOffsetAt(idx: *const Idx, i: usize) ?u64 {
    if (i >= idx.count) return null;
    const raw = be32(idx.data, idx.offs_off + i * 4);
    if ((raw & 0x80000000) == 0) return @intCast(u64, raw);
    const li: usize = @intCast(usize, raw & 0x7FFFFFFF);
    const off64: u64 = @intCast(u64, idx.large_off) + @intCast(u64, li) * 8;
    if (off64 + 8 > @intCast(u64, idx.large_end)) return null;
    return be64(idx.data, @intCast(usize, off64));
}

fn readAt(p: *Pack, off: u64, dst: []u8) !void {
    var done: usize = 0;
    while (done < dst.len) {
        const cur = try addU64(off, @intCast(u64, done));
        const win_end = try addU64(p.win_start, @intCast(u64, p.win_len));
        if (p.win_len == 0 or cur < p.win_start or cur >= win_end) {
            try fillWindow(p, cur);
            if (p.win_len == 0) return error.Corrupt;
        }
        const rel: usize = @intCast(usize, cur - p.win_start);
        if (rel >= p.win_len) return error.Corrupt;
        var n: usize = dst.len - done;
        const avail = p.win_len - rel;
        if (n > avail) n = avail;
        if (n == 0) return error.Corrupt;
        var i: usize = 0;
        while (i < n) : (i += 1) dst[done + i] = p.win[rel + i];
        done += n;
    }
}

fn fillWindow(p: *Pack, off: u64) !void {
    if (off >= p.file_size) return error.Corrupt;
    var remaining = p.file_size - off;
    var want: usize = WINDOW_SIZE;
    if (remaining < @intCast(u64, WINDOW_SIZE)) want = @intCast(usize, remaining);
    if (want == 0) return error.Corrupt;
    if (off > 0x7FFFFFFFFFFFFFFF) return error.Corrupt;
    _ = file_mod.seek(&p.file, @intCast(i64, off), file_mod.SeekWhence.Set) catch return error.Corrupt;
    var got: usize = 0;
    while (got < want) {
        const r = file_mod.read(&p.file, p.win[got..want]) catch return error.Corrupt;
        if (r == 0) break;
        got += r;
    }
    p.win_start = off;
    p.win_len = got;
}

fn readByte(p: *Pack, off: u64) !u8 {
    var b: [1]u8 = undefined;
    try readAt(p, off, b[0..1]);
    return b[0];
}

fn typeFromKind(k: u8) !Kind {
    if (k == 1) return Kind.commit;
    if (k == 2) return Kind.tree;
    if (k == 3) return Kind.blob;
    if (k == 4) return Kind.tag;
    if (k == 6) return Kind.ofs_delta;
    if (k == 7) return Kind.ref_delta;
    return error.Corrupt;
}

fn readHeaderSize(p: *Pack, pos: *u64, first: u8) !u64 {
    var c: u8 = first;
    var size: u64 = @intCast(u64, c & 0x0F);
    var shift: usize = 4;
    while ((c & 0x80) != 0) {
        c = try readByte(p, pos.*);
        pos.* = try addU64(pos.*, 1);
        if (shift >= 64) return error.Corrupt;
        const bits: u64 = @intCast(u64, c & 0x7F);
        const sh: u64 = @intCast(u64, shift);
        if (bits > (MAX_U64 >> sh)) return error.Corrupt;
        const add = bits << sh;
        size = try addU64(size, add);
        shift += 7;
    }
    return size;
}

fn readOfsDistance(p: *Pack, pos: *u64) !u64 {
    var c = try readByte(p, pos.*);
    pos.* = try addU64(pos.*, 1);
    var dist: u64 = @intCast(u64, c & 0x7F);
    while ((c & 0x80) != 0) {
        if (dist > (MAX_U64 >> 7) - 1) return error.Corrupt;
        dist = (dist + 1) << 7;
        c = try readByte(p, pos.*);
        pos.* = try addU64(pos.*, 1);
        const bits: u64 = @intCast(u64, c & 0x7F);
        dist = try addU64(dist, bits);
    }
    return dist;
}

const Inflated = struct {
    data: []u8,
    used: usize,
};

fn decompressEntry(arena: *arena_mod.Arena, p: *Pack, payload_off: u64, size: u64) !Inflated {
    if (size > MAX_U32) return error.Corrupt;
    const usize_size: usize = @intCast(usize, size);
    const out_raw = arena_mod.alloc(arena, usize_size) catch return error.OutOfMemory;
    const out: []u8 = out_raw[0..usize_size];

    if (payload_off > p.file_size) return error.Corrupt;
    const after_header = p.file_size - 20;
    if (payload_off > after_header) return error.Corrupt;
    const remaining: u64 = after_header - payload_off;

    var slack: u64 = size / 4;
    if (slack < 1024) slack = 1024;
    var cap64 = try addU64(size, slack);
    if (cap64 > remaining) cap64 = remaining;
    if (cap64 > MAX_U32) cap64 = MAX_U32;
    if (cap64 == 0) return error.Corrupt;
    const cap: usize = @intCast(usize, cap64);
    const in_raw = arena_mod.alloc(arena, cap) catch return error.OutOfMemory;
    try readAt(p, payload_off, in_raw[0..cap]);

    var used: usize = 0;
    const got = deflate.inflateZlib(in_raw[0..cap], out, &used) catch return error.Corrupt;
    if (@intCast(u64, got) != size) return error.Corrupt;
    if (used > cap) return error.Corrupt;
    const end = try addU64(payload_off, @intCast(u64, used));
    if (end > after_header) return error.Corrupt;
    return Inflated{ .data = out, .used = used };
}

pub fn packOpen(arena: *arena_mod.Arena, pack_path: []const u8, idx: Idx) !Pack {
    const file = file_mod.open(arena, pack_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var p: Pack = undefined;
    p.file = file;
    const fsz = file_mod.size(&p.file) catch return error.OpenFailed;
    if (fsz < 12 + 20) return error.Corrupt;
    p.file_size = @intCast(u64, fsz);
    p.idx = idx;
    const win_raw = arena_mod.alloc(arena, WINDOW_SIZE) catch return error.OutOfMemory;
    p.win = win_raw[0..WINDOW_SIZE];
    p.win_start = 0;
    p.win_len = 0;
    p.count = 0;

    var hdr: [12]u8 = undefined;
    try readAt(&p, 0, hdr[0..12]);
    if (hdr[0] != 'P' or hdr[1] != 'A' or hdr[2] != 'C' or hdr[3] != 'K') return error.Corrupt;
    if (be32(hdr[0..], 4) != 2) return error.Corrupt;
    p.count = be32(hdr[0..], 8);
    if (@intCast(usize, p.count) != idx.count) return error.Corrupt;

    // Streaming SHA-1 over everything except the 20-byte pack trailer.
    var h = crypto.sha1Init();
    var off: u64 = 0;
    const body_end = p.file_size - 20;
    var chunk: [4096]u8 = undefined;
    while (off < body_end) {
        var n: usize = 4096;
        const left = body_end - off;
        if (left < @intCast(u64, n)) n = @intCast(usize, left);
        try readAt(&p, off, chunk[0..n]);
        crypto.sha1Update(&h, chunk[0..n]);
        off += @intCast(u64, n);
    }
    var trailer: ObjectId = undefined;
    crypto.sha1Final(&h, &trailer);
    var on_disk: [20]u8 = undefined;
    try readAt(&p, body_end, on_disk[0..20]);
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (trailer[i] != on_disk[i]) return error.Corrupt;
        if (on_disk[i] != idx.pack_id[i]) return error.Corrupt;
    }
    return p;
}

pub fn readEntry(arena: *arena_mod.Arena, p: *Pack, offset: u64) !RawEntry {
    if (offset >= p.file_size) return error.Corrupt;
    var pos: u64 = offset;
    const first = try readByte(p, pos);
    pos = try addU64(pos, 1);
    const kind_u8: u8 = (first >> 4) & 0x07;
    const kind = try typeFromKind(kind_u8);
    const size = try readHeaderSize(p, &pos, first);

    var base_off: u64 = 0;
    var base_id: ObjectId = undefined;
    var bi: usize = 0;
    while (bi < 20) : (bi += 1) base_id[bi] = 0;

    if (kind == Kind.ofs_delta) {
        const dist = try readOfsDistance(p, &pos);
        if (dist == 0 or dist > offset) return error.Corrupt;
        base_off = offset - dist;
    } else if (kind == Kind.ref_delta) {
        var tmp: [20]u8 = undefined;
        try readAt(p, pos, tmp[0..20]);
        bi = 0;
        while (bi < 20) : (bi += 1) base_id[bi] = tmp[bi];
        pos = try addU64(pos, 20);
    }

    const got = try decompressEntry(arena, p, pos, size);
    return RawEntry{
        .kind = kind,
        .size = size,
        .base_off = base_off,
        .base_id = base_id,
        .payload = got.data,
        .payload_off = pos,
        .payload_len = got.used,
    };
}
