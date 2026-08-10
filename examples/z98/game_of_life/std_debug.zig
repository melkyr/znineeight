const std = @import("std.zig");

pub fn print(fmt: *const c_char, ...) void {
    std.io.print(fmt);
}

pub fn printInt(n: i32) void {
    std.io.printInt(n);
}
