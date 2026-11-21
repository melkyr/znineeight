const ext_c = @import("extern_c.zig");
pub fn main() void {
    ext_c.__bootstrap_print("hello");
}
