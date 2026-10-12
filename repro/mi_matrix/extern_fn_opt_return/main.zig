extern fn getp() *u32;

pub fn main() void {
    var x: ?*u32 = getp();
    _ = x;
}
