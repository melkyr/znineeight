pub fn copyU8(dst: [*]u8, src: [*]const u8, n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dst[i] = src[i];
    }
}

pub fn copyU32(dst: [*]u32, src: [*]const u32, n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dst[i] = src[i];
    }
}

pub fn copyU64(dst: [*]u64, src: [*]const u64, n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dst[i] = src[i];
    }
}

pub fn zeroU8(dst: [*]u8, n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dst[i] = 0;
    }
}

pub fn eqlU8(a: [*]const u8, b: [*]const u8, n: usize) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}
