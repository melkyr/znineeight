// std_hpack.zig — Z98 std lib: RFC 7541 HPACK decode (full) + literal encode.
//
// Contract: caller-owned storage and arena only. The dynamic table keeps
// bounded copies in `storage`; decoded header names/values are copied into the
// caller arena. Decode is the full RFC surface: static table, dynamic table,
// indexed/literal-with-indexing/literal-without-indexing/never-indexed fields,
// dynamic-table-size updates, integer/string codecs, and HPACK Huffman.
//
// Algorithm pins: Huffman decode is a two-level 8-bit canonical lookup table
// (root 256 entries; the two 0xFE/0xFF prefixes have 256-entry subtables) with
// a canonical rare-code bit-walk tail for codes longer than 16 bits. The
// dynamic table is a byte ring with O(1) eviction (no memmove). Static decode
// is direct-indexed; static encode is a linear scan. Encode is literal-only
// (with static indexed fields where possible) and never grows a dynamic table.
//
// Fail closed: every malformed input returns HpackError.Corrupt. The decoder
// pre-validates before every @intCast/shift/index so -fsafe never traps.

const arena_mod = @import("std_arena.zig");
const buf_mod = @import("std_buf.zig");

pub const HpackHeader = struct {
    name: []const u8,
    value: []const u8,
};

pub const HpackError = error{
    Corrupt,
    OutOfMemory,
};

const StaticEntry = struct {
    name: []const u8,
    value: []const u8,
};

// The two-level Huffman decode table uses the top two bits as a tag:
//   10 = terminal (bits 16..21 hold code length, bits 0..8 hold symbol)
//   01 = root subtable reference (low bits hold subtable index)
//   11 = rare code: canonical bit-walk tail
const HUFF_TERM: u32 = 0x80000000;
const HUFF_SUB: u32 = 0x40000000;
const HUFF_RARE: u32 = 0xC0000000;
const HUFF_TAG: u32 = 0xC0000000;

const MAX_ENTRIES: usize = 1024;

const HpackEntry = struct {
    name_off: usize,
    name_len: usize,
    value_off: usize,
    value_len: usize,
};

pub const Hpack = struct {
    storage: []u8,
    max_size: usize,
    used_size: usize,
    used_bytes: usize,
    head_byte: usize,
    tail_byte: usize,
    head: usize,
    count: usize,
    max_entries: usize,
    entries: [MAX_ENTRIES]HpackEntry,
};

pub fn hpackInit(h: *Hpack, storage: []u8) void {
    h.storage = storage;
    h.max_size = storage.len;
    h.used_size = 0;
    h.used_bytes = 0;
    h.head_byte = 0;
    h.tail_byte = 0;
    h.head = 0;
    h.count = 0;
    h.max_entries = storage.len / 32;
    if (h.max_entries > MAX_ENTRIES) h.max_entries = MAX_ENTRIES;
}

pub fn hpackDynamicSize(h: *const Hpack) usize {
    return h.used_size;
}

pub fn hpackDynamicCount(h: *const Hpack) usize {
    return h.count;
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn copyBytes(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[i] = src[i];
    }
}

fn copyToArena(ar: *arena_mod.Arena, src: []const u8) HpackError![]u8 {
    const raw = arena_mod.alloc(ar, src.len) catch return error.OutOfMemory;
    const dst = raw[0..src.len];
    copyBytes(dst, src);
    return dst;
}

fn entrySize(name_len: usize, value_len: usize) HpackError!usize {
    const sz: u64 = @intCast(u64, name_len) + @intCast(u64, value_len) + 32;
    if (sz > 0xFFFFFFFF) return error.Corrupt;
    return @intCast(usize, sz);
}

fn dynClear(h: *Hpack) void {
    h.used_size = 0;
    h.used_bytes = 0;
    h.head_byte = 0;
    h.tail_byte = 0;
    h.head = 0;
    h.count = 0;
}

