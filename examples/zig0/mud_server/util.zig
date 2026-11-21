// util.zig
pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i += 1;
    }
    return true;
}

pub fn copy(dest: []u8, src: []const u8) void {
    var i: usize = 0;
    const len = if (dest.len < src.len) dest.len else src.len;
    while (i < len) {
        dest[i] = src[i];
        i += 1;
    }
}
