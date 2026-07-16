extern fn extFn() ?*u32;

pub fn main() void {
    var x = extFn() orelse return;
    _ = x;
}
