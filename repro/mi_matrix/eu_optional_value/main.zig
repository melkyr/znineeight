const E = error { Bad };
const Node = struct { v: i32 };
extern fn getn() *Node;
fn f() E!?*Node { return getn(); }
pub fn main() void { _ = f() catch return; }