fn dynEvict(h: *Hpack) void {
    const e = h.entries[h.head];
    h.used_size -= e.name_len + e.value_len + 32;
    h.used_bytes -= e.name_len + e.value_len;
    h.head += 1;
    if (h.head == MAX_ENTRIES) h.head = 0;
    h.head_byte += e.name_len + e.value_len;
    if (h.head_byte >= h.storage.len) h.head_byte = h.head_byte % h.storage.len;
    h.count -= 1;
}

fn dynInsert(h: *Hpack, name: []const u8, value: []const u8) HpackError!void {
    const sz = try entrySize(name.len, value.len);
    if (h.max_size == 0 or sz > h.max_size) {
        dynClear(h);
        return;
    }
    while (h.used_size + sz > h.max_size) {
        if (h.count == 0) return error.Corrupt;
        dynEvict(h);
    }
    while (h.count >= h.max_entries) {
        if (h.count == 0) return error.Corrupt;
        dynEvict(h);
    }
    if (h.storage.len == 0) return error.Corrupt;

    var e: HpackEntry = undefined;
    e.name_off = h.tail_byte;
    e.name_len = name.len;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        h.storage[h.tail_byte] = name[i];
        h.tail_byte += 1;
        if (h.tail_byte == h.storage.len) h.tail_byte = 0;
    }
    e.value_off = h.tail_byte;
    e.value_len = value.len;
    i = 0;
    while (i < value.len) : (i += 1) {
        h.storage[h.tail_byte] = value[i];
        h.tail_byte += 1;
        if (h.tail_byte == h.storage.len) h.tail_byte = 0;
    }

    const slot: usize = (h.head + h.count) % MAX_ENTRIES;
    h.entries[slot] = e;
    h.count += 1;
    h.used_size += sz;
    h.used_bytes += name.len + value.len;
}

fn copyRing(h: *const Hpack, off: usize, len: usize, dst: []u8) void {
    var p: usize = off;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        dst[i] = h.storage[p];
        p += 1;
        if (p == h.storage.len) p = 0;
    }
}

fn copyRingToArena(h: *const Hpack, off: usize, len: usize, ar: *arena_mod.Arena) HpackError![]u8 {
    const raw = arena_mod.alloc(ar, len) catch return error.OutOfMemory;
    const dst = raw[0..len];
    copyRing(h, off, len, dst);
    return dst;
}

fn dynSlot(h: *const Hpack, dyn_offset: usize) HpackError!usize {
    if (dyn_offset >= h.count) return error.Corrupt;
    var slot: usize = h.head + h.count - 1 - dyn_offset;
    if (slot >= MAX_ENTRIES) slot = slot % MAX_ENTRIES;
    return slot;
}

fn resolveName(h: *Hpack, idx: usize, ar: *arena_mod.Arena) HpackError![]const u8 {
    if (idx == 0) return error.Corrupt;
    if (idx <= 61) {
        return try copyToArena(ar, STATIC_TABLE[idx - 1].name);
    }
    const slot = try dynSlot(h, idx - 62);
    const e = h.entries[slot];
    return try copyRingToArena(h, e.name_off, e.name_len, ar);
}

fn resolveIndex(h: *Hpack, idx: usize, ar: *arena_mod.Arena, name_out: *[]const u8, value_out: *[]const u8) HpackError!void {
    if (idx == 0) return error.Corrupt;
    if (idx <= 61) {
        const se = STATIC_TABLE[idx - 1];
        name_out.* = try copyToArena(ar, se.name);
        value_out.* = try copyToArena(ar, se.value);
        return;
    }
    const slot = try dynSlot(h, idx - 62);
    const e = h.entries[slot];
    name_out.* = try copyRingToArena(h, e.name_off, e.name_len, ar);
    value_out.* = try copyRingToArena(h, e.value_off, e.value_len, ar);
}

