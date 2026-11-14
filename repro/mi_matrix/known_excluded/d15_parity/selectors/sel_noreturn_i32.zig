fn pick(v: u32) i32 {
    return switch (v) { 0 => return 1, 1 => 2, else => 3 };
}
pub fn main() void { var v: u32 = 0; v += 1; _ = pick(v); }
