const std = @import("std");
pub fn main() void {
    var c: u8 = 0;
    switch (c) {
        ' ' => { c = 1; },
        else => return,
    }
    std.io.printInt(c);
}
