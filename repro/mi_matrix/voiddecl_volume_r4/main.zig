const std = @import("std");
const mod = @import("mod.zig");
pub fn main() void {
    var s: u32 = 0;
    s += mod.v0000; s += mod.v0100; s += mod.v0200;
    s += mod.v0300; s += mod.v0400; s += mod.v0500;
    s += mod.v0600; s += mod.v0700; s += mod.v0800;
    s += mod.v0900;
    std.io.printInt(s);
    var x = mod.make();
    std.io.printInt(x.v);
}
