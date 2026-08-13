const std = @import("std.zig");

fn add(a: i32, b: i32) i32 { return a + b; }

pub fn main() void {
    const f: fn(i32, i32) i32 = add;
    std.io.printInt(f(1, 2));
}
