pub fn fnv1a(data: []const u8) u32 {
    var hash: u32 = 2166136261;
    for (data) |byte| {
        hash ^= @intCast(u32, byte);
        hash = hash *% 16777619;
    }
    return hash;
}
