const E = error{Bad};
const Node = struct { v: u8 };
fn g(x: u32, y: u32) E!?*Node {
    switch (x) {
        0 => return null,
        1 => {
            switch (y) {
                2 => return null,
                else => return error.Bad,
            }
        },
        else => return error.Bad,
    }
}
pub fn main() void { var r: E!?*Node = g(0, 0); _ = r; }
