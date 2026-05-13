fn copyStr(buf: []u8, idx: *usize, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) {
        buf[idx.*] = s[i];
        idx.* += 1;
        i += 1;
    }
}

fn formatU32(val: u32, buf: []u8, buf_len: usize) []u8 {
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

fn formatU64(val: u64, buf: []u8, buf_len: usize) []u8 {
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

fn extractDigit(v: f64) i32 {
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

fn formatF64(val: f64, buf: []u8, buf_len: usize) []u8 {
    var is_neg: u8 = 0;
    var v = val;
    if (v < 0) {
        is_neg = 1;
        v = -v;
    }
    var exp: i32 = 0;
    if (v >= 10.0 or v < 1.0) {
        while (v >= 10.0) {
            v = v / 10.0;
            exp += 1;
        }
        while (v < 1.0 and v != 0.0) {
            v = v * 10.0;
            exp -= 1;
        }
    }
    var fmt_buf: [64]u8 = undefined;
    var fi: i32 = 0;
    var rem = v;
    while (fi < 6) {
        var digit = extractDigit(rem);
        fmt_buf[@intCast(usize, fi)] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, digit));
        fi += 1;
        rem = (rem - @intToFloat(f64, digit)) * 10.0;
    }
    var bi: i32 = 0;
    if (is_neg != 0) {
        buf[@intCast(usize, bi)] = '-';
        bi += 1;
    }
    var di: i32 = 0;
    buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
    bi += 1;
    di += 1;
    var has_frac: u8 = 0;
    while (di < 6) {
        if (fmt_buf[@intCast(usize, di)] != '0') {
            has_frac = 1;
        }
        di += 1;
    }
    if (has_frac != 0) {
        buf[@intCast(usize, bi)] = '.';
        bi += 1;
        di = 1;
        while (di < 6) {
            buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
            bi += 1;
            di += 1;
        }
    } else if (exp != 0) {
        di = 0;
        buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
        bi += 1;
        buf[@intCast(usize, bi)] = '.';
        bi += 1;
        di = 1;
        while (di < 6) {
            buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
            bi += 1;
            di += 1;
        }
    } else {
        buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, 0)];
        bi += 1;
    }
    if (exp != 0) {
        buf[@intCast(usize, bi)] = 'e';
        bi += 1;
        if (exp < 0) {
            buf[@intCast(usize, bi)] = '-';
            bi += 1;
            exp = -exp;
        } else {
            buf[@intCast(usize, bi)] = '+';
            bi += 1;
        }
        var exp_buf: [8]u8 = undefined;
        var ei: i32 = 7;
        exp_buf[@intCast(usize, ei)] = 0;
        ei -= 1;
        var expv = exp;
        while (expv > 0) {
            exp_buf[@intCast(usize, ei)] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, expv % 10));
            expv = expv / 10;
            ei -= 1;
        }
        ei += 1;
        while (@intCast(usize, ei) < 7) {
            buf[@intCast(usize, bi)] = exp_buf[@intCast(usize, ei)];
            bi += 1;
            ei += 1;
        }
    }
    buf[@intCast(usize, bi)] = 0;
    return buf[0..@intCast(usize, bi)];
}
