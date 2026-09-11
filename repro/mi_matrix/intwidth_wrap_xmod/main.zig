// A6F (C89-AHEAD) migration: this fixture exercises arbitrary-width integer
// wrapping (u3 7+1 and u12 4095+1 wrap to 0). The original plain `+` relied on
// wrapping; under the default `-fsafe` mode that is an intentional
// integer-overflow trap, so the additions are migrated to the explicit wrap op
// `+%` to preserve the previous wrapping behavior. Offending code:
// repro/mi_matrix/intwidth_wrap_xmod/main.zig:13 (was `a + b`) and :18 (was
// `x + y`), now `+%`.
const std = @import("std");

pub fn main() void {
    var a: u3 = @intCast(u3, 7);
    var b: u3 = @intCast(u3, 1);
    var w = a +% b;
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte('\n');
    var x: u12 = @intCast(u12, 4095);
    var y: u12 = @intCast(u12, 1);
    var w2 = x +% y;
    std.io.printInt(@intCast(i32, w2));
    std.io.writeByte('\n');
}
