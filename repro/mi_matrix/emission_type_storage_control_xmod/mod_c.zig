const Value = @import("mod_a.zig").Value;
const V = Value;

pub fn probe() i32 {
    var v: V = V{ .i32 = 3 };
    return v.i32;
}
