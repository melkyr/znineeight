const lib = @import("lib.zig");
const std = @import("std.zig");
pub fn main() void {
    lib.bump();
    lib.bump();
    std.io.printInt(lib.counter);
}
