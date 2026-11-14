// D8 sibling shape: explicit `{d}`/`{x}` specifiers on typed error-set values.
const std = @import("std");

const E = error{ Foo, Bar };

pub fn main() void {
    const direct: E = error.Bar;
    std.io.print("direct={}\n", .{direct});
    std.io.print("d={d}\n", .{direct});
    std.io.print("x={x}\n", .{direct});
}
