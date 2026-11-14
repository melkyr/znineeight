// Helper module for stdlib_const_decay_ok_xmod: only the LEGAL const-ADDING
// directions cross the module boundary (mutable parameters called with mutable
// slices/many-pointers, const parameters called with arrays/slices in every
// const-adding spelling, and a const-slice return).
pub fn sumConst(s: []const i32) i32 {
    return s[0] + s[1] + s[2];
}

pub fn sumConstMany(p: [*]const i32) i32 {
    return p[0] + p[1] + p[2];
}

pub fn retConstFromArray(p: *const [3]i32) []const i32 {
    return p;
}

pub fn retConstFromSlice(s: []const i32) [*]const i32 {
    return s;
}

pub fn bumpMut(s: []i32) void {
    s[0] = s[0] + 1;
}

pub fn bumpMany(p: [*]i32) void {
    p[1] = p[1] + 2;
}

pub fn strHead(s: []const u8) u8 {
    return s[0];
}

pub fn strTail(p: [*]const u8) u8 {
    return p[2];
}
