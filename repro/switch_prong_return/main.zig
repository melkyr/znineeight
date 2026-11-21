const E = error{Bad};
const Node = struct { v: u8 };
fn f(x: u32) E!?*Node {
    switch (x) {
        0 => return null,
        1 => { return null; },
        else => return error.Bad,
    }
}
pub fn main() void { var r: E!?*Node = f(0); _ = r; }
