extern fn getp() *u32;

const E = error{Bad};
fn f() E!*u32 { return getp(); }

pub fn main() void {
    _ = f() catch |err| { return; };
}
