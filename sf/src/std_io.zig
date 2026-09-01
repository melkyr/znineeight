pub fn writeByte(c: u8) void {
    @putChar(c);
}

pub fn write(data: []const u8) void {
    @stdoutWrite(data.ptr, data.len);
}

pub fn writeStr(s: [*]const c_char) void {
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    @stdoutWrite(@ptrCast([*]const u8, s), len);
}

pub fn print(s: [*]const c_char, ...) void {
    writeStr(s);
}

pub fn printInt(n: i32) void {
    var tmp: [12]u8 = undefined;
    var len: usize = 0;
    var is_neg = false;
    var v: u32 = 0;
    if (n < 0) {
        is_neg = true;
        v = @intCast(u32, 0 - @intCast(i64, n));
    } else {
        v = @intCast(u32, n);
    }
    if (v == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        while (v > 0) {
            tmp[len] = '0' + @intCast(u8, v % 10);
            len += 1;
            v = v / 10;
        }
    }
    var out: [12]u8 = undefined;
    var pos: usize = 0;
    if (is_neg) {
        out[pos] = '-';
        pos += 1;
    }
    var k: usize = 0;
    while (k < len) : (k += 1) {
        out[pos] = tmp[len - 1 - k];
        pos += 1;
    }
    @stdoutWrite(@ptrCast([*]const u8, &out[0]), pos);
}

pub fn readByte() u8 {
    return @getChar();
}

pub fn sleepMs(ms: u32) void {
    @sleepMs(ms);
}
