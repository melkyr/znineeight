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
const delta_mod = @import("delta.zig");

// Work buffers for the external idx (scratch, base cache, sort chunks) are
// allocated outside the app arena and released when the idx is done, so several
// packs in one clone do not accumulate their per-pack scratch.  Both mappings
// are pagefile-backed and the OS may page them.
extern "c" fn mmap(addr: *void, length: usize, prot: i32, flags: i32, fd: i32, offset: i32) *void;
extern "c" fn munmap(addr: *void, length: usize) i32;
extern "stdcall" fn VirtualAlloc(addr: *void, size: usize, alloc_type: u32, protect: u32) *void;
extern "stdcall" fn VirtualFree(addr: *void, size: usize, free_type: u32) i32;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

pub fn dynAlloc(n0: usize) ?[]u8 {
    var n = n0;
    if (n == 0) n = 1;
    if (@isWindows()) {
        const p = VirtualAlloc(nullVoid(), n, 0x1000 + 0x2000, 0x04);
        if (@ptrToInt(p) == 0) return null;
        return @ptrCast([*]u8, p)[0..n];
    } else {
        const p = mmap(nullVoid(), n, 3, 2 + 0x20, -1, 0);
        if (@ptrToInt(p) >= 0xFFFFF000) return null;
        return @ptrCast([*]u8, p)[0..n];
    }
}

pub fn dynFree(buf: []u8) void {
    if (buf.len == 0) return;
    if (@isWindows()) {
        _ = VirtualFree(@ptrCast(*void, buf.ptr), 0, 0x8000);
    } else {
        _ = munmap(@ptrCast(*void, buf.ptr), buf.len);
    }
}

// Large object/delta-base buffers are file-backed where possible: a temp file in
// the destination git dir is sized, mapped shared, then unlinked immediately.
// The pages live on temp disk/pagefile, not the app arena; the 32-bit address
// space remains the hard ceiling. Windows falls back to VirtualAlloc (Win9x has
// no cheap file mapping through this layer).
var g_tmp_dir: [4096]u8 = undefined;
var g_tmp_dir_len: usize = 0;
var g_tmp_seq: u32 = 0;

pub fn setTempDir(dir: []const u8) void {
    if (dir.len == 0 or dir.len >= g_tmp_dir.len) {
        g_tmp_dir_len = 0;
        return;
    }
    var i: usize = 0;
    while (i < dir.len) : (i += 1) g_tmp_dir[i] = dir[i];
    g_tmp_dir_len = dir.len;
}

fn buildTempPath(out: []u8) usize {
    if (g_tmp_dir_len == 0) return 0;
    var n: usize = 0;
    var i: usize = 0;
    while (i < g_tmp_dir_len) : (i += 1) out[n + i] = g_tmp_dir[i];
    n += g_tmp_dir_len;
    if (out[n - 1] != '/' and out[n - 1] != '\\') {
        if (n + 1 >= out.len) return 0;
        out[n] = '/';
        n += 1;
    }
    const prefix: []const u8 = "z9big-";
    if (n + prefix.len + 16 >= out.len) return 0;
    i = 0;
    while (i < prefix.len) : (i += 1) out[n + i] = prefix[i];
    n += prefix.len;
    n += putDecimal(out[n..], @intCast(u64, g_tmp_seq));
    g_tmp_seq += 1;
    const suffix: []const u8 = ".tmp";
    if (n + suffix.len >= out.len) return 0;
    i = 0;
    while (i < suffix.len) : (i += 1) out[n + i] = suffix[i];
    n += suffix.len;
    return n;
}

pub fn dynAllocFile(arena: *arena_mod.Arena, n0: usize) ?[]u8 {
    var n = n0;
    if (n == 0) n = 1;
    if (!@isWindows() and g_tmp_dir_len != 0) {
        var pb: [4096]u8 = undefined;
        const plen = buildTempPath(pb[0..]);
        if (plen != 0) {
            const f = file_mod.open(arena, pb[0..plen], file_mod.Mode.ReadWrite) catch return dynAlloc(n);
            var ok = true;
            _ = file_mod.seek(&f, @intCast(i64, n - 1), file_mod.SeekWhence.Set) catch {
                ok = false;
            };
            if (ok) {
                var z: [1]u8 = [_]u8{0};
                const w = file_mod.write(&f, z[0..]) catch 0;
                if (w != 1) ok = false;
            }
            if (!ok) {
                file_mod.close(&f);
                file_mod.remove(pb[0..plen]) catch {};
                return dynAlloc(n);
            }
            const fd: i32 = @intCast(i32, @ptrToInt(f.handle));
            const p = mmap(nullVoid(), n, 3, 1, fd, 0);
            file_mod.close(&f);
            file_mod.remove(pb[0..plen]) catch {};
            if (@ptrToInt(p) >= 0xFFFFF000) return dynAlloc(n);
            return @ptrCast([*]u8, p)[0..n];
        }
    }
    return dynAlloc(n);
}

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
    // The idx stays on disk. Only the 1 KiB fanout is resident; names, CRCs,
    // offsets and the large-offset table are read on demand, so a 24 MiB idx
    // (git/git) does not consume the arena.
    file: file_mod.File,
    file_size: u64,
    names_off: u64,
    crc_off: u64,
    offs_off: u64,
    large_off: u64,
    large_end: u64,
    count: usize,
    pack_id: ObjectId,
    fanout: [256]u32,
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
    big: bool,
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

fn sha1Slice(data: []const u8, out: *ObjectId) void {
    var h = crypto.sha1Init();
    crypto.sha1Update(&h, data);
    crypto.sha1Final(&h, out);
}

const IDX_HEADER_BYTES: usize = 8 + 256 * 4;
const IDX_MIN_BYTES: u64 = @intCast(u64, IDX_HEADER_BYTES) + 40;

fn idxReadFile(f: *file_mod.File, size: u64, off: u64, dst: []u8) !void {
    if (off > size) return error.Corrupt;
    if (@intCast(u64, dst.len) > size - off) return error.Corrupt;
    if (off > 0x7FFFFFFFFFFFFFFF) return error.Corrupt;
    _ = file_mod.seek(f, @intCast(i64, off), file_mod.SeekWhence.Set) catch return error.Io;
    var got: usize = 0;
    while (got < dst.len) {
        const n = file_mod.read(f, dst[got..]) catch return error.Io;
        if (n == 0) return error.Corrupt;
        got += n;
    }
}

fn idxReadAt(idx: *Idx, off: u64, dst: []u8) !void {
    return idxReadFile(&idx.file, idx.file_size, off, dst);
}

pub fn idxClose(idx: *Idx) void {
    file_mod.close(&idx.file);
}

