// resume.zig — z9torr: fastresume sidecar (bencode) + re-hash on start.
//
// Spec 2026-10-08 §7. The sidecar `.z9torr.resume` is bencode:
//
//   d
//     10:info_hash    20:<20 bytes>
//     12:total_length i<n>e
//     5:mtime         i<n>e
//     13:completed_bits <n>:<ceil(pieces/8) bits>
//     7:partial       l(d5:indexi<i>e10:block_mask<n>:<ceil(blocks/8)>e)…ee
//   e
//
// `load` returns a `ResumeState` whose `completed_bits` is always allocated to
// the right size (zeroed = all missing). The sidecar is trusted only when
// `info_hash`, `total_length`, AND the output file's mtime all match; on any
// mismatch (or absence) the zeroed state is returned and `rehash` rebuilds the
// verified set from the file itself. Mutating the output changes its mtime,
// which invalidates the sidecar — the mechanism that catches a corrupt piece on
// restart. `rehash` SHA-1s only pieces not already verified.
//
// Z98 D2: `ResumeState.partial` is `[]PartialPiece` (a named struct) and
// `PartialPiece.block_mask` is `[]u8` (primitive) — no `[]`-of-synthetic type.

const std = @import("std");
const filemod = @import("std_file.zig");
const bencode = @import("std_bencode");
const crypto = @import("std_crypto");
const disk = @import("disk.zig");
const torrent = @import("torrent.zig");

pub const PartialPiece = struct {
    index: u32,
    block_mask: []u8,
};

pub const ResumeState = struct {
    completed_bits: []u8,
    partial: []PartialPiece,
};

pub const ResumeError = error{ OutOfMemory, SaveFailed };

const BITS_PER_BYTE: u32 = 8;
const HASH_LEN: usize = 20;

// Zero-length fallbacks for the (practically unreachable) OOM path of load.
var g_empty_bits: [1]u8 = undefined;
var g_empty_partial: [1]PartialPiece = undefined;

fn emptyState() ResumeState {
    return ResumeState{ .completed_bits = g_empty_bits[0..0], .partial = g_empty_partial[0..0] };
}

fn pieceCount(t: torrent.Torrent) u32 {
    if (t.total_length == 0) return 0;
    var pl: u64 = @intCast(u64, t.piece_length);
    var n: u64 = (t.total_length + pl - 1) / pl;
    return @intCast(u32, n);
}

fn bitsBytes(n: u32) usize {
    return @intCast(usize, (n + BITS_PER_BYTE - 1) / BITS_PER_BYTE);
}

fn bitGet(bits: []u8, i: u32) bool {
    var byte: usize = @intCast(usize, i / BITS_PER_BYTE);
    var sh: u8 = @intCast(u8, BITS_PER_BYTE - 1 - (i % BITS_PER_BYTE));
    return ((bits[byte] >> sh) & @intCast(u8, 1)) == @intCast(u8, 1);
}

fn bitSet(bits: []u8, i: u32) void {
    var byte: usize = @intCast(usize, i / BITS_PER_BYTE);
    var sh: u8 = @intCast(u8, BITS_PER_BYTE - 1 - (i % BITS_PER_BYTE));
    var mask: u8 = @intCast(u8, 1) << sh;
    bits[byte] = bits[byte] | mask;
}