fn peek8At(src: []const u8, bitpos: usize, total: usize) u32 {
    if (bitpos >= total) return 255;
    const byteidx: usize = bitpos >> 3;
    const shift: u32 = @intCast(u32, bitpos & 7);
    const b0: u32 = @intCast(u32, src[byteidx]);
    var v: u32 = 0;
    if (shift == 0) {
        v = b0;
    } else {
        const high: u32 = b0 << shift;
        var low: u32 = 0;
        if (byteidx + 1 < src.len) {
            low = @intCast(u32, src[byteidx + 1]) >> @intCast(u32, 8 - shift);
        } else {
            low = (@intCast(u32, 1) << shift) - 1;
        }
        v = (high | low) & 0xFF;
    }
    const rem: usize = total - bitpos;
    if (rem < 8) {
        const pad: u32 = (@intCast(u32, 1) << @intCast(u32, 8 - rem)) - 1;
        v = v | pad;
    }
    return v & 0xFF;
}

fn remainingAllOnes(src: []const u8, bitpos: usize, total: usize) bool {
    var p: usize = bitpos;
    while (p < total) : (p += 1) {
        const sh: u32 = @intCast(u32, 7 - (p & 7));
        const bit: u32 = (@intCast(u32, src[p >> 3]) >> sh) & 1;
        if (bit == 0) return false;
    }
    return true;
}

fn huffRare(src: []const u8, bitpos: usize, total: usize, prefix: u32) HpackError!u32 {
    var code: u32 = prefix;
    var len: u32 = 16;
    var p: usize = bitpos + 16;
    while (len < 30) {
        if (p >= total) return error.Corrupt;
        const sh: u32 = @intCast(u32, 7 - (p & 7));
        const bit: u32 = (@intCast(u32, src[p >> 3]) >> sh) & 1;
        p += 1;
        len += 1;
        code = (code << 1) | bit;
        const idxv: u16 = HUFF_IDX[@intCast(usize, len)];
        if (idxv != 65535) {
            const first: u32 = HUFF_FIRST[@intCast(usize, len)];
            const cnt: u32 = @intCast(u32, HUFF_COUNT[@intCast(usize, len)]);
            if (code >= first) {
                const off: u32 = code - first;
                if (off < cnt) {
                    const sym: u32 = @intCast(u32, HUFF_SYMS[@intCast(usize, @intCast(u32, idxv) + off)]);
                    return (len << 16) | sym;
                }
            }
        }
    }
    return error.Corrupt;
}

fn huffDecode(src: []const u8, ar: *arena_mod.Arena) HpackError![]u8 {
    if (src.len > 0x1FFFFFFF) return error.Corrupt;
    const cap64: u64 = (@intCast(u64, src.len) * 8 + 4) / 5 + 1;
    if (cap64 > 0xFFFFFFFF) return error.Corrupt;
    const cap: usize = @intCast(usize, cap64);
    const raw = arena_mod.alloc(ar, cap) catch return error.OutOfMemory;
    const dst = raw[0..cap];

    var total: usize = 0;
    if (src.len != 0) total = src.len * 8;
    var bitpos: usize = 0;
    var op: usize = 0;

    while (bitpos < total) {
        const rem: usize = total - bitpos;
        if (rem < 8 and remainingAllOnes(src, bitpos, total)) break;

        const chunk: u32 = peek8At(src, bitpos, total);
        var e: u32 = HUFF_ROOT[@intCast(usize, chunk)];
        var ln: u32 = 0;
        var sym: u32 = 0;

        if ((e & HUFF_TAG) == HUFF_SUB) {
            if (rem < 9) return error.Corrupt;
            const sub: u32 = e & 0xFFFF;
            const chunk16: u32 = (chunk << 8) | peek8At(src, bitpos + 8, total);
            const si: usize = @intCast(usize, sub * 256 + (chunk16 & 0xFF));
            e = HUFF_SUB_TABLE[si];
            if ((e & HUFF_TAG) == HUFF_RARE) {
                const res = try huffRare(src, bitpos, total, chunk16);
                ln = res >> 16;
                sym = res & 0xFFFF;
                if (sym == 256) return error.Corrupt;
            } else if ((e & HUFF_TAG) == HUFF_TERM) {
                ln = (e >> 16) & 0x3F;
                sym = e & 0xFF;
                if (ln < 9) return error.Corrupt;
            } else {
                return error.Corrupt;
            }
        } else if ((e & HUFF_TAG) == HUFF_TERM) {
            ln = (e >> 16) & 0x3F;
            sym = e & 0xFF;
            if (ln == 0 or ln > 8) return error.Corrupt;
        } else {
            return error.Corrupt;
        }

        if (ln == 0 or ln > 30) return error.Corrupt;
        if (ln > rem) return error.Corrupt;
        if (sym == 256) return error.Corrupt;
        if (op >= cap) return error.Corrupt;
        dst[op] = @intCast(u8, sym);
        op += 1;
        bitpos += @intCast(usize, ln);
    }
    return dst[0..op];
}

