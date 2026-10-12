const a = @import("lib_a.zig");
pub fn wrapper() i32 { return a.helper(); }
