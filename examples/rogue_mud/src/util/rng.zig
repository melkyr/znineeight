// src/util/rng.zig
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

pub fn Random_range(self: *Random, min: u8, max: u8) u8 {
    // Z98 quirk: cast to u32 before modulo to avoid overflow
    const span = @intCast(u32, max) - @intCast(u32, min) + 1;
    const offset = Random_next(self) % span;
    return @intCast(u8, @intCast(u32, min) + offset);
}
