pub const S = struct { v: u32 };
pub fn make() S {
    var f = S{ .v = 20 };
    return f;
}