fn idxParse(f: file_mod.File, size: u64, out: *Idx) !void {
    if (size < IDX_MIN_BYTES) return error.Corrupt;
    var hdr: [IDX_HEADER_BYTES]u8 = undefined;
    try idxReadFile(&f, size, 0, hdr[0..]);
    if (hdr[0] != 0xFF or hdr[1] != 't' or hdr[2] != 'O' or hdr[3] != 'c') {
        return error.Corrupt;
    }
    if (be32(hdr[0..], 4) != 2) return error.Corrupt;

    var fanout: [256]u32 = undefined;
    var prev: u32 = 0;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        fanout[i] = be32(hdr[0..], 8 + i * 4);
        if (fanout[i] < prev) return error.Corrupt;
        prev = fanout[i];
    }
    const count: usize = @intCast(usize, fanout[255]);
    const names_off: u64 = @intCast(u64, IDX_HEADER_BYTES);
    const names_bytes: u64 = try mulU64(@intCast(u64, count), 20);
    const crc_off: u64 = try addU64(names_off, names_bytes);
    const crc_bytes: u64 = try mulU64(@intCast(u64, count), 4);
    const offs_off: u64 = try addU64(crc_off, crc_bytes);
    const offs_bytes: u64 = try mulU64(@intCast(u64, count), 4);
    const large_off: u64 = try addU64(offs_off, offs_bytes);
    if (large_off > size - 40) return error.Corrupt;
    const large_end: u64 = size - 40;
    const large_bytes: u64 = large_end - large_off;
    if (large_bytes % 8 != 0) return error.Corrupt;

    var pack_id: ObjectId = undefined;
    try idxReadFile(&f, size, large_end, pack_id[0..20]);

    // The idx SHA-1 trailer is verified over the file bytes, not a whole-file
    // arena copy.
    var h = crypto.sha1Init();
    var off: u64 = 0;
    const body_end: u64 = size - 20;
    var buf: [4096]u8 = undefined;
    while (off < body_end) {
        var take: usize = 4096;
        const left = body_end - off;
        if (left < @intCast(u64, take)) take = @intCast(usize, left);
        try idxReadFile(&f, size, off, buf[0..take]);
        crypto.sha1Update(&h, buf[0..take]);
        off += @intCast(u64, take);
    }
    var trailer: ObjectId = undefined;
    crypto.sha1Final(&h, &trailer);
    var on_disk: [20]u8 = undefined;
    try idxReadFile(&f, size, body_end, on_disk[0..20]);
    i = 0;
    while (i < 20) : (i += 1) {
        if (trailer[i] != on_disk[i]) return error.Corrupt;
    }

    out.file = f;
    out.file_size = size;
    out.names_off = names_off;
    out.crc_off = crc_off;
    out.offs_off = offs_off;
    out.large_off = large_off;
    out.large_end = large_end;
    out.count = count;
    i = 0;
    while (i < 20) : (i += 1) out.pack_id[i] = pack_id[i];
    i = 0;
    while (i < 256) : (i += 1) out.fanout[i] = fanout[i];
}

pub fn idxLoad(arena: *arena_mod.Arena, path: []const u8, out: *Idx) !void {
    const f = file_mod.open(arena, path, file_mod.Mode.Read) catch return error.OpenFailed;
    const sz = file_mod.size(&f) catch {
        file_mod.close(&f);
        return error.OpenFailed;
    };
    if (sz <= 0) {
        file_mod.close(&f);
        return error.Corrupt;
    }
    idxParse(f, @intCast(u64, sz), out) catch |e| {
        file_mod.close(&f);
        if (e == error.Io) return error.Io;
        return error.Corrupt;
    };
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
// the entries whose first byte matches, then a binary search reads the sorted
// 20-byte names from the idx file on demand.
pub fn idxFind(idx: *Idx, id: ObjectId) !?u64 {
    const c: usize = @intCast(usize, id[0]);
    var lo: u32 = 0;
    if (c != 0) lo = idx.fanout[c - 1];
    const hi: u32 = idx.fanout[c];
    if (hi < lo) return error.Corrupt;
    var a: usize = @intCast(usize, lo);
    var b: usize = @intCast(usize, hi);
    var namebuf: [20]u8 = undefined;
    while (a < b) {
        const mid: usize = a + (b - a) / 2;
        if (mid >= idx.count) return error.Corrupt;
        const name_off = idx.names_off + @intCast(u64, mid) * 20;
        try idxReadAt(idx, name_off, namebuf[0..]);
        const cmp = nameCmpId(namebuf[0..], id);
        if (cmp == 0) return try idxOffsetAt(idx, mid);
        if (cmp < 0) {
            a = mid + 1;
        } else {
            b = mid;
        }
    }
    return null;
}

fn idxOffsetAt(idx: *Idx, i: usize) !?u64 {
    if (i >= idx.count) return error.Corrupt;
    var raw_b: [4]u8 = undefined;
    const pos = idx.offs_off + @intCast(u64, i) * 4;
    try idxReadAt(idx, pos, raw_b[0..]);
    const raw = be32(raw_b[0..], 0);
    if ((raw & 0x80000000) == 0) return @intCast(u64, raw);
    const li: u64 = @intCast(u64, raw & 0x7FFFFFFF);
    const off64 = idx.large_off + li * 8;
    if (off64 > idx.large_end or idx.large_end - off64 < 8) return error.Corrupt;
    var large_b: [8]u8 = undefined;
    try idxReadAt(idx, off64, large_b[0..]);
    return be64(large_b[0..], 0);
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
    big: bool,
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
    return Inflated{ .data = out, .used = used, .big = false };
}

fn decompressEntryBig(arena: *arena_mod.Arena, p: *Pack, payload_off: u64, size: u64) !Inflated {
    if (size > MAX_U32) return error.Corrupt;
    const usize_size: usize = @intCast(usize, size);
    const out_raw = dynAllocFile(arena, usize_size) orelse return error.OutOfMemory;
    const out: []u8 = out_raw[0..usize_size];
    if (payload_off > p.file_size) {
        dynFree(out_raw);
        return error.Corrupt;
    }
    const after_header = p.file_size - 20;
    if (payload_off > after_header) {
        dynFree(out_raw);
        return error.Corrupt;
    }
    const remaining: u64 = after_header - payload_off;

    var slack: u64 = size / 4;
    if (slack < 1024) slack = 1024;
    var cap64 = try addU64(size, slack);
    if (cap64 > remaining) cap64 = remaining;
    if (cap64 > MAX_U32) cap64 = MAX_U32;
    if (cap64 == 0) {
        dynFree(out_raw);
        return error.Corrupt;
    }
    const cap: usize = @intCast(usize, cap64);
    const in_raw = dynAllocFile(arena, cap) orelse {
        dynFree(out_raw);
        return error.OutOfMemory;
    };
    readAt(p, payload_off, in_raw[0..cap]) catch {
        dynFree(in_raw);
        dynFree(out_raw);
        return error.Corrupt;
    };

    var used: usize = 0;
    const got = deflate.inflateZlib(in_raw[0..cap], out, &used) catch {
        dynFree(in_raw);
        dynFree(out_raw);
        return error.Corrupt;
    };
    dynFree(in_raw);
    if (@intCast(u64, got) != size) {
        dynFree(out_raw);
        return error.Corrupt;
    }
    if (used > cap) {
        dynFree(out_raw);
        return error.Corrupt;
    }
    const end = try addU64(payload_off, @intCast(u64, used));
    if (end > after_header) {
        dynFree(out_raw);
        return error.Corrupt;
    }
    return Inflated{ .data = out, .used = used, .big = true };
}

pub fn packOpen(arena: *arena_mod.Arena, pack_path: []const u8, idx: *Idx, out: *Pack) !void {
    const file = file_mod.open(arena, pack_path, file_mod.Mode.Read) catch return error.OpenFailed;
    out.file = file;
    const fsz = file_mod.size(&out.file) catch return error.OpenFailed;
    if (fsz < 12 + 20) return error.Corrupt;
    out.file_size = @intCast(u64, fsz);
    out.idx = idx.*;
    const win_raw = arena_mod.alloc(arena, WINDOW_SIZE) catch return error.OutOfMemory;
    out.win = win_raw[0..WINDOW_SIZE];
    out.win_start = 0;
    out.win_len = 0;
    out.count = 0;

    var hdr: [12]u8 = undefined;
    try readAt(out, 0, hdr[0..12]);
    if (hdr[0] != 'P' or hdr[1] != 'A' or hdr[2] != 'C' or hdr[3] != 'K') return error.Corrupt;
    if (be32(hdr[0..], 4) != 2) return error.Corrupt;
    out.count = be32(hdr[0..], 8);
    if (@intCast(usize, out.count) != out.idx.count) return error.Corrupt;

    // Streaming SHA-1 over everything except the 20-byte pack trailer.
    var h = crypto.sha1Init();
    var off: u64 = 0;
    const body_end = out.file_size - 20;
    var chunk: [4096]u8 = undefined;
    while (off < body_end) {
        var n: usize = 4096;
        const left = body_end - off;
        if (left < @intCast(u64, n)) n = @intCast(usize, left);
        try readAt(out, off, chunk[0..n]);
        crypto.sha1Update(&h, chunk[0..n]);
        off += @intCast(u64, n);
    }
    var trailer: ObjectId = undefined;
    crypto.sha1Final(&h, &trailer);
    var on_disk: [20]u8 = undefined;
    try readAt(out, body_end, on_disk[0..20]);
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (trailer[i] != on_disk[i]) return error.Corrupt;
        if (on_disk[i] != out.idx.pack_id[i]) return error.Corrupt;
    }
}

