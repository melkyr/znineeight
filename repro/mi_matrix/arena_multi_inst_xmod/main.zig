const std = @import("std.zig");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var a = mod_a.makeA();
    var b = mod_b.makeB();
    std.io.printInt(@intCast(i32, a.used + b.used));
}
