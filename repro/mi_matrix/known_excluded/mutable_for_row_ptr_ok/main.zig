// Off-corpus mutable-for fixture (Task 4 Step 1b): `|*row|` over a
// `*[3][2]u32` pointer-to-array iterable. The item is a row pointer
// (`*[2]u32`), so `row.*[0] += 1` mutates the caller's rows in place. The
// printed first column proves the write reached the source array.
const std = @import("std");

fn fill(p: *[3][2]u32) void {
    for (p) |*row| {
        row.*[0] += 1;
    }
}

pub fn main() void {
    var a: [3][2]u32 = [3][2]u32{ [2]u32{ 0, 0 }, [2]u32{ 10, 20 }, [2]u32{ 30, 40 } };
    fill(&a);
    std.io.printInt(@intCast(i32, a[0][0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, a[1][0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, a[2][0]));
    std.io.writeByte('\n');
}