// Open a pack without an idx.  Used only by idxSynthesize: entry parsing and
// the sliding window need file_size, not the idx lookup table.
pub fn packOpenRaw(arena: *arena_mod.Arena, pack_path: []const u8) !Pack {
    const file = file_mod.open(arena, pack_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var p: Pack = undefined;
    p.file = file;
    const fsz = file_mod.size(&p.file) catch return error.OpenFailed;
    if (fsz < 12 + 20) return error.Corrupt;
    p.file_size = @intCast(u64, fsz);
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
    }
    return p;
}

const EntryHeader = struct {
    kind: Kind,
    size: u64,
    base_off: u64,
    base_id: ObjectId,
    payload_off: u64,
};

fn parseEntryHeader(p: *Pack, offset: u64) !EntryHeader {
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
    return EntryHeader{ .kind = kind, .size = size, .base_off = base_off, .base_id = base_id, .payload_off = pos };
}

pub fn readEntry(arena: *arena_mod.Arena, p: *Pack, offset: u64) !RawEntry {
    const h = try parseEntryHeader(p, offset);
    const got = try decompressEntry(arena, p, h.payload_off, h.size);
    var out: RawEntry = undefined;
    out.kind = h.kind;
    out.size = h.size;
    out.base_off = h.base_off;
    var bi: usize = 0;
    while (bi < 20) : (bi += 1) out.base_id[bi] = h.base_id[bi];
    out.payload = got.data;
    out.payload_off = h.payload_off;
    out.payload_len = got.used;
    out.big = got.big;
    return out;
}

pub fn readEntryBig(arena: *arena_mod.Arena, p: *Pack, offset: u64) !RawEntry {
    const h = try parseEntryHeader(p, offset);
    const got = try decompressEntryBig(arena, p, h.payload_off, h.size);
    var out: RawEntry = undefined;
    out.kind = h.kind;
    out.size = h.size;
    out.base_off = h.base_off;
    var bi: usize = 0;
    while (bi < 20) : (bi += 1) out.base_id[bi] = h.base_id[bi];
    out.payload = got.data;
    out.payload_off = h.payload_off;
    out.payload_len = got.used;
    out.big = got.big;
    return out;
}


// --- external-memory idx v2 synthesis ---------------------------------------
//
// idxSynthesize(arena, pack_path, idx_path) is the reusable Task 8 entry point.
// The T8b rewrite keeps the same API and output bytes but bounds memory:
//
//   pass 1  walk the pack once, inflate every entry only to find its zlib
//           extent, CRC the raw packed bytes, write fixed-size (id,offset,crc)
//           records for non-delta objects, and write one metadata record per
//           entry to a temp file.  Payloads are dropped after hashing.
//   pass 2  resolve delta ids in pack order.  Bases are reconstructed on
//           demand from the pack into a reset-per-entry scratch arena; a
//           bounded byte-ring caches small bases.  Each resolved delta appends
//           one (id,offset,crc) record.
//   sort    external merge sort: fixed-size chunks sorted in memory, written as
//           runs, then merged pairwise.  No O(pack) array survives.
//   stream  the sorted records are scanned three times (names, CRCs, offsets)
//           and written straight to the idx; the large-offset table is spilled
//           to a temp file and appended.  The trailers are hashed on the flow.
//
// Temp files live beside the idx and are removed on normal and error paths.
// A self-contained pack is required: a REF_DELTA whose base is not another
// entry in the pack is Corrupt (a thin pack is not a valid object store).

const META_REC: usize = 64;
const ID_REC: usize = 32;
const SORT_CHUNK_DEFAULT: usize = 8192;
const IDX_TRAILER: usize = 40;
const CACHE_SLOTS: usize = 256;

const Resolved = struct {
    ty: Kind,
    data: []u8,
    id: ObjectId,
    big: bool,
};

const CacheEntry = struct {
    valid: bool,
    offset: u64,
    id: ObjectId,
    ty: Kind,
    d_off: usize,
    d_len: usize,
};

const Cache = struct {
    buf: []u8,
    used: usize,
    next: usize,
    entries: [CACHE_SLOTS]CacheEntry,
};

const SortRec = struct {
    id: ObjectId,
    offset: u64,
    crc: u32,
};

const FileWriter = struct {
    f: file_mod.File,
    buf: [8192]u8,
    len: usize,
    hashing: bool,
    hash: crypto.Sha1,
};

const FileReader = struct {
    f: file_mod.File,
    buf: [8192]u8,
    pos: usize,
    len: usize,
    eof: bool,
};

fn getU32le(b: []const u8, off: usize) u32 {
    var v: u32 = @intCast(u32, b[off]);
    v |= @intCast(u32, b[off + 1]) << 8;
    v |= @intCast(u32, b[off + 2]) << 16;
    v |= @intCast(u32, b[off + 3]) << 24;
    return v;
}

fn getU64le(b: []const u8, off: usize) u64 {
    var v: u64 = 0;
    var mul: u64 = 1;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        v += @intCast(u64, b[off + i]) * mul;
        if (i < 7) mul = mul * 256;
    }
    return v;
}

fn putU32le(b: []u8, off: usize, v: u32) void {
    b[off] = @intCast(u8, v & 0xFF);
    b[off + 1] = @intCast(u8, (v >> 8) & 0xFF);
    b[off + 2] = @intCast(u8, (v >> 16) & 0xFF);
    b[off + 3] = @intCast(u8, (v >> 24) & 0xFF);
}

fn putU64le(b: []u8, off: usize, v: u64) void {
    var x = v;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        b[off + i] = @intCast(u8, x & 0xFF);
        x = x / 256;
    }
}

fn removeIfExists(path: []const u8) void {
    file_mod.remove(path) catch {};
}

fn copyId(dst: *ObjectId, src: ObjectId) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) dst[i] = src[i];
}

