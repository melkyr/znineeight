const value_mod = @import("value.zig");

pub fn main() void {
    var v1: value_mod.Value = undefined;
    var v2: value_mod.Value = undefined;

    // Full union assignment
    v1 = v2;
}
