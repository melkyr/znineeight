const Tag = enum { A, B };
const U = union(Tag) {
    A: i32,
    B: bool,
};

extern fn __bootstrap_print_int(i: i32) void;

pub fn main() void {
    var u = U{ .A = 42 };
    switch (u) {
        .A => |val| __bootstrap_print_int(val),
        .B => |val| { if (val) __bootstrap_print_int(1) else __bootstrap_print_int(0); },
    }
}
