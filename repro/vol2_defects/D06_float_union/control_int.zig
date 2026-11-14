// D6 control: annotated integer payloads work.
const std = @import("std");

const ShapeI = union(enum) {
    go: u8,
    count: i32,
    empty,
};

pub fn main() void {
    var a: ShapeI = ShapeI{ .go = 7 };
    var b: ShapeI = ShapeI{ .count = 9 };
    std.io.print("go={} count={}\n", .{ a.go, b.count });
}
