// D12 in-module RED (acceptance bug): a `[]const T` -> `[]T` coercion is
// accepted with warning[3000] only and then mutates through the alias.
// The Language Spec (Type Coercions, Const Correctness) forbids it.
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const c: []const i32 = arr;
    var m: []i32 = c;
    m[0] = 9;
    std.io.print("m0={}\n", .{m[0]});
}
