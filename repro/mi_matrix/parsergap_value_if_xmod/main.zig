const std = @import("std");

fn take_cap(o: ?i32) i32 {
    var x: i32 = if (o) |cap| cap else 0;
    return x;
}

pub fn main() void {
    var v: i32 = take_cap(@intCast(i32, 7));
    std.io.printInt(v);
}
