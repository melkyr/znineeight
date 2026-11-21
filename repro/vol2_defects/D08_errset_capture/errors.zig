// D8 cross-module helper: error set + fallible function.
pub const E = error{ Foo, Bar };

pub fn mightFail() E!i32 {
    return error.Bar;
}

pub const Holder = struct { e: E };
