fn pick(v: u32) void {
    const S = struct { x: ?i32 };
    const s = S{ .x = if (v == 0) null else 0 };
    _ = s;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
