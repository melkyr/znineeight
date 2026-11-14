fn pick(v: u32) f32 {
    return     switch (v) {
        0 => 1.5,
        1 => 2,
        else => 3.5,
    };
}
pub fn main() void { var v: u32 = 0; v += 1;
    _ = pick(v);
}
