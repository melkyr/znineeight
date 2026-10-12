const lib = @import("lib.zig");

pub fn main() void {
    var x = lib.noop();
    _ = x;
}
