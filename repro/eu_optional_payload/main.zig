const E = error { Bad };
const Node = struct { v: i32 };
fn f(sel: bool) E!?*Node {
    if (sel) return error.Bad;
    return null;
}
pub fn main() void { _ = f(true) catch return; }
