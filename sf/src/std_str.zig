// std_str.zig — Z98 std lib L2: string slice operations. Extends the original
// pure byte-string helpers (len/eql/copy/copyZ/findChar/startsWith/endsWith/
// toUpper/toLower) with the blueprint §3 L2 additions. Slices only; no
// null-termination anywhere. The allocating functions (`split`, `splitLines`,
// `join`, `replace`, `repeat`) take an arena and return `OutOfMemory` only.
// `std_str` is L2 and imports only `std_arena` (L0); it never imports an L2
// sibling. `split` returns slices into `s` (only the outer array allocates);
// `replace` allocates the result only and reads `s` without mutating it, so
// `from`/`to` may alias `s`. `trim` strips ASCII whitespace.
const arena_mod = @import("std_arena.zig");

pub fn len(s: []const u8) usize {
    return s.len;
}

pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub fn copy(dst: []u8, src: []const u8) void {
    if (src.len > dst.len) return;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[i] = src[i];
    }
}

pub fn copyZ(dst: [*]u8, src: []const u8) usize {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[i] = src[i];
    }
    dst[src.len] = 0;
    return src.len;
}

pub fn findChar(s: []const u8, c: u8) ?usize {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == c) return i;
    }
    return null;
}

pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    if (prefix.len > s.len) return false;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        if (s[i] != prefix[i]) return false;
    }
    return true;
}

pub fn endsWith(s: []const u8, suffix: []const u8) bool {
    if (suffix.len > s.len) return false;
    var off: usize = s.len - suffix.len;
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        if (s[off + i] != suffix[i]) return false;
    }
    return true;
}

pub fn toUpper(s: []u8) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] >= 'a' and s[i] <= 'z') {
            s[i] = s[i] - @intCast(u8, 32);
        }
    }
}

pub fn toLower(s: []u8) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] >= 'A' and s[i] <= 'Z') {
            s[i] = s[i] + @intCast(u8, 32);
        }
    }
}

// ---- private helpers -------------------------------------------------------

// Does `needle` occur in `s` starting at `at`? Caller guarantees at+needle.len <= s.len.
fn matchAt(s: []const u8, at: usize, needle: []const u8) bool {
    var j: usize = 0;
    while (j < needle.len) : (j += 1) {
        if (s[at + j] != needle[j]) return false;
    }
    return true;
}

fn lowerAscii(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + @intCast(u8, 32);
    return c;
}

// ASCII whitespace: 0x09..0x0D (TAB/LF/VT/FF/CR) plus 0x20 (SPACE). Z98 has no
// \v/\f escapes, so VT/FF are written as the byte values 11/12.
fn isSpace(c: u8) bool {
    if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 11 or c == 12) return true;
    return false;
}

fn inSet(chars: []const u8, c: u8) bool {
    var i: usize = 0;
    while (i < chars.len) : (i += 1) {
        if (chars[i] == c) return true;
    }
    return false;
}

fn copyInto(dst: []u8, off: usize, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[off + i] = src[i];
    }
}

// ---- blueprint §3 L2 additions --------------------------------------------

// Split `s` on the byte `sep`. Returns slices INTO `s`; only the outer array is
// allocated. A trailing separator yields a trailing empty segment and an empty
// `s` yields exactly one empty segment.
pub fn split(arena: *arena_mod.Arena, s: []const u8, sep: u8) ![][]const u8 {
    var n: usize = 1;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == sep) n += 1;
    }
    var raw = try arena_mod.alloc(arena, n * @sizeOf([]const u8));
    var p: [*][]const u8 = @ptrCast([*][]const u8, raw);
    var start: usize = 0;
    var idx: usize = 0;
    i = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == sep) {
            p[idx] = s[start..i];
            idx += 1;
            start = i + 1;
        }
    }
    p[idx] = s[start..s.len];
    return p[0..n];
}

// Split `s` on '\n' (CRLF-aware: a single trailing '\r' is stripped from each
// segment). Returns slices into `s`; only the outer array is allocated.
pub fn splitLines(arena: *arena_mod.Arena, s: []const u8) ![][]const u8 {
    var n: usize = 1;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\n') n += 1;
    }
    var raw = try arena_mod.alloc(arena, n * @sizeOf([]const u8));
    var p: [*][]const u8 = @ptrCast([*][]const u8, raw);
    var start: usize = 0;
    var idx: usize = 0;
    i = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\n') {
            var e: usize = i;
            if (e > start and s[e - 1] == '\r') e -= 1;
            p[idx] = s[start..e];
            idx += 1;
            start = i + 1;
        }
    }
    var e2: usize = s.len;
    if (e2 > start and s[e2 - 1] == '\r') e2 -= 1;
    p[idx] = s[start..e2];
    return p[0..n];
}

