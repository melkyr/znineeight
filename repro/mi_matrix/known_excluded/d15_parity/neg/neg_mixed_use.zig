fn pick(v: u32) i32 {
    const x = switch (v) { 0 => 1, else => true };
    return x + 1;
}
pub fn main() void { var v: u32 = 0; v += 1; _ = pick(v); }
