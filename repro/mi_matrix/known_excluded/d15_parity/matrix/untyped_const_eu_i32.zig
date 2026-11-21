const E = error{Bad};
fn pick(v: u32) void {
    const e0: E!i32 = error.Bad;
    const e1: E!i32 = 0;
    const e2: E!i32 = 1;
    const r = switch (v) {
        0 => e0,
        1 => e1,
        else => e2,
    };
    _ = r catch 0;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
