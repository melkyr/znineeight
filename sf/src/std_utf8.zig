// std_utf8.zig — Z98 std lib L5: UTF-8 code point iteration.
//
// Contract (blueprint §3 L5): alloc none | errors none | coroutine no. Pure
// (no imports at all). `sf/src/std.zig` is NOT modified (Ruling F1: L5 modules
// are imported by path, not re-exported; the core re-export set stays 12).
//
// Blueprint note: the blueprint writes decode's return as the anonymous struct
// `?struct { cp: u32, len: u8 }`. Z98 cannot write an anonymous struct type
// literally, so this module declares the equivalent named type
//   pub const Codepoint = struct { cp: u32, len: u8 };
// and `decode` returns `?Codepoint`. The field names, field order and layout
// are unchanged from the blueprint.
//
//   codepointLen(first_byte) u8   lead-byte sequence length 1..4, or 0 if the
//                                 byte can never begin a valid sequence
//   decode(s) ?Codepoint          the FIRST code point of s, or null if s is
//                                 empty / does not begin with valid UTF-8
//   encode(buf, cp) ?[]u8         the encoding written to buf[0..n], or null if
//                                 cp is not a scalar value or buf is too small
//   countCodepoints(s) usize      total walk: each valid code point counts 1;
//                                 a byte that begins an invalid sequence counts
//                                 1 and advances one byte
//
// VALIDATION POLICY (RFC 3629; pinned by the fixtures): a sequence is valid
// only if every continuation byte is in 0x80..0xBF, the code point is not
// overlong (2-byte >= 0x80, 3-byte >= 0x800, 4-byte >= 0x10000), is not a
// UTF-16 surrogate (U+D800..U+DFFF), and is not above U+10FFFF. Lead bytes
// 0x80..0xBF, 0xC0, 0xC1 and 0xF5..0xFF are invalid. A truncated sequence is
// invalid. `decode` validates before returning, so it never yields a value
// outside the Unicode scalar range.
//
// `codepointLen` consults only the lead byte; the second-byte constraints
// (overlong E0/F0, surrogate ED, >U+10FFFF F4) are enforced by `decode`.
// `encode` rejects surrogates and code points above U+10FFFF, and refuses a
// buffer smaller than the encoding rather than writing a partial sequence.
//
// Determinism (R6): all four functions are pure functions of their arguments —
// no address, clock, or PID input.

pub const Codepoint = struct {
    cp: u32,
    len: u8,
};

pub fn codepointLen(first_byte: u8) u8 {
    if (first_byte < 0x80) return 1;
    if (first_byte >= 0xC2 and first_byte <= 0xDF) return 2;
    if (first_byte >= 0xE0 and first_byte <= 0xEF) return 3;
    if (first_byte >= 0xF0 and first_byte <= 0xF4) return 4;
    return 0;
}

pub fn decode(s: []const u8) ?Codepoint {
    if (s.len == 0) return null;
    var n: u8 = codepointLen(s[0]);
    if (n == 0) return null;
    var need: usize = @intCast(usize, n);
    if (s.len < need) return null;

    var i: usize = 1;
    while (i < need) : (i += 1) {
        if (s[i] < 0x80 or s[i] > 0xBF) return null;
    }

    var cp: u32 = 0;
    if (n == 1) {
        cp = @intCast(u32, s[0]);
    } else if (n == 2) {
        var b0: u32 = @intCast(u32, s[0] & 0x1F);
        var b1: u32 = @intCast(u32, s[1] & 0x3F);
        cp = (b0 << 6) | b1;
        if (cp < 0x80) return null;
    } else if (n == 3) {
        var b0: u32 = @intCast(u32, s[0] & 0x0F);
        var b1: u32 = @intCast(u32, s[1] & 0x3F);
        var b2: u32 = @intCast(u32, s[2] & 0x3F);
        cp = (b0 << 12) | (b1 << 6) | b2;
        if (cp < 0x800) return null;
        if (cp >= 0xD800 and cp <= 0xDFFF) return null;
    } else {
        var b0: u32 = @intCast(u32, s[0] & 0x07);
        var b1: u32 = @intCast(u32, s[1] & 0x3F);
        var b2: u32 = @intCast(u32, s[2] & 0x3F);
        var b3: u32 = @intCast(u32, s[3] & 0x3F);
        cp = (b0 << 18) | (b1 << 12) | (b2 << 6) | b3;
        if (cp < 0x10000) return null;
        if (cp > 0x10FFFF) return null;
    }
    return Codepoint{ .cp = cp, .len = n };
}

pub fn encode(buf: []u8, cp: u32) ?[]u8 {
    if (cp > 0x10FFFF) return null;
    if (cp >= 0xD800 and cp <= 0xDFFF) return null;

    var n: usize = 0;
    if (cp < 0x80) {
        n = 1;
    } else if (cp < 0x800) {
        n = 2;
    } else if (cp < 0x10000) {
        n = 3;
    } else {
        n = 4;
    }
    if (buf.len < n) return null;

    if (n == 1) {
        buf[0] = @intCast(u8, cp);
    } else if (n == 2) {
        buf[0] = @intCast(u8, 0xC0 | (cp >> 6));
        buf[1] = @intCast(u8, 0x80 | (cp & 0x3F));
    } else if (n == 3) {
        buf[0] = @intCast(u8, 0xE0 | (cp >> 12));
        buf[1] = @intCast(u8, 0x80 | ((cp >> 6) & 0x3F));
        buf[2] = @intCast(u8, 0x80 | (cp & 0x3F));
    } else {
        buf[0] = @intCast(u8, 0xF0 | (cp >> 18));
        buf[1] = @intCast(u8, 0x80 | ((cp >> 12) & 0x3F));
        buf[2] = @intCast(u8, 0x80 | ((cp >> 6) & 0x3F));
        buf[3] = @intCast(u8, 0x80 | (cp & 0x3F));
    }
    return buf[0..n];
}

pub fn countCodepoints(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        var d = decode(s[i..]);
        if (d) |c| {
            i += @intCast(usize, c.len);
        } else {
            i += 1;
        }
        n += 1;
    }
    return n;
}
