fn pick(v: u32) void {
    const S = struct { x: []const u8 };
    const s = S{ .x =     switch (v) {
        0 => "",
        1 => "a",
        else => "b",
    } };
    _ = s;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
