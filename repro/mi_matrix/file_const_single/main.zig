pub const File = void;
extern fn extFn() ?*File;

pub fn main() void {
    var x = extFn() orelse return;
    _ = x;
}