fn bitMask(i: usize) u8 {
    var m: u8 = 1;
    var s: usize = i % 8;
    while (s > 0) : (s -= 1) m = m * 2;
    return m;
}

fn idEql(a: ObjectId, b: ObjectId) bool {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn idLess(a: ObjectId, b: ObjectId) bool {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (a[i] < b[i]) return true;
        if (a[i] > b[i]) return false;
    }
    return false;
}

fn isBaseKind(k: Kind) bool {
    return k == Kind.commit or k == Kind.tree or k == Kind.blob or k == Kind.tag;
}

fn kindName(k: Kind) []const u8 {
    if (k == Kind.commit) return "commit";
    if (k == Kind.tree) return "tree";
    if (k == Kind.blob) return "blob";
    return "tag";
}

fn putDecimal(dst: []u8, value: u64) usize {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var v = value;
    if (v == 0) {
        dst[0] = '0';
        return 1;
    }
    while (v != 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        n += 1;
        v = v / 10;
    }
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = tmp[n - 1 - i];
    return n;
}

fn synthObjectId(k: Kind, data: []const u8, out: *ObjectId) void {
    var hdr: [40]u8 = undefined;
    const name = kindName(k);
    var n: usize = 0;
    while (n < name.len) : (n += 1) hdr[n] = name[n];
    hdr[n] = ' ';
    n += 1;
    n += putDecimal(hdr[n..], @intCast(u64, data.len));
    hdr[n] = 0;
    n += 1;
    var h = crypto.sha1Init();
    crypto.sha1Update(&h, hdr[0..n]);
    crypto.sha1Update(&h, data);
    crypto.sha1Final(&h, out);
}

fn putBe32(dst: []u8, off: usize, v: u32) void {
    dst[off] = @intCast(u8, (v >> 24) & 0xFF);
    dst[off + 1] = @intCast(u8, (v >> 16) & 0xFF);
    dst[off + 2] = @intCast(u8, (v >> 8) & 0xFF);
    dst[off + 3] = @intCast(u8, v & 0xFF);
}

fn putBe64(dst: []u8, off: usize, v: u64) void {
    dst[off] = @intCast(u8, (v >> 56) & 0xFF);
    dst[off + 1] = @intCast(u8, (v >> 48) & 0xFF);
    dst[off + 2] = @intCast(u8, (v >> 40) & 0xFF);
    dst[off + 3] = @intCast(u8, (v >> 32) & 0xFF);
    dst[off + 4] = @intCast(u8, (v >> 24) & 0xFF);
    dst[off + 5] = @intCast(u8, (v >> 16) & 0xFF);
    dst[off + 6] = @intCast(u8, (v >> 8) & 0xFF);
    dst[off + 7] = @intCast(u8, v & 0xFF);
}

fn pathSuffix(arena: *arena_mod.Arena, base: []const u8, suffix: []const u8) ![]u8 {
    const n64 = try addU64(@intCast(u64, base.len), @intCast(u64, suffix.len));
    if (n64 > 0xFFFFFFFF) return error.OutOfMemory;
    const n: usize = @intCast(usize, n64);
    const raw = arena_mod.alloc(arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < base.len) : (i += 1) raw[i] = base[i];
    i = 0;
    while (i < suffix.len) : (i += 1) raw[base.len + i] = suffix[i];
    return raw[0..n];
}

fn pathSuffixInt(arena: *arena_mod.Arena, base: []const u8, suffix: []const u8, v: u32) ![]u8 {
    const extra: usize = base.len + suffix.len + 12;
    const raw = arena_mod.alloc(arena, extra) catch return error.OutOfMemory;
    var n: usize = 0;
    var i: usize = 0;
    while (i < base.len) : (i += 1) {
        raw[n] = base[i];
        n += 1;
    }
    i = 0;
    while (i < suffix.len) : (i += 1) {
        raw[n] = suffix[i];
        n += 1;
    }
    n += putDecimal(raw[n..extra], @intCast(u64, v));
    return raw[0..n];
}

fn metaOffset(b: []const u8) u64 {
    return getU64le(b, 0);
}

fn metaEnd(b: []const u8) u64 {
    return getU64le(b, 8);
}

fn metaBaseOff(b: []const u8) u64 {
    return getU64le(b, 16);
}

fn metaCrc(b: []const u8) u32 {
    return getU32le(b, 24);
}

fn metaKind(b: []const u8) Kind {
    return typeFromKind(b[28]) catch Kind.blob;
}

fn metaBaseId(b: []const u8, out: *ObjectId) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) out[i] = b[30 + i];
}

fn metaFill(b: []u8, offset: u64, end: u64, crc: u32, kind: Kind, base_off: u64, base_id: ObjectId) void {
    var i: usize = 0;
    while (i < META_REC) : (i += 1) b[i] = 0;
    putU64le(b, 0, offset);
    putU64le(b, 8, end);
    putU64le(b, 16, base_off);
    putU32le(b, 24, crc);
    b[28] = @intCast(u8, @enumToInt(kind));
    i = 0;
    while (i < 20) : (i += 1) b[30 + i] = base_id[i];
}

fn idRecFill(b: []u8, id: ObjectId, offset: u64, crc: u32) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) b[i] = id[i];
    putU64le(b, 20, offset);
    putU32le(b, 28, crc);
}

fn idRecId(b: []const u8, out: *ObjectId) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) out[i] = b[i];
}

fn idRecOffset(b: []const u8) u64 {
    return getU64le(b, 20);
}

fn idRecCrc(b: []const u8) u32 {
    return getU32le(b, 28);
}

// --- bounded base cache ------------------------------------------------------

fn cacheInit(c: *Cache, buf: []u8) void {
    c.buf = buf;
    c.used = 0;
    c.next = 0;
    var i: usize = 0;
    while (i < CACHE_SLOTS) : (i += 1) c.entries[i].valid = false;
}

fn cacheClear(c: *Cache) void {
    c.used = 0;
    var i: usize = 0;
    while (i < CACHE_SLOTS) : (i += 1) c.entries[i].valid = false;
}

fn cacheFindOffset(c: *Cache, offset: u64) ?*CacheEntry {
    var i: usize = 0;
    while (i < CACHE_SLOTS) : (i += 1) {
        const e = &c.entries[i];
        if (e.valid and e.offset == offset) return e;
    }
    return null;
}

fn cacheAdd(c: *Cache, offset: u64, id: ObjectId, ty: Kind, data: []const u8) void {
    // Objects larger than a quarter of the cache are never retained; a delta
    // chain reads them from the pack on demand instead.
    if (c.buf.len == 0) return;
    if (data.len > c.buf.len / 4) return;
    if (c.used + data.len > c.buf.len) cacheClear(c);
    const slot = c.next % CACHE_SLOTS;
    c.next += 1;
    const e = &c.entries[slot];
    e.valid = true;
    e.offset = offset;
    e.ty = ty;
    var i: usize = 0;
    while (i < 20) : (i += 1) e.id[i] = id[i];
    e.d_off = c.used;
    e.d_len = data.len;
    i = 0;
    while (i < data.len) : (i += 1) c.buf[c.used + i] = data[i];
    c.used += data.len;
}

// --- buffered readers/writers -----------------------------------------------

fn writerInit(f: file_mod.File, hashing: bool) FileWriter {
    var w: FileWriter = undefined;
    w.f = f;
    w.len = 0;
    w.hashing = hashing;
    if (hashing) w.hash = crypto.sha1Init();
    return w;
}

