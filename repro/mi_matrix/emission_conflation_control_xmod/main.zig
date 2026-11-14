const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var k: mod_a.Kind = .a;
    var r = mod_b.ifExpr() + mod_b.switchExpr(k);
    std.io.printInt(r);
}
