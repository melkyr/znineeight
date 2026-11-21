extern fn getp() *u32;
pub fn main() void {
    var p: *u32 = getp();
    var x: ?*u32 = p;
    _ = x;
}
