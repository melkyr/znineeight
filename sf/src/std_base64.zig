// std_base64.zig — Z98 std lib L5: RFC 4648 base64 encode/decode.
//
// Contract (blueprint §3 L5): alloc output only | errors OutOfMemory |
// coroutine no. Imports only L1 (`std_arena`) — never a sibling (`std_hex`) and
// never a higher layer (R3). `sf/src/std.zig` is NOT modified (Ruling F1: L5
// modules are imported by path, not re-exported).
//
// Format: RFC 4648 §4 standard base64 — alphabet
//   ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
// with mandatory '=' padding out to a multiple of 4 output characters.
//
//   encode(arena, src) ![]u8   the base64 text (no whitespace emitted)
//   decode(arena, src) ![]u8   the decoded bytes
//   encodedLen(n) usize        exact encoded size: 4 * ceil(n / 3)
//   decodedLen(n) usize        max decoded size: (n / 4) * 3 (upper bound)
//
// `encodedLen`/`decodedLen` allocate nothing (R1). `encode`/`decode` allocate
// only the output; their error set is exactly `error.OutOfMemory`.
//
// WHITESPACE / VALIDITY POLICY (pinned by the fixtures): `decode` does not skip
// whitespace and accepts only canonical padded base64. Any byte outside the
// alphabet (space, tab, CR, LF, ...), a length that is not a multiple of 4, or
// misplaced/malformed '=' makes the input invalid. Because the contract fixes
// the error set to exactly `error.OutOfMemory`, invalid input is signalled by
// an empty output slice (length 0), not by an error; a well-formed empty input
// also yields length 0. An invalid decode allocates nothing (`used` unchanged).
//
// `decodedLen(n)` is an upper bound because the exact decoded length depends on
// trailing padding, which a length alone cannot reveal; it equals (n / 4) * 3,
// matching the Zig std decoder sizing convention (calcSizeForSlice).

const arena_mod = @import("std_arena.zig");

fn b64Val(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c - 'A';
    if (c >= 'a' and c <= 'z') return c - 'a' + 26;
    if (c >= '0' and c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return 0xFF;
}

fn emptyOut(arena: *arena_mod.Arena) ![]u8 {
    var raw = try arena_mod.alloc(arena, 0);
    return raw[0..0];
}

pub fn encodedLen(n: usize) usize {
    var q: usize = n / 3;
    var r: usize = n % 3;
    if (r == 0) return q * 4;
    return q * 4 + 4;
}

pub fn decodedLen(n: usize) usize {
    return (n / 4) * 3;
}

pub fn encode(arena: *arena_mod.Arena, src: []const u8) ![]u8 {
    var alphabet: []const u8 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var total: usize = encodedLen(src.len);
    var raw = try arena_mod.alloc(arena, total);
    var out: []u8 = raw[0..total];
    var i: usize = 0;
    var op: usize = 0;
    while (i + 3 <= src.len) : (i += 3) {
        var b0: u32 = @intCast(u32, src[i]);
        var b1: u32 = @intCast(u32, src[i + 1]);
        var b2: u32 = @intCast(u32, src[i + 2]);
        var n: u32 = (b0 << 16) | (b1 << 8) | b2;
        out[op] = alphabet[@intCast(usize, (n >> 18) & 63)];
        out[op + 1] = alphabet[@intCast(usize, (n >> 12) & 63)];
        out[op + 2] = alphabet[@intCast(usize, (n >> 6) & 63)];
        out[op + 3] = alphabet[@intCast(usize, n & 63)];
        op += 4;
    }
    var rem: usize = src.len - i;
    if (rem == 1) {
        var b0: u32 = @intCast(u32, src[i]);
        var n: u32 = b0 << 16;
        out[op] = alphabet[@intCast(usize, (n >> 18) & 63)];
        out[op + 1] = alphabet[@intCast(usize, (n >> 12) & 63)];
        out[op + 2] = '=';
        out[op + 3] = '=';
    } else if (rem == 2) {
        var b0: u32 = @intCast(u32, src[i]);
        var b1: u32 = @intCast(u32, src[i + 1]);
        var n: u32 = (b0 << 16) | (b1 << 8);
        out[op] = alphabet[@intCast(usize, (n >> 18) & 63)];
        out[op + 1] = alphabet[@intCast(usize, (n >> 12) & 63)];
        out[op + 2] = alphabet[@intCast(usize, (n >> 6) & 63)];
        out[op + 3] = '=';
    }
    return out;
}

pub fn decode(arena: *arena_mod.Arena, src: []const u8) ![]u8 {
    if (src.len == 0) return emptyOut(arena);
    if (src.len % 4 != 0) return emptyOut(arena);

    var pad: usize = 0;
    var i: usize = 0;
    while (i < src.len) : (i += 4) {
        var c0: u8 = src[i];
        var c1: u8 = src[i + 1];
        if (b64Val(c0) == 0xFF) return emptyOut(arena);
        if (b64Val(c1) == 0xFF) return emptyOut(arena);
        var c2: u8 = src[i + 2];
        var c3: u8 = src[i + 3];
        var is_last: bool = (i + 4 == src.len);
        if (c2 == '=') {
            if (c3 != '=') return emptyOut(arena);
            if (!is_last) return emptyOut(arena);
            pad += 2;
        } else {
            if (b64Val(c2) == 0xFF) return emptyOut(arena);
            if (c3 == '=') {
                if (!is_last) return emptyOut(arena);
                pad += 1;
            } else if (b64Val(c3) == 0xFF) {
                return emptyOut(arena);
            }
        }
    }

    var out_len: usize = (src.len / 4) * 3 - pad;
    var raw = try arena_mod.alloc(arena, out_len);
    var out: []u8 = raw[0..out_len];
    var op: usize = 0;
    i = 0;
    while (i < src.len) : (i += 4) {
        var v0: u32 = @intCast(u32, b64Val(src[i]));
        var v1: u32 = @intCast(u32, b64Val(src[i + 1]));
        var c2: u8 = src[i + 2];
        var c3: u8 = src[i + 3];
        var v2: u32 = 0;
        var v3: u32 = 0;
        if (c2 != '=') v2 = @intCast(u32, b64Val(c2));
        if (c3 != '=') v3 = @intCast(u32, b64Val(c3));
        var triple: u32 = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3;
        if (op < out_len) {
            out[op] = @intCast(u8, (triple >> 16) & 0xFF);
            op += 1;
        }
        if (op < out_len) {
            out[op] = @intCast(u8, (triple >> 8) & 0xFF);
            op += 1;
        }
        if (op < out_len) {
            out[op] = @intCast(u8, triple & 0xFF);
            op += 1;
        }
    }
    return out;
}
