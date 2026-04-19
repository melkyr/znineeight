const std = @import("std");

pub fn main() void {
    // Empty tuple
    const empty = .{};
    _ = empty;
    std.debug.print("Empty: .{}\n", .{});

    // Simple tuple
    const simple = .{ 1, 2, 3 };
    std.debug.print("Simple: {}-{}-{}\n", simple);

    // Tuple with mixed types
    const mixed = .{ 10, true, 'A' };
    std.debug.print("Mixed: {}-{}-{}\n", mixed);

    // Tuple assignment
    var mutable_tuple = .{ 100, 200 };
    mutable_tuple = .{ 300, 400 };
    std.debug.print("Mutable: {}-{}\n", mutable_tuple);

    // Nested tuples
    const nested = .{ 1, .{ 2, 3 }, 4 };
    _ = nested;
    // std.debug.print does not support nested printing yet, so we just check it compiles

    std.debug.print("Done\n", .{});
}