fn decodeInt(block: []const u8, pos: *usize, prefix_bits: u32, first: u8) HpackError!usize {
    const mask: u32 = (@intCast(u32, 1) << prefix_bits) - 1;
    var value: u32 = @intCast(u32, first) & mask;
    if (value < mask) return @intCast(usize, value);

    var total: u64 = @intCast(u64, mask);
    var shift: u32 = 0;
    while (true) {
        if (shift > 28) return error.Corrupt;
        if (pos.* >= block.len) return error.Corrupt;
        const b: u8 = block[pos.*];
        pos.* += 1;
        const low: u64 = @intCast(u64, b & 0x7F);
        total += low << @intCast(u64, shift);
        if (total > 0xFFFFFFFF) return error.Corrupt;
        if ((b & 0x80) == 0) break;
        shift += 7;
    }
    return @intCast(usize, total);
}

fn decodeString(block: []const u8, pos: *usize, ar: *arena_mod.Arena, out: *[]const u8) HpackError!void {
    if (pos.* >= block.len) return error.Corrupt;
    const b: u8 = block[pos.*];
    pos.* += 1;
    const huff: bool = (b & 0x80) != 0;
    const len = try decodeInt(block, pos, 7, b);
    if (pos.* > block.len) return error.Corrupt;
    if (len > block.len - pos.*) return error.Corrupt;
    const src = block[pos.* .. pos.* + len];
    pos.* += len;
    if (huff) {
        out.* = try huffDecode(src, ar);
    } else {
        out.* = try copyToArena(ar, src);
    }
}

fn appendHeader(out: []HpackHeader, n: *usize, name: []const u8, value: []const u8) HpackError!void {
    if (n.* >= out.len) return error.Corrupt;
    out[n.*] = HpackHeader{ .name = name, .value = value };
    n.* += 1;
}

pub fn hpackDecode(h: *Hpack, block: []const u8, out: []HpackHeader, ar: *arena_mod.Arena) HpackError!usize {
    var pos: usize = 0;
    var n: usize = 0;
    var seen_field: bool = false;

    while (pos < block.len) {
        const b: u8 = block[pos];
        if ((b & 0x80) != 0) {
            pos += 1;
            const idx = try decodeInt(block, &pos, 7, b);
            if (idx == 0) return error.Corrupt;
            var name: []const u8 = "";
            var value: []const u8 = "";
            try resolveIndex(h, idx, ar, &name, &value);
            try appendHeader(out, &n, name, value);
            seen_field = true;
        } else if ((b & 0x40) != 0) {
            pos += 1;
            const idx = try decodeInt(block, &pos, 6, b);
            var name: []const u8 = "";
            if (idx == 0) {
                try decodeString(block, &pos, ar, &name);
            } else {
                name = try resolveName(h, idx, ar);
            }
            var value: []const u8 = "";
            try decodeString(block, &pos, ar, &value);
            try appendHeader(out, &n, name, value);
            try dynInsert(h, name, value);
            seen_field = true;
        } else if ((b & 0x20) != 0) {
            if (seen_field) return error.Corrupt;
            pos += 1;
            const sz = try decodeInt(block, &pos, 5, b);
            if (sz > h.storage.len) return error.Corrupt;
            h.max_size = sz;
            while (h.used_size > h.max_size and h.count > 0) dynEvict(h);
        } else {
            pos += 1;
            const idx = try decodeInt(block, &pos, 4, b);
            var name: []const u8 = "";
            if (idx == 0) {
                try decodeString(block, &pos, ar, &name);
            } else {
                name = try resolveName(h, idx, ar);
            }
            var value: []const u8 = "";
            try decodeString(block, &pos, ar, &value);
            try appendHeader(out, &n, name, value);
            seen_field = true;
        }
    }
    return n;
}

