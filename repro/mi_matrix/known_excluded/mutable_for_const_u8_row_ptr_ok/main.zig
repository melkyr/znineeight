// Off-corpus mutable-for fixture (Task 4 fix round 1, coverage 2): `|*r|`
// over a `*const [3]u8` pointer-to-array iterable. Iteration yields u8
// elements, so the capture is `*const u8`; reading `r.*` proves the element
// pointer aliases the pointee array.
const std = @import("std");

pub fn main() void {
    var a: [3]u8 = [3]u8{ 7, 8, 9 };
    const p: *const [3]u8 = &a;
    var sum: u32 = 0;
    for (p) |*r| {
        sum += @intCast(u32, r.*);
    }
    std.io.printInt(@intCast(i32, sum));
    std.io.writeByte('\n');
}
