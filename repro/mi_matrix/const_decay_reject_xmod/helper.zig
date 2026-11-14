// Helper module for const_decay_reject_xmod: cross-module const-violation
// sites — an array value / const slice / string literal crossing the module
// boundary into a mutable parameter, and an array value returned through a
// mutable slice return.
pub fn takeSlice(s: []i32) void {
    s[0] = 9;
}

pub fn takeMany(p: [*]i32) void {
    p[0] = 9;
}

pub fn takeU8(s: []u8) void {
    s[0] = 9;
}

pub fn retSlice(a: [3]i32) []i32 {
    return a;
}

pub fn retMany(a: [3]i32) [*]i32 {
    return a;
}
