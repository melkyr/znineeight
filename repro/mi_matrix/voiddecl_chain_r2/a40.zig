pub const T = struct { v: u32 };
pub fn make() T {
    var f = T{ .v = 42 };
    return f;
}
