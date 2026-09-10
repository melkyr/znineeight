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
