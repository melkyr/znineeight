pub fn copyStr(buf: []u8, idx: *usize, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) {
        buf[idx.*] = s[i];
        idx.* += 1;
        i += 1;
    }
}

pub fn formatU32(val: u32, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + v % 10);
            v = v / 10;
            idx -= 1;
        }
    }
    var start = idx + 1;
    return buf[start..buf_len - 1];
}

pub fn formatU64(val: u64, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, v % 10));
            v = v / 10;
            idx -= 1;
        }
    }
    var start = idx + 1;
    return buf[start..buf_len - 1];
}

// Self-contained f64 -> decimal formatter (no libc). Emits 17 significant
// digits in normalized scientific notation (`d.dddddddddddddddde+/-XX`, with
// trailing fractional zeros trimmed), which is enough for an IEEE-754 double
// to round-trip. Pure integer arithmetic on a base-1e9 big integer:
//
//   v = m * 2^E   (m = 53-bit significand recovered by exact power-of-two
//                  scaling into [1,2); E = binary exponent)
//   E >= 0 -> B = m * 2^E,      v = B * 10^0
//   E <  0 -> B = m * 5^(-E),   v = B * 10^E
//
// so the decimal digits of v are the digits of B shifted by E. Rounding the
// exact decimal to 17 significant digits (half up) is within
// 0.5 * 10^(dexp-16) < 0.5 ulp of v, so the emitted text parses back to v.
const FMT_BN_LIMBS: usize = 128;

fn fmtBnMulSmall(a: *[FMT_BN_LIMBS]u32, nlimbs: *usize, mul: u32) void {
    var carry: u64 = 0;
    var i: usize = 0;
    while (i < nlimbs.*) {
        var p: u64 = @intCast(u64, a[i]) * @intCast(u64, mul) + carry;
        a[i] = @intCast(u32, p % 1000000000);
        carry = p / 1000000000;
        i += 1;
    }
    while (carry > 0) {
        a[nlimbs.*] = @intCast(u32, carry % 1000000000);
        carry = carry / 1000000000;
        nlimbs.* += 1;
    }
}

fn fmtCopyOut(src: []const u8, buf: []u8, cap: usize) []u8 {
    var n: usize = src.len;
    if (n > cap - 1) n = cap - 1;
    var i: usize = 0;
    while (i < n) {
        buf[i] = src[i];
        i += 1;
    }
    buf[n] = 0;
    return buf[0..n];
}

