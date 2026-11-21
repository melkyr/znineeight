fn pick(v: u32) ??i32 {
    return     switch (v) {
        0 => null,
        1 => 0,
        else => 1,
    };
}
pub fn main() void { var v: u32 = 0; v += 1;
    _ = pick(v);
}