fn bitClear(bits: []u8, i: u32) void {
    var byte: usize = @intCast(usize, i / BITS_PER_BYTE);
    var sh: u8 = @intCast(u8, BITS_PER_BYTE - 1 - (i % BITS_PER_BYTE));
    var mask: u8 = @intCast(u8, 1) << sh;
    bits[byte] = bits[byte] & ~mask;
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

fn allocValues(ar: *std.arena.Arena, n: usize) ResumeError![]bencode.Value {
    const p = std.arena.alloc(ar, n * @sizeOf(bencode.Value)) catch return error.OutOfMemory;
    return @ptrCast([*]bencode.Value, p)[0..n];
}

fn allocEntries(ar: *std.arena.Arena, n: usize) ResumeError![]bencode.Entry {
    const p = std.arena.alloc(ar, n * @sizeOf(bencode.Entry)) catch return error.OutOfMemory;
    return @ptrCast([*]bencode.Entry, p)[0..n];
}

// SHA-1 `piece index` from `f` (via disk.readPiece) and compare to
// `t.piece_hashes[index*20 .. index*20+20]`.
fn verifyPiece(t: torrent.Torrent, f: *filemod.File, index: u32, buf: []u8) bool {
    var plen: u32 = disk.pieceLength(t, index);
    if (plen == 0) return false;
    var want: usize = @intCast(usize, plen);
    if (want > buf.len) return false;
    var got: usize = disk.readPiece(f, t, index, buf[0..want]) catch return false;
    if (got != want) return false;
    var hs = crypto.sha1Init();
    crypto.sha1Update(&hs, buf[0..got]);
    var h: [20]u8 = undefined;
    crypto.sha1Final(&hs, &h);
    var off: usize = @intCast(usize, index) * HASH_LEN;
    if (off + HASH_LEN > t.piece_hashes.len) return false;
    var k: usize = 0;
    while (k < HASH_LEN) : (k += 1) {
        if (h[k] != t.piece_hashes[off + k]) return false;
    }
    return true;
}

// Load the sidecar into a correctly sized `ResumeState`. Never fails: a
// missing, unreadable, malformed, or non-matching sidecar yields the zeroed
// (all-missing) state, and `rehash` recovers from the file.
pub fn load(arena: *std.arena.Arena, t: torrent.Torrent, out_file: *filemod.File) ResumeState {
    var nbits: usize = bitsBytes(pieceCount(t));
    var raw = std.arena.alloc(arena, nbits) catch return emptyState();
    var bits: []u8 = raw[0..nbits];
    var zi: usize = 0;
    while (zi < nbits) : (zi += 1) {
        bits[zi] = 0;
    }
    var state: ResumeState = ResumeState{ .completed_bits = bits, .partial = g_empty_partial[0..0] };

    var sz: i64 = filemod.size(out_file) catch return state;
    if (sz < 0) return state;
    if (@intCast(u64, sz) != t.total_length) return state;
    if (!filemod.exists(".z9torr.resume")) return state;

    var bytes: []u8 = filemod.readAll(arena, ".z9torr.resume") catch return state;
    var v = bencode.decode(arena, bytes) catch return state;
    var top: []bencode.Entry = undefined;
    switch (v) {
        .dict => |d| {
            top = d;
        },
        else => return state,
    }

    // --- info_hash (exactly 20 bytes, equal) ---
    var ih_i: usize = 0;
    if (findEntry(top, "info_hash")) |x| {
        ih_i = x;
    } else {
        return state;
    }
    switch (top[ih_i].value) {
        .bytes => |b| {
            if (b.len != HASH_LEN) return state;
            var k: usize = 0;
            while (k < HASH_LEN) : (k += 1) {
                if (b[k] != t.info_hash[k]) return state;
            }
        },
        else => return state,
    }

    // --- total_length ---
    var tl_i: usize = 0;
    if (findEntry(top, "total_length")) |x| {
        tl_i = x;
    } else {
        return state;
    }
    switch (top[tl_i].value) {
        .int_val => |n| {
            if (n != @intCast(i64, t.total_length)) return state;
        },
        else => return state,
    }

    // --- mtime (must equal the output file's current mtime) ---
    var mt_i: usize = 0;
    if (findEntry(top, "mtime")) |x| {
        mt_i = x;
    } else {
        return state;
    }
    var cur_mtime: i64 = filemod.mtime(t.name) catch return state;
    switch (top[mt_i].value) {
        .int_val => |n| {
            if (n != cur_mtime) return state;
        },
        else => return state,
    }

    // --- completed_bits (must be exactly nbits) ---
    var cb_i: usize = 0;
    if (findEntry(top, "completed_bits")) |x| {
        cb_i = x;
    } else {
        return state;
    }
    var src_bits: []const u8 = undefined;
    switch (top[cb_i].value) {
        .bytes => |b| {
            if (b.len != nbits) return state;
            src_bits = b;
        },
        else => return state,
    }
    zi = 0;
    while (zi < nbits) : (zi += 1) {
        bits[zi] = src_bits[zi];
    }

    // --- partial (optional; parsed after the mandatory fields validate) ---
    if (findEntry(top, "partial")) |pi| {
        switch (top[pi].value) {
            .list => |items| {
                var praw = std.arena.alloc(arena, items.len * @sizeOf(PartialPiece)) catch return state;
                var pp: []PartialPiece = @ptrCast([*]PartialPiece, praw)[0..items.len];
                var q: usize = 0;
                while (q < items.len) : (q += 1) {
                    var dent: []bencode.Entry = undefined;
                    switch (items[q]) {
                        .dict => |dd| {
                            dent = dd;
                        },
                        else => return state,
                    }
                    var di: usize = 0;
                    if (findEntry(dent, "index")) |x| {
                        di = x;
                    } else {
                        return state;
                    }
                    var pidx: u32 = 0;
                    switch (dent[di].value) {
                        .int_val => |n| {
                            if (n < 0) return state;
                            pidx = @intCast(u32, n);
                        },
                        else => return state,
                    }
                    var bi: usize = 0;
                    if (findEntry(dent, "block_mask")) |x| {
                        bi = x;
                    } else {
                        return state;
                    }
                    var mask_src: []const u8 = undefined;
                    switch (dent[bi].value) {
                        .bytes => |b| {
                            mask_src = b;
                        },
                        else => return state,
                    }
                    var mraw = std.arena.alloc(arena, mask_src.len) catch return state;
                    var mask: []u8 = mraw[0..mask_src.len];
                    var m: usize = 0;
                    while (m < mask_src.len) : (m += 1) {
                        mask[m] = mask_src[m];
                    }
                    pp[q] = PartialPiece{ .index = pidx, .block_mask = mask };
                }
                state.partial = pp;
            },
            else => return state,
        }
    }

    return state;
}

// Re-hash every piece not already marked verified in `state.completed_bits`.
// Matches set the bit; mismatches leave it clear. Mutates the bit buffer in
// place (the slice is shared with the caller's state).
pub fn rehash(arena: *std.arena.Arena, t: torrent.Torrent, f: *filemod.File, state: ResumeState) ResumeError!void {
    var n: u32 = pieceCount(t);
    var needed: usize = bitsBytes(n);
    if (state.completed_bits.len < needed) return error.OutOfMemory;
    var plen: usize = @intCast(usize, t.piece_length);
    if (plen == 0) return error.OutOfMemory;
    var raw = std.arena.alloc(arena, plen) catch return error.OutOfMemory;
    var buf: []u8 = raw[0..plen];
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        if (!bitGet(state.completed_bits, i)) {
            if (verifyPiece(t, f, i, buf)) {
                bitSet(state.completed_bits, i);
            } else {
                bitClear(state.completed_bits, i);
            }
        }
    }
}