fn staticFindName(name: []const u8) usize {
    var i: usize = 0;
    while (i < STATIC_TABLE.len) : (i += 1) {
        if (eqBytes(STATIC_TABLE[i].name, name)) return i + 1;
    }
    return 0;
}

fn staticFind(name: []const u8, value: []const u8) usize {
    var i: usize = 0;
    while (i < STATIC_TABLE.len) : (i += 1) {
        if (eqBytes(STATIC_TABLE[i].name, name) and eqBytes(STATIC_TABLE[i].value, value)) return i + 1;
    }
    return 0;
}

fn putInt(out: *buf_mod.Buf, value: usize, prefix_bits: u32, high: u8) HpackError!void {
    var one: u32 = 1;
    const maxu: u32 = (one << prefix_bits) - 1;
    const maxv: usize = @intCast(usize, maxu);
    if (value < maxv) {
        const byte: u8 = @intCast(u8, @intCast(u32, high) | @intCast(u32, value));
        try buf_mod.appendByte(out, byte);
        return;
    }
    var first: u32 = @intCast(u32, high) | maxu;
    try buf_mod.appendByte(out, @intCast(u8, first));
    var rem: usize = value - maxv;
    while (rem >= 128) {
        const byte: u8 = @intCast(u8, (rem & 127) | 128);
        try buf_mod.appendByte(out, byte);
        rem = rem >> 7;
    }
    try buf_mod.appendByte(out, @intCast(u8, rem));
}

fn putString(out: *buf_mod.Buf, s: []const u8) HpackError!void {
    try putInt(out, s.len, 7, 0x00);
    try buf_mod.append(out, s);
}

pub fn hpackEncode(headers: []const HpackHeader, out: *buf_mod.Buf) HpackError!void {
    var i: usize = 0;
    while (i < headers.len) : (i += 1) {
        const name = headers[i].name;
        const value = headers[i].value;
        const exact = staticFind(name, value);
        if (exact != 0) {
            try putInt(out, exact, 7, 0x80);
            continue;
        }
        const name_idx = staticFindName(name);
        try putInt(out, name_idx, 4, 0x00);
        if (name_idx == 0) try putString(out, name);
        try putString(out, value);
    }
}

