const E = error { Bad };
fn f(sel: bool) E!?*u32 {
    if (sel) return error.Bad;
    return null;
}
pub fn main() void { _ = f(true) catch return; }
