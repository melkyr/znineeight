const std = @import("std.zig");

pub fn print(fmt: *const c_char, ...) void {
    std.io.print(fmt);
}
