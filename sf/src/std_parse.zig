// std_parse.zig — Z98 std lib L5: number parsing and formatting.
//
// Contract (blueprint §3 L5): alloc none | errors none | coroutine no. Pure
// (no imports at all). Parsing rejects whitespace, '+', and underscores; null
// on overflow or malformed. itoa/utoa/itoa64/utoa64/ftoa write backwards from
// buf's end; the returned slice points into buf.
//
// Overflow detection is done in u64 before narrowing, so a malformed/oversized
// input returns null instead of trapping under -fsafe. Float formatting avoids
// any f64->int conversion (unsupported here): digits are extracted by
// comparison and placed into a temporary buffer, which is then copied into the
// tail of buf.
//
// ftoa contract (L5):
//   * Fixed-point notation, round half up, `precision` fraction digits clamped
//     to 17. No exponent notation.
//   * Non-finite input is total: NaN -> "nan", +inf -> "inf", -inf -> "-inf".
//     It never hangs or traps.
//   * Buffer precondition: `buf` must hold the rendered text (sign + integer
//     digits + optional '.' + precision). If it does not, ftoa writes nothing
//     and returns buf[0..0]; size buf >= 1 + 309 + 1 + 17 = 328 bytes to cover
//     every finite f64. The same empty result is returned for any value that
//     cannot be represented in the fixed ftoa temps.

const MAX_I32_MAG: u64 = 2147483647;
const MAX_I32_NEG_MAG: u64 = 2147483648;
const MAX_U32: u64 = 4294967295;
const MAX_I64_MAG: u64 = @intCast(u64, 0x7FFFFFFFFFFFFFFF);
const MAX_I64_NEG_MAG: u64 = @intCast(u64, 0x8000000000000000);
const MAX_U64: u64 = @intCast(u64, 0xFFFFFFFFFFFFFFFF);

// ftoa working size. The largest finite f64 (~1.7977e308) has 309 integer
// digits; precision is clamped to 17, so a rendered value is at most
// 1 (sign) + 309 + 1 ('.') + 17 = 328 bytes. 352 gives headroom and is used for
// both the digit scratch and the output temp, so no finite input can overrun.
const FTOA_TMP = 352;

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

pub fn parseInt(s: []const u8) ?i32 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var neg: bool = false;
    if (s[0] == '-') {
        neg = true;
        i = 1;
        if (s.len == 1) return null;
    }
    var lim: u64 = MAX_I32_MAG;
    if (neg) lim = MAX_I32_NEG_MAG;
    var acc: u64 = 0;
    while (i < s.len) : (i += 1) {
        var c = s[i];
        if (c < '0' or c > '9') return null;
        var d: u64 = @intCast(u64, c - '0');
        if (acc > lim / 10) return null;
        if (acc == lim / 10 and d > lim % 10) return null;
        acc = acc * 10 + d;
    }
    var m: i64 = @intCast(i64, acc);
    if (neg) m = -m;
    return @intCast(i32, m);
}

pub fn parseUint(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var acc: u64 = 0;
    while (i < s.len) : (i += 1) {
        var c = s[i];
        if (c < '0' or c > '9') return null;
        var d: u64 = @intCast(u64, c - '0');
        if (acc > MAX_U32 / 10) return null;
        if (acc == MAX_U32 / 10 and d > MAX_U32 % 10) return null;
        acc = acc * 10 + d;
    }
    return @intCast(u32, acc);
}

pub fn parseInt64(s: []const u8) ?i64 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var neg: bool = false;
    if (s[0] == '-') {
        neg = true;
        i = 1;
        if (s.len == 1) return null;
    }
    var lim: u64 = MAX_I64_MAG;
    if (neg) lim = MAX_I64_NEG_MAG;
    var acc: u64 = 0;
    while (i < s.len) : (i += 1) {
        var c = s[i];
        if (c < '0' or c > '9') return null;
        var d: u64 = @intCast(u64, c - '0');
        if (acc > lim / 10) return null;
        if (acc == lim / 10 and d > lim % 10) return null;
        acc = acc * 10 + d;
    }
    if (neg) {
        var bits: u64 = (~acc) +% 1;
        return @bitCast(i64, bits);
    }
    return @intCast(i64, acc);
}

pub fn parseUint64(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var acc: u64 = 0;
    while (i < s.len) : (i += 1) {
        var c = s[i];
        if (c < '0' or c > '9') return null;
        var d: u64 = @intCast(u64, c - '0');
        if (acc > MAX_U64 / 10) return null;
        if (acc == MAX_U64 / 10 and d > MAX_U64 % 10) return null;
        acc = acc * 10 + d;
    }
    return acc;
}

