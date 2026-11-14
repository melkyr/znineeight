// packed_array_global_xmod — FEATURE-GAP RED fixture (L5: array of packed in a
//   storage global). Also re-exercises whole-element global stores (store-drop fix).
// GREEN (contract): "1 33 3 4\n" — size 1 (stride 1, no pad); grid[1] byte =
//   x=1,y=2 => 0x21 = 33; grid[3].x=3, .y=4.
const std = @import("std");

const Cell = packed struct { x: u4, y: u4 };
var grid: [4]Cell = undefined;

pub fn main() void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        grid[i] = Cell{ .x = @intCast(u4, i), .y = @intCast(u4, i + 1) };
    }
    std.io.printInt(@intCast(i32, @sizeOf(Cell)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &grid[0]);
    std.io.printInt(@intCast(i32, bp[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, grid[3].x));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, grid[3].y));
    std.io.writeByte('\n');
}
