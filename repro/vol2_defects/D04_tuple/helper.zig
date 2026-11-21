// D4 cross-module helper: a module-scope tuple literal and a grouped return
// of a named struct.
pub const Pair = .{ 10, 20 };

pub const DivMod = struct { q: i32, r: i32 };

pub fn divmod(a: i32, b: i32) DivMod {
    return .{ a / b, a % b };
}
