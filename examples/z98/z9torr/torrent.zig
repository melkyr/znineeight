// torrent.zig — z9torr: parse a single-file .torrent into `Torrent`.
//
// Consumes `std_bencode` (decode + dictValueSpan) and `std_crypto` (SHA-1).
// `info_hash` is SHA-1 over the EXACT `info` dictionary bytes from the input
// file (never re-encoded): `dictValueSpan` yields the raw span.
//
// Single-file only (spec 2026-10-08 §1/§6): `info.length` is required and
// `info.files` is rejected implicitly (absent `length` -> MissingField).

const std = @import("std");
const bencode = @import("std_bencode");
const crypto = @import("std_crypto");

pub const Torrent = struct {
    announce: []const u8,
    announce_list: [][]const u8,
    info_hash: [20]u8,
    name: []const u8,
    piece_length: u32,
    piece_hashes: []const u8,
    total_length: u64,
};

pub const TorrentError = error{
    MalformedBencode,
    MissingField,
    BadInfoHash,
    BadPieceCount,
    BadFilePath,
    TooLarge,
    OutOfMemory,
};

// Piece-length sanity window (spec/brief): 16 KiB .. 16 MiB.
const MIN_PIECE_LENGTH: i64 = 16384;
const MAX_PIECE_LENGTH: i64 = 16777216;

// Blueprint Stage 3 limit: at most 2^20 pieces.
const MAX_PIECES: usize = 1048576;

const HASH_LEN: usize = 20;

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn findIndex(entries: []bencode.Entry, key: []const u8) ?usize {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eqBytes(entries[i].key, key)) return i;
    }
    return null;
}

