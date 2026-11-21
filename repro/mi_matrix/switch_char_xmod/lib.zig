pub fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 0);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
        else => r = @intCast(u8, 0),
    }
    return r;
}
