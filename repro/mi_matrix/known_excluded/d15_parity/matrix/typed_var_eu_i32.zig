const E = error{Bad};
fn pick(v: u32) void {
    var r: E!i32 =     switch (v) {
        0 => error.Bad,
        1 => 0,
        else => 1,
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
