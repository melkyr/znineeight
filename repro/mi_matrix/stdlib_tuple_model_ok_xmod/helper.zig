// Helper module for stdlib_tuple_model_ok_xmod (FB, Volume II D4): a
// cross-module named tuple type, tuple params/returns, an inline tuple return
// type and a module-scope tuple global.
pub const Pair = struct { i32, i32 };

pub var g: Pair = .{ 4, 5 };

pub fn swap(p: Pair) Pair {
    return .{ p[1], p[0] };
}

pub fn mk(a: i32, b: i32) struct { i32, i32 } {
    return .{ a, b };
}

pub fn first(t: Pair) i32 {
    return t[0];
}
