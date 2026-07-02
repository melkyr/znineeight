extern fn extFn() ?*void;

pub fn main() void {
    var x = extFn() orelse return;
    _ = x;
}
