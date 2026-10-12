// src/util/rng.zig
const std = @import("std");

pub const Random = struct {
    seed: u32,
};

pub fn Random_init(seed: u32) Random {
    return Random{ .seed = seed };
}

pub fn Random_next(self: *Random) u32 {
    // Numerical Recipes constants - C89 safe
    self.seed = self.seed * 1103515245 + 12345;
    return (self.seed >> 16) & 0x7FFF;
}

@cInclude("zig_runtime.h");

pub fn Random_range(self: *Random, min: u8, max: u8) u8 {
    if (max < min) {
        std.io.print("Random_range error: min=");
        std.io.printInt(@intCast(i32, min));
        std.io.print(" max=");
        std.io.printInt(@intCast(i32, max));
        std.io.print("\n");
        return min;
    }
    // Z98 quirk: cast to u32 before modulo to avoid overflow
    const span = @intCast(u32, max) - @intCast(u32, min) + 1;
    if (span == 0) return min;
    const offset = Random_next(self) % span;
    return @intCast(u8, @intCast(u32, min) + offset);
}