pub fn formatF64(val: f64, buf: []u8, buf_len: usize) []u8 {
    var cap: usize = buf_len;
    if (cap > buf.len) cap = buf.len;
    if (cap == 0) { return buf[0..0]; }

    var sb: [64]u8 = undefined;
    var bi: usize = 0;

    // Zero and non-finite guard. There is no valid C89 literal for inf/nan;
    // this only avoids the old formatter's unbounded normalization loop.
    if (val == 0.0) { sb[0] = '0'; return fmtCopyOut(sb[0..1], buf, cap); }
    if (val != val) { sb[0] = '0'; return fmtCopyOut(sb[0..1], buf, cap); }
    if (val * 2.0 == val) { sb[0] = '0'; return fmtCopyOut(sb[0..1], buf, cap); }

    var neg: u8 = 0;
    var v = val;
    if (v < 0.0) {
        neg = 1;
        v = -v;
    }

    // Normalize v into [1, 2); e2 is the binary exponent.
    var e2: i32 = 0;
    while (v >= 2.0) {
        v = v / 2.0;
        e2 += 1;
    }
    while (v < 1.0) {
        v = v * 2.0;
        e2 -= 1;
    }
    // v == m / 2^52 exactly, so the truncating cast recovers the 53-bit m.
    var m: u64 = @intCast(u64, v * 4503599627370496.0);
    var e: i32 = e2 - 52;

    var a: [FMT_BN_LIMBS]u32 = undefined;
    var nlimbs: usize = 0;
    var mm: u64 = m;
    while (mm > 0) {
        a[nlimbs] = @intCast(u32, mm % 1000000000);
        mm = mm / 1000000000;
        nlimbs += 1;
    }

    var offset: i32 = 0;
    if (e >= 0) {
        var k: i32 = 0;
        while (k < e) {
            fmtBnMulSmall(&a, &nlimbs, 2);
            k += 1;
        }
        offset = 0;
    } else {
        var f: i32 = 0 - e;
        var k2: i32 = 0;
        while (k2 < f) {
            fmtBnMulSmall(&a, &nlimbs, 5);
            k2 += 1;
        }
        offset = e;
    }

    // Decimal digit count of B.
    var top: usize = nlimbs - 1;
    var tv: u32 = a[top];
    var topdig: u32 = 0;
    while (tv > 0) {
        topdig += 1;
        tv = tv / 10;
    }
    var nd: i32 = @intCast(i32, top * 9) + @intCast(i32, topdig);
    var dexp: i32 = nd - 1 + offset;

    // Collect the top 17 digits, plus the 18th for rounding.
    var q: u64 = 0;
    var collected: u32 = 0;
    var d18: u32 = 0;
    var li: i32 = @intCast(i32, top);
    while (li >= 0) {
        var limb: u32 = a[@intCast(usize, li)];
        var dcnt: u32 = 9;
        if (li == @intCast(i32, top)) { dcnt = topdig; }
        var tmp: [9]u8 = undefined;
        var tt: u32 = limb;
        var k3: i32 = 8;
        while (k3 >= 0) {
            tmp[@intCast(usize, k3)] = @intCast(u8, @intCast(u32, '0') + tt % 10);
            tt = tt / 10;
            k3 -= 1;
        }
        var start: usize = 9 - @intCast(usize, dcnt);
        var j: usize = start;
        while (j < 9) {
            var dg: u32 = @intCast(u32, tmp[j] - '0');
            if (collected < 17) {
                q = q * 10 + @intCast(u64, dg);
                collected += 1;
            } else if (collected == 17) {
                d18 = dg;
                collected += 1;
            }
            j += 1;
        }
        li -= 1;
    }
    while (collected < 17) {
        q = q * 10;
        collected += 1;
    }
    if (d18 >= 5) { q += 1; }
    if (q >= 100000000000000000) {
        q = q / 10;
        dexp += 1;
    }

    if (neg != 0) { sb[bi] = '-'; bi += 1; }
    var d1: u64 = q / 10000000000000000;
    var rest: u64 = q % 10000000000000000;
    sb[bi] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, d1));
    bi += 1;
    var fdig: [16]u8 = undefined;
    var fi: i32 = 15;
    while (fi >= 0) {
        fdig[@intCast(usize, fi)] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, rest % 10));
        rest = rest / 10;
        fi -= 1;
    }
    var flen: usize = 16;
    while (flen > 0 and fdig[flen - 1] == '0') { flen -= 1; }
    if (flen > 0) {
        sb[bi] = '.';
        bi += 1;
        var fj: usize = 0;
        while (fj < flen) {
            sb[bi] = fdig[fj];
            bi += 1;
            fj += 1;
        }
    }
    sb[bi] = 'e';
    bi += 1;
    var ae: i32 = dexp;
    if (ae < 0) {
        sb[bi] = '-';
        bi += 1;
        ae = 0 - ae;
    } else {
        sb[bi] = '+';
        bi += 1;
    }
    if (ae == 0) {
        sb[bi] = '0';
        bi += 1;
    } else {
        var eb: [8]u8 = undefined;
        var en: usize = 0;
        var av: i32 = ae;
        while (av > 0) {
            eb[en] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, av % 10));
            av = av / 10;
            en += 1;
        }
        while (en > 0) {
            en -= 1;
            sb[bi] = eb[en];
            bi += 1;
        }
    }
    return fmtCopyOut(sb[0..bi], buf, cap);
}
