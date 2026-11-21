fn pick(v: u32) bool {
    return switch (v) { 0 => 1, else => true };
}
pub fn main() void { var v: u32 = 0; v += 1; _ = pick(v); }
