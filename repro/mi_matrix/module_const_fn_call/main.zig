const std = @import("std.zig");

fn getInit() i32 { return 42; }
const x: i32 = getInit();

pub fn main() void {
    std.io.printInt(x);
}
