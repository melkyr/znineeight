// leaf.zig — innermost module for the module_value_* nested-module fixtures.
//
// `mid.zig` re-exports this module as `pub const leaf = @import("leaf.zig")`,
// so `mid.leaf.<member>` is a 2-level module alias (module -> module -> member).
// Every member below is `pub` so it is visible cross-module.
pub const HEADER_SIZE: usize = 16;
pub const FLAG: bool = true;
pub const SMALL: i32 = -7;
pub const ARR: [3]u8 = [3]u8{ 1, 2, 3 };
pub const BUF: []const u8 = "hi";
pub const Point = struct { x: i32, y: i32 };
pub const ORIGIN: Point = Point{ .x = 1, .y = 2 };
pub const Color = enum { red, green };
pub const PICK: Color = Color.green;
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
pub var counter: i32 = 5;
pub const CB: fn (i32, i32) i32 = add;