const STATIC_TABLE = [_]StaticEntry{
    .{ .name = ":authority", .value = "" },
    .{ .name = ":method", .value = "GET" },
    .{ .name = ":method", .value = "POST" },
    .{ .name = ":path", .value = "/" },
    .{ .name = ":path", .value = "/index.html" },
    .{ .name = ":scheme", .value = "http" },
    .{ .name = ":scheme", .value = "https" },
    .{ .name = ":status", .value = "200" },
    .{ .name = ":status", .value = "204" },
    .{ .name = ":status", .value = "206" },
    .{ .name = ":status", .value = "304" },
    .{ .name = ":status", .value = "400" },
    .{ .name = ":status", .value = "404" },
    .{ .name = ":status", .value = "500" },
    .{ .name = "accept-charset", .value = "" },
    .{ .name = "accept-encoding", .value = "gzip, deflate" },
    .{ .name = "accept-language", .value = "" },
    .{ .name = "accept-ranges", .value = "" },
    .{ .name = "accept", .value = "" },
    .{ .name = "access-control-allow-origin", .value = "" },
    .{ .name = "age", .value = "" },
    .{ .name = "allow", .value = "" },
    .{ .name = "authorization", .value = "" },
    .{ .name = "cache-control", .value = "" },
    .{ .name = "content-disposition", .value = "" },
    .{ .name = "content-encoding", .value = "" },
    .{ .name = "content-language", .value = "" },
    .{ .name = "content-length", .value = "" },
    .{ .name = "content-location", .value = "" },
    .{ .name = "content-range", .value = "" },
    .{ .name = "content-type", .value = "" },
    .{ .name = "cookie", .value = "" },
    .{ .name = "date", .value = "" },
    .{ .name = "etag", .value = "" },
    .{ .name = "expect", .value = "" },
    .{ .name = "expires", .value = "" },
    .{ .name = "from", .value = "" },
    .{ .name = "host", .value = "" },
    .{ .name = "if-match", .value = "" },
    .{ .name = "if-modified-since", .value = "" },
    .{ .name = "if-none-match", .value = "" },
    .{ .name = "if-range", .value = "" },
    .{ .name = "if-unmodified-since", .value = "" },
    .{ .name = "last-modified", .value = "" },
    .{ .name = "link", .value = "" },
    .{ .name = "location", .value = "" },
    .{ .name = "max-forwards", .value = "" },
    .{ .name = "proxy-authenticate", .value = "" },
    .{ .name = "proxy-authorization", .value = "" },
    .{ .name = "range", .value = "" },
    .{ .name = "referer", .value = "" },
    .{ .name = "refresh", .value = "" },
    .{ .name = "retry-after", .value = "" },
    .{ .name = "server", .value = "" },
    .{ .name = "set-cookie", .value = "" },
    .{ .name = "strict-transport-security", .value = "" },
    .{ .name = "transfer-encoding", .value = "" },
    .{ .name = "user-agent", .value = "" },
    .{ .name = "vary", .value = "" },
    .{ .name = "via", .value = "" },
    .{ .name = "www-authenticate", .value = "" },
};

