const mod2 = @import("sub/mod2.zig");

pub const mod_tag: i32 = 10;

pub fn modValue() i32 {
    return 10 + mod2.mod2Value();
}
