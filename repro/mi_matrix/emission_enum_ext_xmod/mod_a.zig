pub const Kind = enum(u16) { plus, minus, star };

pub fn pick(k: Kind) u32 {
    var r: u32 = 0;
    switch (k) {
        Kind.plus => r = 1,
        Kind.minus => r = 2,
        Kind.star => r = 3,
        else => {},
    }
    return r;
}