pub fn parseFloat(s: []const u8) ?f64 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var neg: bool = false;
    if (s[0] == '-') {
        neg = true;
        i = 1;
        if (s.len == 1) return null;
    }
    var seen: bool = false;
    var value: f64 = 0.0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
        seen = true;
        value = value * 10.0 + @intToFloat(f64, @intCast(i32, s[i] - '0'));
    }
    if (i < s.len and s[i] == '.') {
        i += 1;
        var scale: f64 = 1.0;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
            seen = true;
            scale = scale * 10.0;
            value = value + @intToFloat(f64, @intCast(i32, s[i] - '0')) / scale;
        }
    }
    if (!seen) return null;
    if (i != s.len) return null;
    // Overflow to +/-inf: finite non-zero x has x*2 != x. (No f64 max literal:
    // the emitter rounds f64 literals to ~6 significant digits.)
    if (value != 0.0 and value * 2.0 == value) return null;
    if (neg) return -value;
    return value;
}

// ---------------------------------------------------------------------------
// Formatting (results placed at buf's end; returned slice points into buf)
// ---------------------------------------------------------------------------

fn digitChar(d: u32) u8 {
    return @intCast(u8, @intCast(u32, '0') + d);
}

pub fn itoa(buf: []u8, v: i32) []u8 {
    var x: i64 = @intCast(i64, v);
    var neg: bool = false;
    if (x < 0) {
        neg = true;
        x = -x;
    }
    var idx: usize = buf.len;
    if (x == 0) {
        idx -= 1;
        buf[idx] = '0';
    } else {
        while (x > 0) {
            var d: u32 = @intCast(u32, x % 10);
            idx -= 1;
            buf[idx] = digitChar(d);
            x = x / 10;
        }
    }
    if (neg) {
        idx -= 1;
        buf[idx] = '-';
    }
    return buf[idx..];
}

pub fn utoa(buf: []u8, v: u32) []u8 {
    var x: u32 = v;
    var idx: usize = buf.len;
    if (x == 0) {
        idx -= 1;
        buf[idx] = '0';
    } else {
        while (x > 0) {
            var d: u32 = x % 10;
            idx -= 1;
            buf[idx] = digitChar(d);
            x = x / 10;
        }
    }
    return buf[idx..];
}

pub fn itoa64(buf: []u8, v: i64) []u8 {
    var neg: bool = v < 0;
    var mag: u64 = @bitCast(u64, v);
    if (neg) mag = (~mag) +% 1;
    var idx: usize = buf.len;
    if (mag == 0) {
        idx -= 1;
        buf[idx] = '0';
    } else {
        while (mag > 0) {
            var d: u32 = @intCast(u32, mag % 10);
            idx -= 1;
            buf[idx] = digitChar(d);
            mag = mag / 10;
        }
    }
    if (neg) {
        idx -= 1;
        buf[idx] = '-';
    }
    return buf[idx..];
}

pub fn utoa64(buf: []u8, v: u64) []u8 {
    var x: u64 = v;
    var idx: usize = buf.len;
    if (x == 0) {
        idx -= 1;
        buf[idx] = '0';
    } else {
        while (x > 0) {
            var d: u32 = @intCast(u32, x % 10);
            idx -= 1;
            buf[idx] = digitChar(d);
            x = x / 10;
        }
    }
    return buf[idx..];
}

fn extractDigit(v: f64) u32 {
    if (v >= 9.0) return 9;
    if (v >= 8.0) return 8;
    if (v >= 7.0) return 7;
    if (v >= 6.0) return 6;
    if (v >= 5.0) return 5;
    if (v >= 4.0) return 4;
    if (v >= 3.0) return 3;
    if (v >= 2.0) return 2;
    if (v >= 1.0) return 1;
    return 0;
}

fn writeZeros(p: u8, out: *[FTOA_TMP]u8) usize {
    var n: usize = 1;
    out[0] = '0';
    if (p > 0) {
        out[n] = '.';
        n += 1;
        var z: u8 = 0;
        while (z < p) : (z += 1) {
            out[n] = '0';
            n += 1;
        }
    }
    return n;
}

fn writeRoundedOne(p: u8, out: *[FTOA_TMP]u8) usize {
    if (p == 0) {
        out[0] = '1';
        return 1;
    }
    out[0] = '0';
    out[1] = '.';
    var n: usize = 2;
    var z: u8 = 0;
    while (z + 1 < p) : (z += 1) {
        out[n] = '0';
        n += 1;
    }
    out[n] = '1';
    n += 1;
    return n;
}

