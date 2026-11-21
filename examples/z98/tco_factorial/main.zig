// A6F (C89-AHEAD) migration: `acc * n` is plain arithmetic, which relies on
// two's-complement wrapping for the deep `fact(100000, 1)` call. Under the
// default `-fsafe` mode that is an intentional integer-overflow trap, so the
// body is migrated to the explicit wrap op `*%` to preserve the previous
// wrapping behavior. Offending code: examples/z98/tco_factorial/main.zig:13
// (was plain `acc * n`, now `acc *% n`).
const std = @import("std");

@cInclude("zig_runtime.h");

fn fact(n: i32, acc: i32) i32 {
    if (n == 0) return acc;
    return fact(n - 1, acc *% n);
}

pub fn main() !void {
    std.io.print("fact(10) = {}\n", .{fact(10, 1)});
    _ = fact(100000, 1);
    std.io.print("deep ok\n", .{});
}