const HUFF_ROOT = [_]u32{
    2147811376, 2147811376, 2147811376, 2147811376, 2147811376, 2147811376, 2147811376, 2147811376, 2147811377, 2147811377,
    2147811377, 2147811377, 2147811377, 2147811377, 2147811377, 2147811377, 2147811378, 2147811378, 2147811378, 2147811378,
    2147811378, 2147811378, 2147811378, 2147811378, 2147811425, 2147811425, 2147811425, 2147811425, 2147811425, 2147811425,
    2147811425, 2147811425, 2147811427, 2147811427, 2147811427, 2147811427, 2147811427, 2147811427, 2147811427, 2147811427,
    2147811429, 2147811429, 2147811429, 2147811429, 2147811429, 2147811429, 2147811429, 2147811429, 2147811433, 2147811433,
    2147811433, 2147811433, 2147811433, 2147811433, 2147811433, 2147811433, 2147811439, 2147811439, 2147811439, 2147811439,
    2147811439, 2147811439, 2147811439, 2147811439, 2147811443, 2147811443, 2147811443, 2147811443, 2147811443, 2147811443,
    2147811443, 2147811443, 2147811444, 2147811444, 2147811444, 2147811444, 2147811444, 2147811444, 2147811444, 2147811444,
    2147876896, 2147876896, 2147876896, 2147876896, 2147876901, 2147876901, 2147876901, 2147876901, 2147876909, 2147876909,
    2147876909, 2147876909, 2147876910, 2147876910, 2147876910, 2147876910, 2147876911, 2147876911, 2147876911, 2147876911,
    2147876915, 2147876915, 2147876915, 2147876915, 2147876916, 2147876916, 2147876916, 2147876916, 2147876917, 2147876917,
    2147876917, 2147876917, 2147876918, 2147876918, 2147876918, 2147876918, 2147876919, 2147876919, 2147876919, 2147876919,
    2147876920, 2147876920, 2147876920, 2147876920, 2147876921, 2147876921, 2147876921, 2147876921, 2147876925, 2147876925,
    2147876925, 2147876925, 2147876929, 2147876929, 2147876929, 2147876929, 2147876959, 2147876959, 2147876959, 2147876959,
    2147876962, 2147876962, 2147876962, 2147876962, 2147876964, 2147876964, 2147876964, 2147876964, 2147876966, 2147876966,
    2147876966, 2147876966, 2147876967, 2147876967, 2147876967, 2147876967, 2147876968, 2147876968, 2147876968, 2147876968,
    2147876972, 2147876972, 2147876972, 2147876972, 2147876973, 2147876973, 2147876973, 2147876973, 2147876974, 2147876974,
    2147876974, 2147876974, 2147876976, 2147876976, 2147876976, 2147876976, 2147876978, 2147876978, 2147876978, 2147876978,
    2147876981, 2147876981, 2147876981, 2147876981, 2147942458, 2147942458, 2147942466, 2147942466, 2147942467, 2147942467,
    2147942468, 2147942468, 2147942469, 2147942469, 2147942470, 2147942470, 2147942471, 2147942471, 2147942472, 2147942472,
    2147942473, 2147942473, 2147942474, 2147942474, 2147942475, 2147942475, 2147942476, 2147942476, 2147942477, 2147942477,
    2147942478, 2147942478, 2147942479, 2147942479, 2147942480, 2147942480, 2147942481, 2147942481, 2147942482, 2147942482,
    2147942483, 2147942483, 2147942484, 2147942484, 2147942485, 2147942485, 2147942486, 2147942486, 2147942487, 2147942487,
    2147942489, 2147942489, 2147942506, 2147942506, 2147942507, 2147942507, 2147942513, 2147942513, 2147942518, 2147942518,
    2147942519, 2147942519, 2147942520, 2147942520, 2147942521, 2147942521, 2147942522, 2147942522, 2148007974, 2148007978,
    2148007980, 2148007995, 2148008024, 2148008026, 1073741824, 1073741825,
};

const HUFF_SUB_TABLE = [_]u32{
    2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041,
    2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041,
    2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041,
    2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041,
    2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041,
    2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041, 2148139041,
    2148139041, 2148139041, 2148139041, 2148139041, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042,
    2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042,
    2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042,
    2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042,
    2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042,
    2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042,
    2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139042, 2148139048, 2148139048,
    2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048,
    2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048,
    2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048,
    2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048,
    2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048,
    2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048, 2148139048,
    2148139048, 2148139048, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049,
    2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049,
    2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049,
    2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049,
    2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049,
    2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049,
    2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139049, 2148139071, 2148139071, 2148139071, 2148139071,
    2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071,
    2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071,
    2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071,
    2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071,
    2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071,
    2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071, 2148139071,
    2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583,
    2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583,
    2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583, 2148204583,
    2148204583, 2148204583, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587,
    2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587,
    2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587, 2148204587,
    2148204587, 2148204587, 2148204587, 2148204587, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668,
    2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668,
    2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668,
    2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148204668, 2148270115, 2148270115, 2148270115, 2148270115,
    2148270115, 2148270115, 2148270115, 2148270115, 2148270115, 2148270115, 2148270115, 2148270115, 2148270115, 2148270115,
    2148270115, 2148270115, 2148270142, 2148270142, 2148270142, 2148270142, 2148270142, 2148270142, 2148270142, 2148270142,
    2148270142, 2148270142, 2148270142, 2148270142, 2148270142, 2148270142, 2148270142, 2148270142, 2148335616, 2148335616,
    2148335616, 2148335616, 2148335616, 2148335616, 2148335616, 2148335616, 2148335652, 2148335652, 2148335652, 2148335652,
    2148335652, 2148335652, 2148335652, 2148335652, 2148335680, 2148335680, 2148335680, 2148335680, 2148335680, 2148335680,
    2148335680, 2148335680, 2148335707, 2148335707, 2148335707, 2148335707, 2148335707, 2148335707, 2148335707, 2148335707,
    2148335709, 2148335709, 2148335709, 2148335709, 2148335709, 2148335709, 2148335709, 2148335709, 2148335742, 2148335742,
    2148335742, 2148335742, 2148335742, 2148335742, 2148335742, 2148335742, 2148401246, 2148401246, 2148401246, 2148401246,
    2148401277, 2148401277, 2148401277, 2148401277, 2148466748, 2148466748, 2148466784, 2148466784, 2148466811, 2148466811,
    3221225472, 3221225472,

};

