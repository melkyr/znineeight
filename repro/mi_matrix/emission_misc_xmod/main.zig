const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main(argc: u32, argv: [][*]u8) void {
    _ = argv;
    var t = mod_b.copyFieldA();
    t = mod_b.copyFieldB();
    t = mod_b.copyFieldC();
    t = mod_a.addOne(t);
    std.io.printInt(@intCast(i32, t + argc));
}
