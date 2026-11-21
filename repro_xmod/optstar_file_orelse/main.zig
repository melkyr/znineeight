const lib = @import("lib.zig");

pub fn main() void {
    var x = lib.extFn() orelse return;
    _ = x;
}
