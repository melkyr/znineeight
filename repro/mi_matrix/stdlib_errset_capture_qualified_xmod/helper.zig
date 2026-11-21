// FE (D8 + D11) fixture helper: cross-module error set (catch-capture print)
// and a cross-module tagged union (module-qualified prong capture).
pub const E = error{ Foo, Bar };

pub fn mightFail(flag: bool) E!i32 {
    if (flag) return error.Bar;
    return 7;
}

pub const Box = union(enum) {
    num: i32,
    empty,
};

// FX4: cross-module enum for the module-qualified enum-prong identity check.
pub const Kind = enum { plus, minus };

pub fn boxVal(b: Box) i32 {
    return switch (b) {
        Box.num => |v| v,
        else => 0,
    };
}
