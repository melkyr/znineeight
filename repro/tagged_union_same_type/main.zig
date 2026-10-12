extern fn __bootstrap_print_int(x: i32) void;

const U = union(enum) {
    A: i32,
    B: i32,
};

pub fn main() void {
    var u: U = U{ .B = @intCast(i32, 7) };
    var r: i32 = @intCast(i32, 0);
    switch (u) {
        .A => |a| r = a + @intCast(i32, 100),
        .B => |b| r = b,
    }
    __bootstrap_print_int(r);
}