// Re-encode and write the whole sidecar. Called after each verified piece and
// on clean completion (spec §7); allocation is from `arena`.
pub fn save(arena: *std.arena.Arena, t: torrent.Torrent, state: ResumeState) ResumeError!void {
    var entries: []bencode.Entry = try allocEntries(arena, 5);
    var ih: []const u8 = t.info_hash[0..];
    entries[0] = bencode.Entry{ .key = "info_hash", .value = bencode.Value{ .bytes = ih } };
    entries[1] = bencode.Entry{ .key = "total_length", .value = bencode.Value{ .int_val = @intCast(i64, t.total_length) } };
    var mt: i64 = filemod.mtime(t.name) catch @intCast(i64, 0);
    entries[2] = bencode.Entry{ .key = "mtime", .value = bencode.Value{ .int_val = mt } };
    var cb: []const u8 = state.completed_bits;
    entries[3] = bencode.Entry{ .key = "completed_bits", .value = bencode.Value{ .bytes = cb } };

    var pv: []bencode.Value = try allocValues(arena, state.partial.len);
    var pi: usize = 0;
    while (pi < state.partial.len) : (pi += 1) {
        var pe: []bencode.Entry = try allocEntries(arena, 2);
        pe[0] = bencode.Entry{ .key = "index", .value = bencode.Value{ .int_val = @intCast(i64, state.partial[pi].index) } };
        var bm: []const u8 = state.partial[pi].block_mask;
        pe[1] = bencode.Entry{ .key = "block_mask", .value = bencode.Value{ .bytes = bm } };
        pv[pi] = bencode.Value{ .dict = pe };
    }
    entries[4] = bencode.Entry{ .key = "partial", .value = bencode.Value{ .list = pv } };

    var root: bencode.Value = bencode.Value{ .dict = entries };
    var out: []u8 = bencode.encode(arena, root) catch return error.OutOfMemory;
    filemod.writeAll(".z9torr.resume", out) catch return error.SaveFailed;
}
