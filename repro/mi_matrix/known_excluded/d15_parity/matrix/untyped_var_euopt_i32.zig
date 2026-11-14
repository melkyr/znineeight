const E = error{Bad};
fn pick(v: u32) void {
    const e0: E!?i32 = error.Bad;
    const e1: E!?i32 = null;
    const e2: E!?i32 = 1;
    var r = switch (v) {
        0 => e0,
        1 => e1,
        else => e2,
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
