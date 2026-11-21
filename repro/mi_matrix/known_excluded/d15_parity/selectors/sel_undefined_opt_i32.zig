fn pick(v: u32) ?i32 {
    return switch (v) { 0 => undefined, 1 => null, else => 0 };
}
pub fn main() void { var v: u32 = 0; v += 1; _ = pick(v); }
