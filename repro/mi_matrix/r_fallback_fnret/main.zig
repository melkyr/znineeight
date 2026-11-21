const mod_b = @import("mod_b.zig");
const std = @import("std.zig");

const Foo = struct { a: i32 };

pub fn main() void {
    var b = mod_b.makeBar();
    std.io.printInt(@intCast(i32, b.y));
}
