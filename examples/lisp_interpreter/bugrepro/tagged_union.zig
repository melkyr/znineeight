const Tag = enum { A, B };
const U = union(Tag) {
    A: i32,
    B: bool,
};
pub fn main() void {
    var u = U{ .A = 42 };
    switch (u) {
        .A => |val| { _ = val; },
        .B => |val| { _ = val; },
    }
}
