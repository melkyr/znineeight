fn pick(v: u32) ?i32 {
    return if (v == 0) if (v == 1) null else 0 else 1;
}
pub fn main() void { var v: u32 = 0; v += 1; _ = pick(v); }
