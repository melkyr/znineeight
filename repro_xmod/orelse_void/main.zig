const lib = @import("lib.zig");

pub fn main() void {
    var x = lib.get() orelse return;
    _ = x;
}
