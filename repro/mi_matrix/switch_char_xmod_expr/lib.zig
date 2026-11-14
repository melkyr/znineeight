pub fn score(c: u8) i32 {
    return switch (c) {
        'a' => @intCast(i32, 1),
        'b' => @intCast(i32, 2),
        else => @intCast(i32, 0),
    };
}
