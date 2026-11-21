// Helper module for const_discard_reject_xmod: cross-module const-discard
// sites (`[]const i32` argument to a `[]i32` parameter, `[]const i32`
// argument to a `[*]i32` parameter, and a `[]const i32` return coerced to
// `[]i32`).
pub fn takeSlice(m: []i32) void {
    m[0] = 9;
}

pub fn takeMany(mp: [*]i32) void {
    mp[0] = 9;
}

pub fn retSlice(c: []const i32) []i32 {
    return c;
}
