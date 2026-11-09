fn pick(v: u32) void {
    const a = [_]?i32{ if (v == 0) null else 0 };
    _ = a;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
