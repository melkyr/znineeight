const std = @import("std");

fn foo() void {}

pub fn main() void {
    var f: fn () void = foo;
    f();
    std.io.printInt(0);
}
