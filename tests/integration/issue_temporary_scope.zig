extern fn foo(x: i32) void;

fn do_test(cond: bool) void {
    const y = if (cond) 42 else 24; // this creates a temporary
    foo(y); // the temporary must be in scope here
}

pub fn main() void {
    do_test(true);
}
