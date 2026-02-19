extern fn __bootstrap_print(s: *const u8) void;
extern fn __bootstrap_print_int(n: i32) void;

fn add(a: i32, b: i32) i32 { return a + b; }
fn sub(a: i32, b: i32) i32 { return a - b; }

fn getOp(kind: u8) fn(i32, i32) i32 {
    if (kind == '+') { return add; }
    else { return sub; }
}

pub fn main() void {
    const op_plus = getOp('+');
    const res1 = op_plus(10, 5);
    __bootstrap_print("10 + 5 = ");
    __bootstrap_print_int(res1);
    __bootstrap_print("\n");

    const op_minus = getOp('-');
    const res2 = op_minus(10, 5);
    __bootstrap_print("10 - 5 = ");
    __bootstrap_print_int(res2);
    __bootstrap_print("\n");
}
