pub fn mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a) |c, i| {
        if (c != b[i]) return false;
    }
    return true;
}

pub fn binary_search(offsets: []u32, target: u32) u32 {
    var lo: u32 = 0;
    var hi: u32 = @intCast(u32, offsets.len);
    while (lo < hi) {
        var mid = lo + (hi - lo) / 2;
        if (offsets[@intCast(usize, mid)] <= target) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo == 0) {
        return @intCast(u32, 0);
    } else {
        return @intCast(u32, lo - 1);
    }
}
