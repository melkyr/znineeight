extern fn __bootstrap_print_int(x: i32) void;

const MyUnion = union(enum) {
    A: i32,
    B: f64,
};

pub fn main() void {
    var u: MyUnion = MyUnion{ .A = @intCast(i32, 10) };
    u.tag = @intCast(usize, 1);
    __bootstrap_print_int(@intCast(i32, 0));
}