const HUFF_FIRST = [_]u32{
    0, 0, 0, 0, 0, 0, 20, 92, 248, 0,
    1016, 2042, 4090, 8184, 16380, 32764, 0, 0, 0, 524272,
    1048550, 2097116, 4194258, 8388568, 16777194, 33554412, 67108832, 134217694, 268435426, 0,
    1073741820,
};

const HUFF_COUNT = [_]u8{
    0, 0, 0, 0, 0, 10, 26, 32, 6, 0, 5, 3, 2, 6, 2, 3, 0, 0, 0, 3, 8, 13, 26, 29, 12, 4, 15, 19, 29, 0, 4,
};

const HUFF_IDX = [_]u16{
    65535, 65535, 65535, 65535, 65535, 0, 10, 36, 68, 65535, 74, 79, 82, 84, 90, 92, 65535, 65535, 65535, 95, 98, 106, 119, 145, 174, 186, 190, 205, 224, 65535, 253,
};

const HUFF_SYMS = [_]u16{
    48, 49, 50, 97, 99, 101, 105, 111, 115, 116,
    32, 37, 45, 46, 47, 51, 52, 53, 54, 55,
    56, 57, 61, 65, 95, 98, 100, 102, 103, 104,
    108, 109, 110, 112, 114, 117, 58, 66, 67, 68,
    69, 70, 71, 72, 73, 74, 75, 76, 77, 78,
    79, 80, 81, 82, 83, 84, 85, 86, 87, 89,
    106, 107, 113, 118, 119, 120, 121, 122, 38, 42,
    44, 59, 88, 90, 33, 34, 40, 41, 63, 39,
    43, 124, 35, 62, 0, 36, 64, 91, 93, 126,
    94, 125, 60, 96, 123, 92, 195, 208, 128, 130,
    131, 162, 184, 194, 224, 226, 153, 161, 167, 172,
    176, 177, 179, 209, 216, 217, 227, 229, 230, 129,
    132, 133, 134, 136, 146, 154, 156, 160, 163, 164,
    169, 170, 173, 178, 181, 185, 186, 187, 189, 190,
    196, 198, 228, 232, 233, 1, 135, 137, 138, 139,
    140, 141, 143, 147, 149, 150, 151, 152, 155, 157,
    158, 165, 166, 168, 174, 175, 180, 182, 183, 188,
    191, 197, 231, 239, 9, 142, 144, 145, 148, 159,
    171, 206, 215, 225, 236, 237, 199, 207, 234, 235,
    192, 193, 200, 201, 202, 205, 210, 213, 218, 219,
    238, 240, 242, 243, 255, 203, 204, 211, 212, 214,
    221, 222, 223, 241, 244, 245, 246, 247, 248, 250,
    251, 252, 253, 254, 2, 3, 4, 5, 6, 7,
    8, 11, 12, 14, 15, 16, 17, 18, 19, 20,
    21, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    127, 220, 249, 10, 13, 22, 256,
};
