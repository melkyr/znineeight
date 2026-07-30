const lib = @import("lib_green.zig");
pub fn main() void {
    var r = lib.do_thing() catch 0;
    _ = r;
}
