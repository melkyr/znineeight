extern fn __bootstrap_print_int(n: i32) void;

fn add(a: i32, b: i32) i32 { return a + b; }
fn sub(a: i32, b: i32) i32 { return a - b; }

fn getOp(kind: u8) fn(i32, i32) i32 {
    if (kind == @intCast(u8, 43)) { return add; }
    else { return sub; }
}

pub fn main() void {
    const op = getOp(@intCast(u8, 43));
    __bootstrap_print_int(op(10, 5)); // expect 15 once fixed
}
