const E = error{Bad};
fn take(x: E!i32) void { _ = x catch 0; }
fn pick(v: u32) void {
    take(    switch (v) {
        0 => error.Bad,
        1 => 0,
        else => 1,
    });
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
