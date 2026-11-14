const E = error{Bad};
fn pick(v: u32) E!?i32 {
    return     switch (v) {
        0 => error.Bad,
        1 => null,
        else => 1,
    };
}
pub fn main() void { var v: u32 = 0; v += 1;
    _ = pick(v) catch 0;
}
