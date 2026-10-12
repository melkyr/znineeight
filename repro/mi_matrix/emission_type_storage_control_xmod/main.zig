const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const Value = mod_b.Value;

pub fn main() void {
    std.io.printInt(mod_c.probe() + mod_b.typeOf(Value{ .none = {} }));
}