// Renders a non-negative finite value in fixed-point with `p` fraction digits
// (round half up) into `out` (ASCII, forward). Returns the byte length, or 0 if
// the value cannot fit in `out` (defensive; unreachable for finite f64).
fn ftoaPositive(x: f64, p: u8, out: *[FTOA_TMP]u8) usize {
    if (x == 0.0) return writeZeros(p, out);
    // Normalize to m in [1, 10): x == m * 10^e. The iteration caps below make
    // the loop bounded even if a non-finite value ever reached here; the true
    // finite-f64 range is e in [-324, 308], well inside the caps.
    var m: f64 = x;
    var e: i32 = 0;
    var guard: u32 = 0;
    while (m >= 10.0) {
        if (guard >= 320) return 0;
        guard += 1;
        m = m / 10.0;
        e += 1;
    }
    guard = 0;
    while (m < 1.0) {
        if (guard >= 340) return 0;
        guard += 1;
        m = m * 10.0;
        e -= 1;
    }
    var idx_last: i32 = e + @intCast(i32, p);
    if (idx_last < -1) return writeZeros(p, out);
    if (idx_last == -1) {
        // First significant digit sits one place below the rounding position.
        if (extractDigit(m) >= 5) return writeRoundedOne(p, out);
        return writeZeros(p, out);
    }
    var n_ret: usize = @intCast(usize, idx_last + 1);
    var need: usize = n_ret + 1;
    // Bound the digit temp: the largest finite f64 needs at most
    // 309 integer digits + 17 fraction digits + 1 guard = 327 <= FTOA_TMP.
    if (need > FTOA_TMP) return 0;
    var dg: [FTOA_TMP]u8 = undefined;
    var rem: f64 = m;
    var gi: usize = 0;
    while (gi < need) : (gi += 1) {
        var d: u32 = extractDigit(rem);
        dg[gi] = digitChar(d);
        rem = (rem - @intToFloat(f64, @intCast(i32, d))) * 10.0;
    }
    // Round half up on the guard digit.
    var carry: bool = dg[n_ret] >= '5';
    var j: i32 = idx_last;
    while (carry and j >= 0) {
        if (dg[@intCast(usize, j)] == '9') {
            dg[@intCast(usize, j)] = '0';
            j -= 1;
        } else {
            dg[@intCast(usize, j)] = dg[@intCast(usize, j)] + 1;
            carry = false;
        }
    }
    if (carry) {
        // Carry out of the integer part: shift right, insert a leading 1.
        var s: i32 = idx_last;
        while (s >= 0) {
            dg[@intCast(usize, s + 1)] = dg[@intCast(usize, s)];
            s -= 1;
        }
        dg[0] = '1';
        e += 1;
        n_ret += 1;
    }
    var n_int: i32 = e + 1;
    if (n_int < 0) n_int = 0;
    var n: usize = 0;
    if (n_int == 0) {
        out[n] = '0';
        n += 1;
    } else {
        var k: i32 = 0;
        while (k < n_int) : (k += 1) {
            out[n] = dg[@intCast(usize, k)];
            n += 1;
        }
    }
    if (p > 0) {
        out[n] = '.';
        n += 1;
        var lead: i32 = 0;
        if (n_int == 0) lead = -e - 1;
        var lz: i32 = 0;
        while (lz < lead) : (lz += 1) {
            out[n] = '0';
            n += 1;
        }
        var avail: i32 = 0;
        if (n_int == 0) {
            avail = idx_last + 1;
        } else {
            avail = @intCast(i32, n_ret) - n_int;
        }
        var fi: i32 = n_int;
        var fk: i32 = 0;
        while (fk < avail) : (fk += 1) {
            out[n] = dg[@intCast(usize, fi)];
            n += 1;
            fi += 1;
        }
        var written: i32 = lead + avail;
        while (written < @intCast(i32, p)) : (written += 1) {
            out[n] = '0';
            n += 1;
        }
    }
    return n;
}

// NaN and +/-inf tests with no libm: NaN is the only value unequal to itself;
// a finite non-zero x has x*2 != x, so x*2 == x identifies an infinity.
fn isNanF64(x: f64) bool {
    return x != x;
}

fn isInfF64(x: f64) bool {
    return x != 0.0 and x * 2.0 == x;
}

// Copies `s` into the tail of buf (the returned slice points into buf).
// Returns buf[0..0] and writes nothing when buf cannot hold all of `s`; this is
// the documented ftoa short-buffer guard (see the module header).
fn writeTail(buf: []u8, s: []const u8) []u8 {
    if (buf.len < s.len) return buf[0..0];
    var start: usize = buf.len - s.len;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        buf[start + i] = s[i];
    }
    return buf[start..];
}

pub fn ftoa(buf: []u8, v: f64, precision: u8) []u8 {
    var p: u8 = precision;
    if (p > 17) p = 17;
    // Non-finite values render as text and always terminate (no hang, no trap).
    if (isNanF64(v)) return writeTail(buf, "nan");
    var neg: bool = false;
    var x: f64 = v;
    if (x < 0.0) {
        neg = true;
        x = -x;
    }
    if (isInfF64(x)) {
        if (neg) return writeTail(buf, "-inf");
        return writeTail(buf, "inf");
    }
    var tmp: [FTOA_TMP]u8 = undefined;
    var n: usize = ftoaPositive(x, p, &tmp);
    if (n == 0) return buf[0..0];
    if (neg) {
        if (n + 1 > FTOA_TMP) return buf[0..0];
        var s: usize = n;
        while (s > 0) : (s -= 1) {
            tmp[s] = tmp[s - 1];
        }
        tmp[0] = '-';
        n += 1;
    }
    return writeTail(buf, tmp[0..n]);
}
