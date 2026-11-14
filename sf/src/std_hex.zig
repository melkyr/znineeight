// std_hex.zig — Z98 std lib L5: hexadecimal encode/decode.
//
// Contract (blueprint §3 L5): alloc output only | errors OutOfMemory,
// InvalidInput | coroutine no. Imports only L1 (`std_arena`) — never a sibling
// (`std_base64`) and never a higher layer (R3). `sf/src/std.zig` is NOT
// modified (Ruling F1: L5 modules are imported by path, not re-exported).
//
// Format: two hex characters per byte, high nybble first. `encodeLower` emits
// 0-9 a-f; `encodeUpper` emits 0-9 A-F; `decode` is case-insensitive.
//
//   encodeLower(arena, src) ![]u8
//   encodeUpper(arena, src) ![]u8
//   decode(arena, src) ![]u8
//
// `encodeLower`/`encodeUpper` allocate only their output and error only with
// `error.OutOfMemory`; `decode` allocates only its output and errors with
// `error.OutOfMemory` or `error.InvalidInput`.
//
// WHITESPACE / INVALID-INPUT POLICY (pinned by the fixtures): `decode` does not
// skip whitespace and accepts only an even-length string of hex digits. Any byte
// outside [0-9a-fA-F] (space, tab, CR, LF, ...) or an odd length makes the input
// invalid and `decode` returns `error.InvalidInput` (operator ruling m1842). An
// empty input is a VALID empty result (a length-0 slice, no error) and is
// distinct from an invalid one. An invalid decode allocates nothing (`used`
// unchanged).

const arena_mod = @import("std_arena.zig");

// One error set per module (R2). `decode` can fail on a bad arena request
// (OutOfMemory) or on malformed/whitespace input (InvalidInput).
const DecodeError = error{ OutOfMemory, InvalidInput };

fn hexVal(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return 0xFF;
}

fn hexLower(v: u8) u8 {
    if (v < 10) return '0' + v;
    return 'a' + (v - 10);
}

fn hexUpper(v: u8) u8 {
    if (v < 10) return '0' + v;
    return 'A' + (v - 10);
}

fn emptyOut(arena: *arena_mod.Arena) DecodeError![]u8 {
    var raw = try arena_mod.alloc(arena, 0);
    return raw[0..0];
}

pub fn encodeLower(arena: *arena_mod.Arena, src: []const u8) ![]u8 {
    var total: usize = src.len * 2;
    var raw = try arena_mod.alloc(arena, total);
    var out: []u8 = raw[0..total];
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        var b: u8 = src[i];
        out[i * 2] = hexLower(b >> 4);
        out[i * 2 + 1] = hexLower(b & 0x0F);
    }
    return out;
}

pub fn encodeUpper(arena: *arena_mod.Arena, src: []const u8) ![]u8 {
    var total: usize = src.len * 2;
    var raw = try arena_mod.alloc(arena, total);
    var out: []u8 = raw[0..total];
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        var b: u8 = src[i];
        out[i * 2] = hexUpper(b >> 4);
        out[i * 2 + 1] = hexUpper(b & 0x0F);
    }
    return out;
}

pub fn decode(arena: *arena_mod.Arena, src: []const u8) DecodeError![]u8 {
    if (src.len == 0) return emptyOut(arena);
    if (src.len % 2 != 0) return error.InvalidInput;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        if (hexVal(src[i]) == 0xFF) return error.InvalidInput;
    }
    var out_len: usize = src.len / 2;
    var raw = try arena_mod.alloc(arena, out_len);
    var out: []u8 = raw[0..out_len];
    i = 0;
    while (i < out_len) : (i += 1) {
        var hi: u8 = hexVal(src[i * 2]);
        var lo: u8 = hexVal(src[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
    return out;
}
