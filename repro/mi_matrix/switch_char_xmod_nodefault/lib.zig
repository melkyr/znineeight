pub fn classify(c: u8) u8 {
    var r: u8 = @intCast(u8, 9);
    switch (c) {
        'a' => r = @intCast(u8, 1),
        'b' => r = @intCast(u8, 2),
    }
    return r;
}
