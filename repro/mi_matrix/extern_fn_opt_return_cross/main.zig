const ext = @import("ext.zig");
pub fn main() void {
    var x: ?*u32 = ext.getp();
    _ = x;
}
