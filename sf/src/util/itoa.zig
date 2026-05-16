pub fn itoa(value: u32, buf: []u8) u32 {
    var i: u32 = @intCast(u32, buf.len) - 1;
    buf[@intCast(usize, i)] = 0;
    var v = value;
    if (v == 0) {
        i -= 1;
        buf[@intCast(usize, i)] = '0';
    } else {
        while (v > 0 and i > 0) {
            var digit = v % 10;
            v = v / 10;
            i -= 1;
            buf[@intCast(usize, i)] = '0' + @intCast(u8, digit);
        }
    }
    return @intCast(u32, buf.len) - i - 1;
}
