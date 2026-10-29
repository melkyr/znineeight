// Off-corpus mutable-for fixture (Task 4 fix round 1, coverage 3): `|*row|`
// over a local `var m: [3][2]u32` array. The element is itself an array, so
// the array-type header branch must bind a pointer-to-row (`*[2]u32`); the
// printed first column proves the writes land in the source array.
const std = @import("std");

pub fn main() void {
    var m: [3][2]u32 = [3][2]u32{ [2]u32{ 0, 0 }, [2]u32{ 10, 20 }, [2]u32{ 30, 40 } };
    for (m) |*row| {
        row.*[0] += 1;
    }
    std.io.printInt(@intCast(i32, m[0][0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m[1][0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m[2][0]));
    std.io.writeByte('\n');
}
