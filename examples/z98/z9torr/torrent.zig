// torrent.zig — z9torr: parse a single-file .torrent into `Torrent`.
//
// Consumes `std_bencode` (decode + dictValueSpan) and `std_crypto` (SHA-1).
// `info_hash` is SHA-1 over the EXACT `info` dictionary bytes from the input
// file (never re-encoded): `dictValueSpan` yields the raw span.
//
// Single-file only (spec 2026-10-08 §1/§6): `info.length` is required and
// `info.files` is rejected implicitly (absent `length` -> MissingField).
//
// Z98 compiler defect D2 (see examples/torrent_example_defects.md): a slice
// `[]T` is only safe when `T` is primitive or a *named* type. This module has
// no `[]`-of-synthetic type: `announce_list` is the fixed `[8][]const u8`
// (with `announce_count`) and `piece_hashes` is flat `[]const u8`.

const std = @import("std");
const bencode = @import("std_bencode");
const crypto = @import("std_crypto");

pub const Torrent = struct {
    announce: []const u8,
    announce_list: [8][]const u8,
    announce_count: u32,
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

// D2 workaround: the announce list is a fixed `[N][]const u8` (array of
// primitive slices), never a `[]synthetic` slice (see torrent_example_defects.md
// D2). Extra tiers/URLs beyond the cap are dropped.
const MAX_ANNOUNCE_LIST: usize = 8;

// .torrent metadata cap (arena-bound). The DOWNLOADED payload is unbounded
// (`total_length`, streamed to disk); only the metadata file is capped.
pub const MAX_TORRENT_BYTES: usize = 3145728; // 3 MiB

const HASH_LEN: usize = 20;

// Piece-count cap consistent with the metadata cap above.
const MAX_PIECES: usize = MAX_TORRENT_BYTES / HASH_LEN;

// Windows MAX_PATH (260) and the per-component limit (255). `result.name` has
// no path separators (validated below), so it is a single component; the
// tighter component bound is the binding one.
const MAX_PATH: usize = 260;
const MAX_COMPONENT: usize = 255;

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn lowerAscii(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn eqBytesIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (lowerAscii(a[i]) != lowerAscii(b[i])) return false;
    }
    return true;
}

fn isDigit1to9(c: u8) bool {
    return c >= '1' and c <= '9';
}

// Win9x reserved DOS device names (case-insensitive), with or without an
// extension: CON, PRN, AUX, NUL, COM1..COM9, LPT1..LPT9. Only the stem before
// the first '.' is examined, so "NUL.txt" is reserved and "NULlog.txt" is not.
fn isReservedDeviceName(name: []const u8) bool {
    var stem_len: usize = name.len;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        if (name[i] == '.') {
            stem_len = i;
            break;
        }
    }
    var stem: []const u8 = name[0..stem_len];
    var c_con: []const u8 = "CON";
    var c_prn: []const u8 = "PRN";
    var c_aux: []const u8 = "AUX";
    var c_nul: []const u8 = "NUL";
    if (eqBytesIgnoreCase(stem, c_con)) return true;
    if (eqBytesIgnoreCase(stem, c_prn)) return true;
    if (eqBytesIgnoreCase(stem, c_aux)) return true;
    if (eqBytesIgnoreCase(stem, c_nul)) return true;
    if (stem.len == 4) {
        var c_com: []const u8 = "COM";
        var c_lpt: []const u8 = "LPT";
        if (eqBytesIgnoreCase(stem[0..3], c_com) and isDigit1to9(stem[3])) return true;
        if (eqBytesIgnoreCase(stem[0..3], c_lpt) and isDigit1to9(stem[3])) return true;
    }
    return false;
}

fn findIndex(entries: []bencode.Entry, key: []const u8) ?usize {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eqBytes(entries[i].key, key)) return i;
    }
    return null;
}

pub fn load(arena: *std.arena.Arena, file_bytes: []const u8) TorrentError!Torrent {
    if (file_bytes.len > MAX_TORRENT_BYTES) return error.TooLarge;

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
    // Windows path limits + reserved device names (plan Task 3 / spec §12).
    // The output path is `result.name` itself (disk.openTarget opens it
    // relative to cwd), so bounding the name bounds the derived path. Reject
    // here, before disk.openTarget, so the failure is the typed name error
    // (exit 2), not a delegated Win9x CreateFileA failure (exit 5).
    if (result.name.len > MAX_PATH) return error.BadFilePath;
    if (result.name.len > MAX_COMPONENT) return error.BadFilePath;
    if (isReservedDeviceName(result.name)) return error.BadFilePath;

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

    // --- announce-list (optional; fixed `[N][]const u8`, D2-safe) ---
    // Z98 D2: never `[]` a synthetic type. `[8][]const u8` is an array of
    // primitive slices (the array branch recurses correctly in c89_emit).
    var fi: usize = 0;
    while (fi < MAX_ANNOUNCE_LIST) : (fi += 1) {
        result.announce_list[fi] = "";
    }
    var fill: usize = 0;
    if (findIndex(top_entries, "announce-list")) |ali| {
        switch (top_entries[ali].value) {
            .list => |tiers| {
                var ti: usize = 0;
                while (ti < tiers.len) : (ti += 1) {
                    switch (tiers[ti]) {
                        .list => |strs| {
                            var si: usize = 0;
                            while (si < strs.len) : (si += 1) {
                                switch (strs[si]) {
                                    .bytes => |b| {
                                        if (fill < MAX_ANNOUNCE_LIST) {
                                            result.announce_list[fill] = b;
                                            fill += 1;
                                        }
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
    result.announce_count = @intCast(u32, fill);

    // --- pieces (required, bytes; FLAT: 20 bytes per piece) ---
    // D2 workaround (spec §6 2026-10-08 amendment): `piece_hashes` is the raw
    // `pieces` bencode bytes, not a `[][20]u8`, because Z98 emits one shared C
    // slice typedef for `[]`-of-synthetic types and would mistype this field.
    // Callers index `piece_hashes[i*20 .. i*20+20]`.
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