fn writerFlush(w: *FileWriter) !void {
    if (w.len == 0) return;
    var off: usize = 0;
    while (off < w.len) {
        const n = file_mod.write(&w.f, w.buf[off..w.len]) catch return error.WriteFailed;
        if (n == 0) return error.WriteFailed;
        off += n;
    }
    if (w.hashing) crypto.sha1Update(&w.hash, w.buf[0..w.len]);
    w.len = 0;
}

fn writerBytes(w: *FileWriter, data: []const u8) !void {
    var off: usize = 0;
    while (off < data.len) {
        if (w.len == w.buf.len) try writerFlush(w);
        const room = w.buf.len - w.len;
        var take = data.len - off;
        if (take > room) take = room;
        var i: usize = 0;
        while (i < take) : (i += 1) w.buf[w.len + i] = data[off + i];
        w.len += take;
        off += take;
    }
}

fn writerFinish(w: *FileWriter) !void {
    try writerFlush(w);
    file_mod.flush(&w.f) catch return error.WriteFailed;
    file_mod.close(&w.f);
}

fn readerInit(f: file_mod.File) FileReader {
    var r: FileReader = undefined;
    r.f = f;
    r.pos = 0;
    r.len = 0;
    r.eof = false;
    return r;
}

fn readerFill(r: *FileReader) !bool {
    if (r.pos < r.len) return true;
    r.pos = 0;
    r.len = 0;
    if (r.eof) return false;
    const n = file_mod.read(&r.f, r.buf[0..]) catch return error.ReadFailed;
    if (n == 0) {
        r.eof = true;
        return false;
    }
    r.len = n;
    return true;
}

fn readerExact(r: *FileReader, dst: []u8) !bool {
    var got: usize = 0;
    while (got < dst.len) {
        if (!try readerFill(r)) {
            if (got == 0) return false;
            return error.ReadFailed;
        }
        var n = r.len - r.pos;
        if (n > dst.len - got) n = dst.len - got;
        var i: usize = 0;
        while (i < n) : (i += 1) dst[got + i] = r.buf[r.pos + i];
        r.pos += n;
        got += n;
    }
    return true;
}

fn readerFinish(r: *FileReader) void {
    file_mod.close(&r.f);
}

// --- delta reconstruction with a bounded cache ------------------------------

fn applyDeltaCached(scratch: *arena_mod.Arena, base: Resolved, raw: RawEntry) !Resolved {
    var src_len: usize = 0;
    var tgt_len: usize = 0;
    delta_mod.deltaSizes(raw.payload, &src_len, &tgt_len) catch return error.Corrupt;
    if (src_len != base.data.len) return error.Corrupt;
    var out_big = false;
    var out: []u8 = undefined;
    if (tgt_len > scratch.capacity / 4 or scratch.used > scratch.capacity or (scratch.capacity - scratch.used) < tgt_len) {
        const raw_out = dynAlloc(tgt_len) orelse return error.OutOfMemory;
        out = raw_out[0..tgt_len];
        out_big = true;
    } else {
        const raw_out = arena_mod.alloc(scratch, tgt_len) catch return error.OutOfMemory;
        out = raw_out[0..tgt_len];
    }
    delta_mod.deltaApply(base.data, raw.payload, out) catch {
        if (out_big) dynFree(out);
        return error.Corrupt;
    };
    var id: ObjectId = undefined;
    synthObjectId(base.ty, out, &id);
    return Resolved{ .ty = base.ty, .data = out, .id = id, .big = out_big };
}

fn findIdOffset(ids_path: []const u8, id: ObjectId) !?u64 {
    // Pass 2 keeps one ReadWrite handle open so scanning the ids file cannot
    // trip Win9x's share-mode rules (a second read handle next to the append
    // handle is a sharing violation). Flush, rewind, scan, then seek back to the
    // end for the next appended record.
    if (g_ids_writer) |w0| {
        const w = w0;
        try writerFlush(w);
        _ = file_mod.seek(&w.f, @intCast(i64, 0), file_mod.SeekWhence.Set) catch return error.OpenFailed;
        var r = readerInit(w.f);
        var b: [ID_REC]u8 = undefined;
        var found: ?u64 = null;
        while (true) {
            const more = try readerExact(&r, b[0..]);
            if (!more) break;
            var got: ObjectId = undefined;
            idRecId(b[0..], &got);
            if (idEql(got, id)) {
                found = idRecOffset(b[0..]);
                break;
            }
        }
        _ = file_mod.seek(&w.f, @intCast(i64, 0), file_mod.SeekWhence.End) catch return error.OpenFailed;
        return found;
    }
    var f = file_mod.open(arenaFor(ids_path), ids_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var r = readerInit(f);
    defer readerFinish(&r);
    var b: [ID_REC]u8 = undefined;
    while (true) {
        const more = try readerExact(&r, b[0..]);
        if (!more) return null;
        var got: ObjectId = undefined;
        idRecId(b[0..], &got);
        if (idEql(got, id)) return idRecOffset(b[0..]);
    }
    return null;
}

var g_ids_writer: ?*FileWriter = null;

// readEntry/per-entry inflation needs an arena; the caller's scratch arena is
// supplied through this small module-level handoff so findIdOffset can open the
// ids file without threading an extra parameter through every recursive call.
var g_find_arena: ?*arena_mod.Arena = null;

fn arenaFor(path: []const u8) *arena_mod.Arena {
    _ = path;
    if (g_find_arena) |a| return a;
    // Unreachable in normal use; findIdOffset is only called from idxSynthesize
    // after setting g_find_arena.
    return @ptrCast(*arena_mod.Arena, @intToPtr(*void, 0));
}

pub fn readEntryMaybeBig(scratch: *arena_mod.Arena, p: *Pack, offset: u64) !RawEntry {
    // Only the actual large/overflow condition falls back to the mmap path.
    // Corruption and real allocation failures propagate unchanged, and the
    // size check is against this scratch (not the whole process) so a 27 MiB
    // object does not depend on the caller's arena having a contiguous half.
    const h = try parseEntryHeader(p, offset);
    const avail: usize = if (scratch.used >= scratch.capacity) 0 else scratch.capacity - scratch.used;
    // decompressEntry allocates the output (size) plus an input window of about
    // size + size/4. Require roughly four times the object size to remain so a
    // near-threshold object cannot consume the output then fail the input alloc.
    if (h.size > @intCast(u64, scratch.capacity / 4) or h.size > @intCast(u64, avail / 4)) {
        return readEntryBig(scratch, p, offset);
    }
    return readEntry(scratch, p, offset);
}

fn resolveAt(p: *Pack, cache: *Cache, scratch: *arena_mod.Arena, ids_path: []const u8, offset: u64, depth: usize, deferred: *bool) !Resolved {
    if (depth > 64) return error.Corrupt;
    if (cacheFindOffset(cache, offset)) |e| {
        var id: ObjectId = undefined;
        var i: usize = 0;
        while (i < 20) : (i += 1) id[i] = e.id[i];
        return Resolved{ .ty = e.ty, .data = cache.buf[e.d_off .. e.d_off + e.d_len], .id = id, .big = false };
    }

    const raw = try readEntryMaybeBig(scratch, p, offset);
    var res: Resolved = undefined;
    if (raw.kind == Kind.ofs_delta) {
        const base = try resolveAt(p, cache, scratch, ids_path, raw.base_off, depth + 1, deferred);
        if (deferred.*) {
            if (raw.big) dynFree(raw.payload);
            return Resolved{ .ty = Kind.blob, .data = cache.buf[0..0], .id = raw.base_id, .big = false };
        }
        res = applyDeltaCached(scratch, base, raw) catch |e| {
            if (raw.big) dynFree(raw.payload);
            if (base.big) dynFree(base.data);
            if (e == error.OutOfMemory) return error.OutOfMemory;
            return error.Corrupt;
        };
        if (raw.big) dynFree(raw.payload);
        if (base.big) dynFree(base.data);
    } else if (raw.kind == Kind.ref_delta) {
        const bo = try findIdOffset(ids_path, raw.base_id);
        if (bo) |base_off| {
            const base = try resolveAt(p, cache, scratch, ids_path, base_off, depth + 1, deferred);
            if (deferred.*) {
                if (raw.big) dynFree(raw.payload);
                return Resolved{ .ty = Kind.blob, .data = cache.buf[0..0], .id = raw.base_id, .big = false };
            }
            res = applyDeltaCached(scratch, base, raw) catch |e| {
                if (raw.big) dynFree(raw.payload);
                if (base.big) dynFree(base.data);
                if (e == error.OutOfMemory) return error.OutOfMemory;
                return error.Corrupt;
            };
            if (raw.big) dynFree(raw.payload);
            if (base.big) dynFree(base.data);
        } else {
            deferred.* = true;
            if (raw.big) dynFree(raw.payload);
            return Resolved{ .ty = Kind.blob, .data = cache.buf[0..0], .id = raw.base_id, .big = false };
        }
    } else {
        if (!isBaseKind(raw.kind)) {
            if (raw.big) dynFree(raw.payload);
            return error.Corrupt;
        }
        var id: ObjectId = undefined;
        synthObjectId(raw.kind, raw.payload, &id);
        res = Resolved{ .ty = raw.kind, .data = raw.payload, .id = id, .big = raw.big };
    }
    cacheAdd(cache, offset, res.id, res.ty, res.data);
    return res;
}

// --- external merge sort -----------------------------------------------------

fn recLess(a: SortRec, b: SortRec) bool {
    if (idLess(a.id, b.id)) return true;
    if (idLess(b.id, a.id)) return false;
    return a.offset < b.offset;
}

fn mergeRecBlock(a: []SortRec, tmp: []SortRec, lo: usize, mid: usize, hi: usize) void {
    var i = lo;
    var j = mid;
    var k = lo;
    while (i < mid and j < hi) {
        if (recLess(a[i], a[j])) {
            tmp[k] = a[i];
            i += 1;
        } else {
            tmp[k] = a[j];
            j += 1;
        }
        k += 1;
    }
    while (i < mid) {
        tmp[k] = a[i];
        i += 1;
        k += 1;
    }
    while (j < hi) {
        tmp[k] = a[j];
        j += 1;
        k += 1;
    }
}

fn sortRecs(a: []SortRec, tmp: []SortRec) void {
    const n = a.len;
    if (n < 2) return;
    var width: usize = 1;
    while (width < n) {
        var lo: usize = 0;
        while (lo < n) {
            var mid = lo + width;
            if (mid > n) mid = n;
            var hi = lo + width * 2;
            if (hi > n) hi = n;
            mergeRecBlock(a, tmp, lo, mid, hi);
            lo += width * 2;
        }
        var i: usize = 0;
        while (i < n) : (i += 1) a[i] = tmp[i];
        if (width > n / 2) break;
        width = width * 2;
    }
}

fn recToBytes(r: SortRec, b: []u8) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) b[i] = r.id[i];
    putU64le(b, 20, r.offset);
    putU32le(b, 28, r.crc);
}

