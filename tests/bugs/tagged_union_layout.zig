const Tag = enum { A, B };
const U = union(Tag) {
    A: i32,
    B: bool,
};

pub fn main() void {
    const size = @sizeOf(U);
    if (size != 8) {
        unreachable;
    }
}
