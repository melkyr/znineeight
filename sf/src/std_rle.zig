// std_rle.zig — Z98 std lib L4: byte-oriented run-length encoding (QOI-style).
//
// Contract (blueprint §3 L4): alloc output only | errors OutOfMemory |
// coroutine no. Imports only L1 (`std_arena`) — never a sibling (`std_map`/
// `std_sort`/`std_heap`) and never a higher layer (R3). `sf/src/std.zig` is NOT
// modified (Ruling F1: L4 modules are imported by path, not re-exported).
//
// Wire format (deterministic, R6). A stream is a 4-byte little-endian u32
// decoded-length prefix followed by a sequence of tokens:
//
//   literal    one byte `b` with b < 0x80               emits b
//   run        control `0x80 | (n - 1)`, then value `v`  emits v, n times
//              where 1 <= n <= 128
//
// The control byte's high bit disambiguates literals from runs, so a value with
// the high bit set is never emitted as a literal. A maximal run of `n` equal
// bytes with value `v` is encoded as a single literal when n == 1 and v < 0x80,
// and otherwise as one or more run tokens covering at most 128 bytes each (a
// 129-run is `0xFF v` + `0x80 v`). The rule is a pure function of the input.
//
//   encode(arena, src) ![]u8     length prefix + tokens
//   decode(arena, src) ![]u8     the decoded bytes (prefix value)
//   encodedLen(src) usize        exact encoded size (prefix + tokens)
//   decodedLen(src) usize        the prefix value; 0 when src.len < 4
//
// `encodedLen`/`decodedLen` allocate nothing (R1). `encode`/`decode` allocate
// only the output; their error set is exactly `error.OutOfMemory`. `decode`
// trusts a well-formed stream: a truncated stream yields a zero-filled tail and
// an overlong run is clamped to the declared length (never reads out of bounds).

const arena_mod = @import("std_arena.zig");

const PREFIX: usize = 4;
const RUN_TAG: u8 = 0x80;
const MAX_RUN: usize = 128;

fn runToken(n: usize) u8 {
    return RUN_TAG | @intCast(u8, n - 1);
}

fn putU32LE(dst: []u8, v: u32) void {
    dst[0] = @intCast(u8, v & 0xFF);
    dst[1] = @intCast(u8, (v >> 8) & 0xFF);
    dst[2] = @intCast(u8, (v >> 16) & 0xFF);
    dst[3] = @intCast(u8, (v >> 24) & 0xFF);
}

fn getU32LE(src: []const u8) u32 {
    return @intCast(u32, src[0]) |
        (@intCast(u32, src[1]) << 8) |
        (@intCast(u32, src[2]) << 16) |
        (@intCast(u32, src[3]) << 24);
}

pub fn encodedLen(src: []const u8) usize {
    var total: usize = PREFIX;
    var i: usize = 0;
    while (i < src.len) {
        var v: u8 = src[i];
        var n: usize = 1;
        i += 1;
        while (i < src.len and src[i] == v) : (i += 1) {
            n += 1;
        }
        if (n == 1 and v < RUN_TAG) {
            total += 1;
        } else {
            total += 2 * ((n + MAX_RUN - 1) / MAX_RUN);
        }
    }
    return total;
}

pub fn decodedLen(src: []const u8) usize {
    if (src.len < PREFIX) return 0;
    return @intCast(usize, getU32LE(src));
}

pub fn encode(arena: *arena_mod.Arena, src: []const u8) ![]u8 {
    var total: usize = encodedLen(src);
    var raw = try arena_mod.alloc(arena, total);
    var out: []u8 = raw[0..total];
    putU32LE(out, @intCast(u32, src.len));
    var pos: usize = PREFIX;
    var i: usize = 0;
    while (i < src.len) {
        var v: u8 = src[i];
        var n: usize = 1;
        i += 1;
        while (i < src.len and src[i] == v) : (i += 1) {
            n += 1;
        }
        if (n == 1 and v < RUN_TAG) {
            out[pos] = v;
            pos += 1;
        } else {
            var rem: usize = n;
            while (rem > 0) {
                var chunk: usize = rem;
                if (chunk > MAX_RUN) chunk = MAX_RUN;
                out[pos] = runToken(chunk);
                out[pos + 1] = v;
                pos += 2;
                rem -= chunk;
            }
        }
    }
    return out;
}

pub fn decode(arena: *arena_mod.Arena, src: []const u8) ![]u8 {
    var n: usize = decodedLen(src);
    var raw = try arena_mod.alloc(arena, n);
    var out: []u8 = raw[0..n];
    var z: usize = 0;
    while (z < n) : (z += 1) {
        out[z] = 0;
    }
    if (src.len < PREFIX) return out;
    var ip: usize = PREFIX;
    var op: usize = 0;
    while (ip < src.len and op < n) {
        var c: u8 = src[ip];
        ip += 1;
        if (c < RUN_TAG) {
            out[op] = c;
            op += 1;
        } else {
            if (ip >= src.len) break;
            var v: u8 = src[ip];
            ip += 1;
            var count: usize = @intCast(usize, c & 0x7F) + 1;
            while (count > 0 and op < n) : (count -= 1) {
                out[op] = v;
                op += 1;
            }
        }
    }
    return out;
}