fn recFromBytes(b: []const u8, out: *SortRec) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) out.id[i] = b[i];
    out.offset = getU64le(b, 20);
    out.crc = getU32le(b, 28);
}

fn writeRun(arena: *arena_mod.Arena, idx_path: []const u8, run_i: u32, recs: []SortRec, n: usize) !void {
    const path = try pathSuffixInt(arena, idx_path, ".z9run", run_i);
    const f = file_mod.open(arena, path, file_mod.Mode.Write) catch return error.OpenFailed;
    var w = writerInit(f, false);
    var b: [SORT_REC_BYTES]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        recToBytes(recs[i], b[0..]);
        try writerBytes(&w, b[0..]);
    }
    try writerFinish(&w);
}

const SORT_REC_BYTES: usize = 32;

fn mergeRuns(arena: *arena_mod.Arena, idx_path: []const u8, a_i: u32, b_i: u32, out_i: u32) !void {
    const pa = try pathSuffixInt(arena, idx_path, ".z9run", a_i);
    const pb = try pathSuffixInt(arena, idx_path, ".z9run", b_i);
    const po = try pathSuffixInt(arena, idx_path, ".z9run", out_i);
    const fa = file_mod.open(arena, pa, file_mod.Mode.Read) catch return error.OpenFailed;
    var ra = readerInit(fa);
    defer readerFinish(&ra);
    const fb = file_mod.open(arena, pb, file_mod.Mode.Read) catch return error.OpenFailed;
    var rb = readerInit(fb);
    defer readerFinish(&rb);
    const fo = file_mod.open(arena, po, file_mod.Mode.Write) catch return error.OpenFailed;
    var w = writerInit(fo, false);

    var ba: [SORT_REC_BYTES]u8 = undefined;
    var bb: [SORT_REC_BYTES]u8 = undefined;
    var ra_rec: SortRec = undefined;
    var rb_rec: SortRec = undefined;
    var oa: [SORT_REC_BYTES]u8 = undefined;
    var have_a = try readerExact(&ra, ba[0..]);
    var have_b = try readerExact(&rb, bb[0..]);
    if (have_a) recFromBytes(ba[0..], &ra_rec);
    if (have_b) recFromBytes(bb[0..], &rb_rec);
    while (have_a or have_b) {
        var take_a = false;
        if (have_a and have_b) {
            take_a = recLess(ra_rec, rb_rec);
        } else if (have_a) {
            take_a = true;
        }
        if (take_a) {
            recToBytes(ra_rec, oa[0..]);
            try writerBytes(&w, oa[0..]);
            have_a = try readerExact(&ra, ba[0..]);
            if (have_a) recFromBytes(ba[0..], &ra_rec);
        } else {
            recToBytes(rb_rec, oa[0..]);
            try writerBytes(&w, oa[0..]);
            have_b = try readerExact(&rb, bb[0..]);
            if (have_b) recFromBytes(bb[0..], &rb_rec);
        }
    }
    try writerFinish(&w);
    removeIfExists(pa);
    removeIfExists(pb);
}

// --- streamed idx writer -----------------------------------------------------

fn writeIdxEmpty(idx_path: []const u8) !void {
    var out: [8 + 1024 + IDX_TRAILER]u8 = undefined;
    var i: usize = 0;
    while (i < out.len) : (i += 1) out[i] = 0;
    out[0] = 0xFF;
    out[1] = 't';
    out[2] = 'O';
    out[3] = 'c';
    putBe32(out[0..], 4, 2);
    var h = crypto.sha1Init();
    crypto.sha1Update(&h, out[0 .. 8 + 1024]);
    var idx_id: ObjectId = undefined;
    crypto.sha1Final(&h, &idx_id);
    i = 0;
    while (i < 20) : (i += 1) out[8 + 1024 + 20 + i] = idx_id[i];
    file_mod.writeAll(idx_path, out[0..]) catch return error.WriteFailed;
}

