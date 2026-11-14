// Off-corpus mutable-for fixture (Task 3 Step 1g; Task 4 fix round 1
// coverage 4): a module-member array aliases the global, so the capture is
// addressable. The printed values prove the `|*x|` write mutates `h.arr` in
// place (initial `{ 1, 2, 3 }` -> `{ 11, 12, 13 }`).
const std = @import("std");
const h = @import("helper.zig");

pub fn main() void {
    for (h.arr) |*x| {
        x.* += 10;
    }
    std.io.printInt(@intCast(i32, h.arr[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, h.arr[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, h.arr[2]));
    std.io.writeByte('\n');
}
