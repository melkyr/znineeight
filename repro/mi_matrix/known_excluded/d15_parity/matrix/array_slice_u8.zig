fn pick(v: u32) void {
    const a = [_][]const u8{     switch (v) {
        0 => "",
        1 => "a",
        else => "b",
    } };
    _ = a;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
