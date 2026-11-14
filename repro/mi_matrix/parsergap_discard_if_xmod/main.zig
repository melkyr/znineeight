const std = @import("std");

fn fn_maybe(x: i32) ?i32 {
    if (x > 0) {
        return x;
    }
    return null;
}

pub fn main() void {
    var opt: ?i32 = fn_maybe(7);
    var r: i32 = 0;
    if (opt) |_| {
        r = 1;
    } else {
        r = 2;
    }
    std.io.printInt(r);
}
