const mod_a = @import("mod_a.zig");

pub const Value = mod_a.Value;

pub fn typeOf(v: Value) i32 {
    return switch (v) { .i32 => |x| @intCast(i32, x), .f64 => |x| @intCast(i32, x), .none => 0 };
}
