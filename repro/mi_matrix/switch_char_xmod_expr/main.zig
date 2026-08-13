const std = @import("std.zig");
const lib = @import("lib.zig");
pub fn main() void {
    std.io.printInt(lib.score('a'));
    std.io.printInt(lib.score('b'));
    std.io.printInt(lib.score('q'));
}
