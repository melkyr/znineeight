// D6 control: annotated bool payloads work.
const std = @import("std");

const ShapeB = union(enum) {
    on: bool,
    empty,
};

pub fn main() void {
    var b: ShapeB = ShapeB{ .on = true };
    std.io.print("b={}\n", .{b.on});
}
