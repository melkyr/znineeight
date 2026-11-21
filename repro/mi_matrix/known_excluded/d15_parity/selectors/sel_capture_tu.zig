const U = union(enum) { a: i32, b: void, c: void };
fn pick(u: U) i32 {
    return switch (u) {
        .a => |x| x,
        .b => 0,
        else => 0,
    };
}
pub fn main() void { _ = pick(.{ .a = 1 }); }