fn writeIdxStream(arena: *arena_mod.Arena, p: *Pack, idx_path: []const u8, sorted_path: []const u8, large_path: []const u8, n: usize, large_count: usize) !void {
    _ = large_count;
    _ = n;
    const fo = file_mod.open(arena, idx_path, file_mod.Mode.Write) catch return error.OpenFailed;
    var w = writerInit(fo, true);

    // Header + fanout.
    var head: [8 + 1024]u8 = undefined;
    var i: usize = 0;
    while (i < head.len) : (i += 1) head[i] = 0;
    head[0] = 0xFF;
    head[1] = 't';
    head[2] = 'O';
    head[3] = 'c';
    putBe32(head[0..], 4, 2);

    var counts: [256]u32 = undefined;
    i = 0;
    while (i < 256) : (i += 1) counts[i] = 0;

    // Fanout pass.
    var rf = file_mod.open(arena, sorted_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var rr = readerInit(rf);
    var b: [SORT_REC_BYTES]u8 = undefined;
    var rec: SortRec = undefined;
    while (try readerExact(&rr, b[0..])) {
        recFromBytes(b[0..], &rec);
        counts[@intCast(usize, rec.id[0])] += 1;
    }
    readerFinish(&rr);

    var cum: u32 = 0;
    i = 0;
    while (i < 256) : (i += 1) {
        cum += counts[i];
        putBe32(head[0..], 8 + i * 4, cum);
    }
    try writerBytes(&w, head[0..]);

    // Names pass.
    rf = file_mod.open(arena, sorted_path, file_mod.Mode.Read) catch return error.OpenFailed;
    rr = readerInit(rf);
    while (try readerExact(&rr, b[0..])) {
        try writerBytes(&w, b[0..20]);
    }
    readerFinish(&rr);

    // CRC pass.
    rf = file_mod.open(arena, sorted_path, file_mod.Mode.Read) catch return error.OpenFailed;
    rr = readerInit(rf);
    while (try readerExact(&rr, b[0..])) {
        recFromBytes(b[0..], &rec);
        var cb: [4]u8 = undefined;
        putBe32(cb[0..], 0, rec.crc);
        try writerBytes(&w, cb[0..]);
    }
    readerFinish(&rr);

    // Offset pass: small offsets inline, large offsets spilled to large_path.
    const fl = file_mod.open(arena, large_path, file_mod.Mode.Write) catch return error.OpenFailed;
    var lw = writerInit(fl, false);
    var large_i: u32 = 0;
    rf = file_mod.open(arena, sorted_path, file_mod.Mode.Read) catch return error.OpenFailed;
    rr = readerInit(rf);
    while (try readerExact(&rr, b[0..])) {
        recFromBytes(b[0..], &rec);
        var ob: [4]u8 = undefined;
        if (rec.offset <= 0x7FFFFFFF) {
            putBe32(ob[0..], 0, @intCast(u32, rec.offset));
            try writerBytes(&w, ob[0..]);
        } else {
            if (large_i > 0x7FFFFFFF) return error.Corrupt;
            putBe32(ob[0..], 0, @intCast(u32, 0x80000000) + large_i);
            try writerBytes(&w, ob[0..]);
            var lb: [8]u8 = undefined;
            putBe64(lb[0..], 0, rec.offset);
            try writerBytes(&lw, lb[0..]);
            large_i += 1;
        }
    }
    readerFinish(&rr);
    try writerFinish(&lw);

    // Append the large-offset table.
    const lf = file_mod.open(arena, large_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var lr = readerInit(lf);
    var chunk: [4096]u8 = undefined;
    while (true) {
        if (!try readerFill(&lr)) break;
        const avail = lr.len - lr.pos;
        const take = if (avail > chunk.len) chunk.len else avail;
        var k: usize = 0;
        while (k < take) : (k += 1) chunk[k] = lr.buf[lr.pos + k];
        lr.pos += take;
        try writerBytes(&w, chunk[0..take]);
    }
    readerFinish(&lr);

    // Pack SHA-1 trailer (from the pack), then this idx's SHA-1 trailer.
    var pack_id: ObjectId = undefined;
    const body_end = p.file_size - 20;
    try readAt(p, body_end, pack_id[0..20]);
    try writerBytes(&w, pack_id[0..20]);

    var idx_id: ObjectId = undefined;
    try writerFlush(&w);
    crypto.sha1Final(&w.hash, &idx_id);
    w.hashing = false;
    try writerBytes(&w, idx_id[0..20]);

    try writerFinish(&w);
}

pub fn idxSynthesize(arena: *arena_mod.Arena, pack_path: []const u8, idx_path: []const u8) !void {
    var p = try packOpenRaw(arena, pack_path);
    defer file_mod.close(&p.file);
    const n: usize = @intCast(usize, p.count);
    const body_end = p.file_size - 20;

    const meta_path = try pathSuffix(arena, idx_path, ".z9meta");
    const ids_path = try pathSuffix(arena, idx_path, ".z9ids");
    const sorted_path = try pathSuffix(arena, idx_path, ".z9sort");
    const large_path = try pathSuffix(arena, idx_path, ".z9large");
    defer removeIfExists(meta_path);
    defer removeIfExists(ids_path);
    defer removeIfExists(sorted_path);
    defer removeIfExists(large_path);

    // Allocate the work scratch, base cache and per-pack tables outside the app
    // arena. They are freed when this pack's idx is complete, so a clone with
    // several packs does not accumulate per-pack scratch.
    var scratch_bytes = arena.capacity / 2;
    if (scratch_bytes > 16 * 1024 * 1024) scratch_bytes = 16 * 1024 * 1024;
    if (scratch_bytes < 256 * 1024) scratch_bytes = 256 * 1024;
    var cache_bytes = arena.capacity;
    if (cache_bytes > 32 * 1024 * 1024) cache_bytes = 32 * 1024 * 1024;
    if (cache_bytes < 1024 * 1024) cache_bytes = 1024 * 1024;
    const scratch_raw = dynAlloc(scratch_bytes) orelse return error.OutOfMemory;
    defer dynFree(scratch_raw);
    var scratch = arena_mod.init(scratch_raw[0..scratch_bytes]);
    const cache_raw = dynAlloc(cache_bytes) orelse return error.OutOfMemory;
    defer dynFree(cache_raw);
    var cache: Cache = undefined;
    cacheInit(&cache, cache_raw[0..cache_bytes]);

    const resolved_bytes = (n + 7) / 8;
    const resolved_raw = dynAlloc(if (resolved_bytes == 0) 1 else resolved_bytes) orelse return error.OutOfMemory;
    defer dynFree(resolved_raw);
    const resolved = resolved_raw[0..if (resolved_bytes == 0) 1 else resolved_bytes];
    var ri: usize = 0;
    while (ri < resolved_bytes) : (ri += 1) resolved[ri] = 0;

    // Pass 1: walk entries, CRC them, write metadata and non-delta ids.
    var meta_f = file_mod.open(arena, meta_path, file_mod.Mode.Write) catch return error.OpenFailed;
    var mw = writerInit(meta_f, false);
    var ids_f = file_mod.open(arena, ids_path, file_mod.Mode.Write) catch return error.OpenFailed;
    var iw = writerInit(ids_f, false);

    var off: u64 = 12;
    var i: usize = 0;
    var resolved_count: usize = 0;
    var crc_buf: [4096]u8 = undefined;
    while (i < n) : (i += 1) {
        arena_mod.reset(&scratch);
        const raw = try readEntryMaybeBig(&scratch, &p, off);
        const end = try addU64(raw.payload_off, @intCast(u64, raw.payload_len));
        if (end > body_end) return error.Corrupt;
        var crc = crypto.crc32Init();
        var scan: u64 = off;
        while (scan < end) {
            var take: usize = 4096;
            const left = end - scan;
            if (left < @intCast(u64, take)) take = @intCast(usize, left);
            try readAt(&p, scan, crc_buf[0..take]);
            crc = crypto.crc32Update(crc, crc_buf[0..take]);
            scan += @intCast(u64, take);
        }
        crc = crypto.crc32Final(crc);

        var mrec: [META_REC]u8 = undefined;
        metaFill(mrec[0..], off, end, crc, raw.kind, raw.base_off, raw.base_id);
        try writerBytes(&mw, mrec[0..]);

        if (isBaseKind(raw.kind)) {
            var id: ObjectId = undefined;
            synthObjectId(raw.kind, raw.payload, &id);
            var irec: [ID_REC]u8 = undefined;
            idRecFill(irec[0..], id, off, crc);
            try writerBytes(&iw, irec[0..]);
            cacheAdd(&cache, off, id, raw.kind, raw.payload);
            const bit = i / 8;
            const mask: u8 = bitMask(i);
            resolved[bit] |= mask;
            resolved_count += 1;
        } else if (raw.kind != Kind.ofs_delta and raw.kind != Kind.ref_delta) {
            return error.Corrupt;
        }
        if (raw.big) dynFree(raw.payload);
        off = end;
    }
    if (off != body_end) return error.Corrupt;
    try writerFinish(&mw);
    try writerFinish(&iw);

    // Pass 2: resolve deltas in pack order until every entry has an id record.
    g_find_arena = &scratch;
    defer g_find_arena = null;
    var pass_count: usize = 0;
    while (resolved_count < n) {
        pass_count += 1;
        if (pass_count > 64) return error.Corrupt;
        var progress = false;

        var mf = file_mod.open(arena, meta_path, file_mod.Mode.Read) catch return error.OpenFailed;
        var mr = readerInit(mf);
        var ia = file_mod.open(arena, ids_path, file_mod.Mode.ReadWrite) catch return error.OpenFailed;
        _ = file_mod.seek(&ia, @intCast(i64, 0), file_mod.SeekWhence.End) catch {
            file_mod.close(&ia);
            return error.OpenFailed;
        };
        var iw2 = writerInit(ia, false);
        g_ids_writer = &iw2;

        i = 0;
        var mrec: [META_REC]u8 = undefined;
        while (try readerExact(&mr, mrec[0..])) : (i += 1) {
            const bit = i / 8;
            const mask: u8 = bitMask(i);
            if ((resolved[bit] & mask) != 0) continue;
            const kind = metaKind(mrec[0..]);
            if (kind != Kind.ofs_delta and kind != Kind.ref_delta) return error.Corrupt;
            const entry_off = metaOffset(mrec[0..]);
            arena_mod.reset(&scratch);
            try writerFlush(&iw2);
            var deferred = false;
            const res = resolveAt(&p, &cache, &scratch, ids_path, entry_off, 0, &deferred) catch |e| {
                if (e == error.OutOfMemory) return error.OutOfMemory;
                return error.Corrupt;
            };
            if (deferred) continue;
            var irec: [ID_REC]u8 = undefined;
            idRecFill(irec[0..], res.id, entry_off, metaCrc(mrec[0..]));
            try writerBytes(&iw2, irec[0..]);
            if (res.big) dynFree(res.data);
            resolved[bit] |= mask;
            resolved_count += 1;
            progress = true;
        }
        readerFinish(&mr);
        g_ids_writer = null;
        try writerFinish(&iw2);
        if (!progress) return error.Corrupt;
    }

    // External sort of all id records.
    const chunk_n: usize = SORT_CHUNK_DEFAULT;
    const recs_raw = dynAlloc(chunk_n * @sizeOf(SortRec)) orelse return error.OutOfMemory;
    defer dynFree(recs_raw);
    const tmp_raw = dynAlloc(chunk_n * @sizeOf(SortRec)) orelse return error.OutOfMemory;
    defer dynFree(tmp_raw);
    const recs = @ptrCast([*]SortRec, recs_raw.ptr)[0..chunk_n];
    const tmp = @ptrCast([*]SortRec, tmp_raw.ptr)[0..chunk_n];

    const initial_runs = (n + chunk_n - 1) / chunk_n;
    const runs_raw = dynAlloc((initial_runs * 2 + 8) * 4) orelse return error.OutOfMemory;
    defer dynFree(runs_raw);
    const runs = @ptrCast([*]u32, runs_raw.ptr)[0..(initial_runs * 2 + 8)];

    var run_count: usize = 0;
    var next_run: u32 = 0;
    if (n > 0) {
        var inf = file_mod.open(arena, ids_path, file_mod.Mode.Read) catch return error.OpenFailed;
        var inr = readerInit(inf);
        var rb: [SORT_REC_BYTES]u8 = undefined;
        while (true) {
            var got: usize = 0;
            while (got < chunk_n) {
                const more = try readerExact(&inr, rb[0..]);
                if (!more) break;
                recFromBytes(rb[0..], &recs[got]);
                got += 1;
            }
            if (got == 0) break;
            sortRecs(recs[0..got], tmp[0..got]);
            try writeRun(arena, idx_path, next_run, recs[0..got], got);
            runs[run_count] = next_run;
            run_count += 1;
            next_run += 1;
        }
        readerFinish(&inr);
    }

    // Keep every temp run path around for cleanup; the caller removes the final
    // sorted run too after the idx is written.
    var final_run: u32 = 0;
    if (run_count > 0) {
        while (run_count > 1) {
            var out_count: usize = 0;
            var k: usize = 0;
            while (k + 1 < run_count) {
                const a_i = runs[k];
                const b_i = runs[k + 1];
                const out_i = next_run;
                next_run += 1;
                try mergeRuns(arena, idx_path, a_i, b_i, out_i);
                runs[out_count] = out_i;
                out_count += 1;
                k += 2;
            }
            if (k < run_count) {
                runs[out_count] = runs[k];
                out_count += 1;
            }
            run_count = out_count;
        }
        final_run = runs[0];
    }
    const final_path = try pathSuffixInt(arena, idx_path, ".z9run", final_run);
    defer removeIfExists(final_path);

    if (n == 0) {
        try writeIdxEmpty(idx_path);
        return;
    }

    // One scan for the large-offset count (the writer detects it again).
    var large_count: usize = 0;
    var sf = file_mod.open(arena, final_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var sr = readerInit(sf);
    var sb: [SORT_REC_BYTES]u8 = undefined;
    var srec: SortRec = undefined;
    while (try readerExact(&sr, sb[0..])) {
        recFromBytes(sb[0..], &srec);
        if (srec.offset > 0x7FFFFFFF) large_count += 1;
    }
    readerFinish(&sr);

    try writeIdxStream(arena, &p, idx_path, final_path, large_path, n, large_count);
}
