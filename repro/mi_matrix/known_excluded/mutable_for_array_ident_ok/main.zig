// Off-corpus mutable-for fixture (Task 4 Step 1d): `|*x|` over a local array
// identifier (`var a: [3]u32`). The array aliases storage, so the capture is
// an element pointer into `a`; the printed values prove in-place mutation.
const std = @import("std");

pub fn main() void {
    var a: [3]u32 = [3]u32{ 1, 2, 3 };
    for (a) |*x| {
        x.* += 10;
    }
    std.io.printInt(@intCast(i32, a[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, a[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, a[2]));
    std.io.writeByte('\n');
}
