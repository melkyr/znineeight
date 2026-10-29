// Off-corpus mutable-for fixture (Task 4 fix round 1, coverage 1): `|*r|` over
// a `[]const [3]u8` slice of rows. The item is a row pointer (`*const [3]u8`);
// reading `r.*[0]` must not be broken by the `*const [N]u8` string-literal C
// decay (`unsigned char*`). The printed first column values prove the row
// capture aliases the source rows.
const std = @import("std");

pub fn main() void {
    var rows: [2][3]u8 = [2][3]u8{ [3]u8{ 1, 2, 3 }, [3]u8{ 4, 5, 6 } };
    const s: []const [3]u8 = rows[0..];
    var k: u32 = 0;
    for (s) |*r| {
        if (k != 0) {
            std.io.writeByte(' ');
        }
        std.io.printInt(@intCast(i32, r.*[0]));
        k += 1;
    }
    std.io.writeByte('\n');
}
