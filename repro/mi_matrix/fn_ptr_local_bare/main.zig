extern fn __bootstrap_print_int(n: i32) void;

fn add(a: i32, b: i32) i32 { return a + b; }

pub fn main() void {
    const f: fn(i32, i32) i32 = add;
    __bootstrap_print_int(f(1, 2));
}
