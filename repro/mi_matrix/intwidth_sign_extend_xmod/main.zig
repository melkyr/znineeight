const std = @import("std");

pub fn main() void {
    var n: i7 = @intCast(i7, -1);
    if (n < 0) std.io.writeStr("true\n") else std.io.writeStr("false\n");
    var wide: i16 = @intCast(i16, n);
    std.io.printInt(wide);
    std.io.writeByte('\n');
}
