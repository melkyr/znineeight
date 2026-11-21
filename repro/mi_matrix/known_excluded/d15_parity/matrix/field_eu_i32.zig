const E = error{Bad};
fn pick(v: u32) void {
    const S = struct { x: E!i32 };
    const s = S{ .x =     switch (v) {
        0 => error.Bad,
        1 => 0,
        else => 1,
    } };
    _ = s;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