pub fn load(arena: *std.arena.Arena, file_bytes: []const u8) TorrentError!Torrent {
    var result: Torrent = undefined;

    var top = bencode.decode(arena, file_bytes) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.MalformedBencode;
    };
    var top_entries: []bencode.Entry = undefined;
    switch (top) {
        .dict => |d| {
            top_entries = d;
        },
        else => return error.MalformedBencode,
    }

    // --- announce (required, bytes) ---
    if (findIndex(top_entries, "announce")) |ai| {
        switch (top_entries[ai].value) {
            .bytes => |b| {
                result.announce = b;
            },
            else => return error.MalformedBencode,
        }
    } else {
        return error.MissingField;
    }

    // --- info (required, dict) ---
    var info_entries: []bencode.Entry = undefined;
    if (findIndex(top_entries, "info")) |ii| {
        switch (top_entries[ii].value) {
            .dict => |d| {
                info_entries = d;
            },
            else => return error.MalformedBencode,
        }
    } else {
        return error.MissingField;
    }

    // --- name (required, bytes; pass through) ---
    if (findIndex(info_entries, "name")) |ni| {
        switch (info_entries[ni].value) {
            .bytes => |b| {
                result.name = b;
            },
            else => return error.MalformedBencode,
        }
    } else {
        return error.MissingField;
    }

    // Path safety for the single-file output name (spec §6): reject '/', '\',
    // a ".." component, or a leading '/'.
    if (result.name.len == 0) return error.BadFilePath;
    var ci: usize = 0;
    while (ci < result.name.len) : (ci += 1) {
        if (result.name[ci] == '/' or result.name[ci] == '\\') return error.BadFilePath;
    }
    ci = 0;
    while (ci + 1 < result.name.len) : (ci += 1) {
        if (result.name[ci] == '.' and result.name[ci + 1] == '.') return error.BadFilePath;
    }

    // --- piece length (required, int -> u32) ---
    if (findIndex(info_entries, "piece length")) |pli| {
        switch (info_entries[pli].value) {
            .int_val => |n| {
                if (n < MIN_PIECE_LENGTH or n > MAX_PIECE_LENGTH) return error.MalformedBencode;
                result.piece_length = @intCast(u32, n);
            },
            else => return error.MalformedBencode,
        }
    } else {
        return error.MissingField;
    }

    // --- length (required for single-file, int -> u64) ---
    if (findIndex(info_entries, "length")) |li| {
        switch (info_entries[li].value) {
            .int_val => |n| {
                if (n < 0) return error.MalformedBencode;
                result.total_length = @intCast(u64, n);
            },
            else => return error.MalformedBencode,
        }
    } else {
        return error.MissingField;
    }

    // --- announce-list (optional; list of lists of bytes; flattened) ---
    var ann_count: usize = 0;
    var ann_idx: ?usize = findIndex(top_entries, "announce-list");
    if (ann_idx) |ali| {
        switch (top_entries[ali].value) {
            .list => |tiers| {
                var ti: usize = 0;
                while (ti < tiers.len) : (ti += 1) {
                    switch (tiers[ti]) {
                        .list => |strs| {
                            ann_count += strs.len;
                        },
                        else => return error.MalformedBencode,
                    }
                }
            },
            else => return error.MalformedBencode,
        }
    }
    var raw_al = std.arena.alloc(arena, ann_count * @sizeOf([]const u8)) catch return error.OutOfMemory;
    var al: [][]const u8 = @ptrCast([*][]const u8, raw_al)[0..ann_count];
    var fill: usize = 0;
    if (ann_idx) |ali2| {
        switch (top_entries[ali2].value) {
            .list => |tiers| {
                var ti2: usize = 0;
                while (ti2 < tiers.len) : (ti2 += 1) {
                    switch (tiers[ti2]) {
                        .list => |strs| {
                            var si: usize = 0;
                            while (si < strs.len) : (si += 1) {
                                switch (strs[si]) {
                                    .bytes => |b| {
                                        al[fill] = b;
                                        fill += 1;
                                    },
                                    else => return error.MalformedBencode,
                                }
                            }
                        },
                        else => return error.MalformedBencode,
                    }
                }
            },
            else => return error.MalformedBencode,
        }
    }
    result.announce_list = al;

    // --- pieces (required, bytes; FLAT: 20 bytes per piece) ---
    // D2 workaround (spec §6 2026-10-08 amendment): `piece_hashes` is the raw
    // `pieces` bencode bytes, not a `[][20]u8`, because Z98 emits one shared C
    // slice typedef for nested slices (`[][]const u8` + `[][20]u8`) and would
    // mistype this field. Callers index `piece_hashes[i*20 .. i*20+20]`.
    var pieces_bytes: []const u8 = undefined;
    if (findIndex(info_entries, "pieces")) |qi| {
        switch (info_entries[qi].value) {
            .bytes => |b| {
                pieces_bytes = b;
            },
            else => return error.MalformedBencode,
        }
    } else {
        return error.MissingField;
    }
    if (pieces_bytes.len % HASH_LEN != 0) return error.BadPieceCount;
    result.piece_hashes = pieces_bytes;

    // --- piece-count consistency: 20 * ceil(total_length / piece_length) ---
    var expected: u64 = 0;
    if (result.total_length > 0) {
        var pl_u64: u64 = @intCast(u64, result.piece_length);
        expected = (result.total_length + pl_u64 - 1) / pl_u64;
    }
    if (expected > @intCast(u64, MAX_PIECES)) return error.TooLarge;
    var expected_bytes: usize = @intCast(usize, expected) * HASH_LEN;
    if (result.piece_hashes.len != expected_bytes) return error.BadPieceCount;

    // --- info_hash: SHA-1 over the EXACT info bytes (never re-encode) ---
    var info_span = bencode.dictValueSpan(file_bytes, "info") catch |se| {
        if (se == error.OutOfMemory) return error.OutOfMemory;
        return error.MalformedBencode;
    };
    if (info_span) |sp| {
        var hs = crypto.sha1Init();
        var ss: usize = @intCast(usize, sp.start);
        var ee: usize = @intCast(usize, sp.end);
        if (ee < ss or ee > file_bytes.len) return error.BadInfoHash;
        crypto.sha1Update(&hs, file_bytes[ss..ee]);
        crypto.sha1Final(&hs, &result.info_hash);
    } else {
        return error.MissingField;
    }

    return result;
}
