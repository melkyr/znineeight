// text_scan.zig — UNDERSANDED shared text scanning/append primitives.
//
// Owners: CRLF stripping, space trimming, key/value split, and bounded
// slice appends. No I/O, no allocation, no game imports.

pub fn stripCR(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

pub fn trimSpaces(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

pub fn findEq(line: []const u8) ?usize {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '=') return i;
    }
    return null;
}

pub fn appendText(out: []u8, p: *usize, text: []const u8) void {
    var i: usize = 0;
    while (i < text.len and p.* < out.len) : (i += 1) {
        out[p.*] = text[i];
        p.* += 1;
    }
}

pub fn appendInt(out: []u8, p: *usize, value: i64) void {
    var v = value;
    var neg = false;
    if (v < 0) {
        neg = true;
        v = 0 - v;
    }
    var tmp: [24]u8 = undefined;
    var n: usize = 0;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (v > 0 and n < tmp.len) {
            tmp[n] = @intCast(u8, @intCast(u32, v % 10) + 48);
            n += 1;
            v = v / 10;
        }
    }
    if (neg and p.* < out.len) {
        out[p.*] = '-';
        p.* += 1;
    }
    while (n > 0 and p.* < out.len) {
        n -= 1;
        out[p.*] = tmp[n];
        p.* += 1;
    }
}

pub fn appendUint(out: []u8, p: *usize, value: u64) void {
    if (p.* >= out.len) return;
    if (value == 0) {
        out[p.*] = '0';
        p.* += 1;
        return;
    }
    var v = value;
    var tmp: [24]u8 = undefined;
    var n: usize = 0;
    while (v > 0 and n < tmp.len) {
        tmp[n] = @intCast(u8, @intCast(u32, v % 10) + 48);
        n += 1;
        v = v / 10;
    }
    while (n > 0 and p.* < out.len) {
        n -= 1;
        out[p.*] = tmp[n];
        p.* += 1;
    }
}
