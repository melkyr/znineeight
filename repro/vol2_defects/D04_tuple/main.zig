// D4 in-module RED (parse error): the tuple type `struct { T1, T2 }` promised
// by Language Spec section 1.3 is not parseable.
const std = @import("std");

const Pair = struct { i32, i32 };

pub fn main() void {
    const p: Pair = .{ 3, 4 };
    std.io.print("p={}\n", .{p});
}