// Concatenate `parts` with `sep` between consecutive parts; allocates the result.
pub fn join(arena: *arena_mod.Arena, parts: [][]const u8, sep: []const u8) ![]u8 {
    var total: usize = 0;
    var i: usize = 0;
    while (i < parts.len) : (i += 1) {
        total += parts[i].len;
        if (i + 1 < parts.len) total += sep.len;
    }
    var raw = try arena_mod.alloc(arena, total);
    var out: []u8 = raw[0..total];
    var pos: usize = 0;
    i = 0;
    while (i < parts.len) : (i += 1) {
        copyInto(out, pos, parts[i]);
        pos += parts[i].len;
        if (i + 1 < parts.len) {
            copyInto(out, pos, sep);
            pos += sep.len;
        }
    }
    return out;
}

// Strip ASCII whitespace from both ends; returns a view into `s`.
pub fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and isSpace(s[start])) start += 1;
    while (end > start and isSpace(s[end - 1])) end -= 1;
    return s[start..end];
}

// Strip any leading byte present in the `chars` set; returns a view into `s`.
pub fn trimLeft(s: []const u8, chars: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and inSet(chars, s[start])) start += 1;
    return s[start..s.len];
}

// Strip any trailing byte present in the `chars` set; returns a view into `s`.
pub fn trimRight(s: []const u8, chars: []const u8) []const u8 {
    var end: usize = s.len;
    while (end > 0 and inSet(chars, s[end - 1])) end -= 1;
    return s[0..end];
}

// First index of `needle` in `s`, or null. Empty needle matches at 0.
pub fn indexOf(s: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > s.len) return null;
    var i: usize = 0;
    while (i + needle.len <= s.len) : (i += 1) {
        if (matchAt(s, i, needle)) return i;
    }
    return null;
}

// Last index of `needle` in `s`, or null. Empty needle matches at s.len.
pub fn lastIndexOf(s: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return s.len;
    if (needle.len > s.len) return null;
    var i: usize = s.len - needle.len + 1;
    while (i > 0) {
        i -= 1;
        if (matchAt(s, i, needle)) return i;
    }
    return null;
}

// ASCII case-insensitive equality; non-alphabetic bytes must match exactly.
pub fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (lowerAscii(a[i]) != lowerAscii(b[i])) return false;
    }
    return true;
}

// Replace every non-overlapping occurrence of `from` with `to`; allocates the
// result only. Empty `from` is a no-op copy. `from`/`to` may alias `s`.
pub fn replace(arena: *arena_mod.Arena, s: []const u8, from: []const u8, to: []const u8) ![]u8 {
    if (from.len == 0) {
        var raw0 = try arena_mod.alloc(arena, s.len);
        var out0: []u8 = raw0[0..s.len];
        copyInto(out0, 0, s);
        return out0;
    }
    var n: usize = 0;
    var i: usize = 0;
    while (i + from.len <= s.len) {
        if (matchAt(s, i, from)) {
            n += 1;
            i += from.len;
        } else {
            i += 1;
        }
    }
    var new_len: usize = s.len - n * from.len + n * to.len;
    var raw = try arena_mod.alloc(arena, new_len);
    var out: []u8 = raw[0..new_len];
    var pos: usize = 0;
    i = 0;
    while (i < s.len) {
        if (i + from.len <= s.len and matchAt(s, i, from)) {
            copyInto(out, pos, to);
            pos += to.len;
            i += from.len;
        } else {
            out[pos] = s[i];
            pos += 1;
            i += 1;
        }
    }
    return out;
}

// Count occurrences of the byte `needle` in `s`.
pub fn count(s: []const u8, needle: u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == needle) n += 1;
    }
    return n;
}

// Concatenate `s` with itself `n` times; allocates the result.
pub fn repeat(arena: *arena_mod.Arena, s: []const u8, n: usize) ![]u8 {
    var total: usize = s.len * n;
    var raw = try arena_mod.alloc(arena, total);
    var out: []u8 = raw[0..total];
    var k: usize = 0;
    while (k < n) : (k += 1) {
        copyInto(out, k * s.len, s);
    }
    return out;
}
