pub const Arena = struct {
    data: [*]u8,
    capacity: u32,
    used: u32,
};

pub fn create() Arena {
    return Arena{ .data = undefined, .capacity = @intCast(u32, 0), .used = @intCast(u32, 0) };
}
