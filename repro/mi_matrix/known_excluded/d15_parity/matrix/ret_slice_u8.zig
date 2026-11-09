fn pick(v: u32) []const u8 {
    return     switch (v) {
        0 => "",
        1 => "a",
        else => "b",
    };
}
pub fn main() void { var v: u32 = 0; v += 1;
    _ = pick(v);
}
