fn pick(v: u32) void {
    var r: ?i32 = if (v == 0) null else 0;
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
