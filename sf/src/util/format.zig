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

pub fn extractDigit(v: f64) i32 {
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

extern "c" fn gcvt(value: f64, ndigit: i32, buf: [*]u8) void;

pub fn formatF64(val: f64, buf: []u8, buf_len: usize) []u8 {
    var tmp: [64]u8 = undefined;
    gcvt(val, @intCast(i32, 17), &tmp[0]);
    var n: usize = 0;
    while (n < @intCast(usize, 64) and tmp[n] != 0) : (n += 1) {}
    var cap: usize = buf_len;
    if (cap > buf.len) cap = buf.len;
    if (cap == 0) { return buf[0..0]; }
    if (n > cap - 1) n = cap - 1;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = tmp[i];
    }
    buf[n] = 0;
    return buf[0..n];
}
