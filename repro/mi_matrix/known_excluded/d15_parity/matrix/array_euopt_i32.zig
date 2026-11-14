const E = error{Bad};
fn pick(v: u32) void {
    const a = [_]E!?i32{     switch (v) {
        0 => error.Bad,
        1 => null,
        else => 1,
    } };
    _ = a;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
