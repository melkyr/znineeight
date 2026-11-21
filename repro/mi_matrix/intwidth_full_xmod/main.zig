// A6F (C89-AHEAD) migration: this fixture exercises arbitrary-width integer
// wrapping (u63 MAX+1 wraps to 0). The original plain `+` relied on wrapping;
// under the default `-fsafe` mode that is an intentional integer-overflow trap,
// so the addition is migrated to the explicit wrap op `+%` to preserve the
// previous wrapping behavior. Offending code:
// repro/mi_matrix/intwidth_full_xmod/main.zig:12 (was `a + b`, now `+%`).
const std = @import("std");

pub fn main() void {
    var a: u63 = @intCast(u63, 9223372036854775807);
    var b: u63 = @intCast(u63, 1);
    var s = a +% b;
    std.io.printInt(@intCast(i64, s));
    std.io.writeByte('\n');
    var n: i63 = @intCast(i63, -1);
    std.io.printInt(@intCast(i64, n));
    std.io.writeByte('\n');
}
