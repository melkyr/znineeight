// helper.zig — cross-module carrier for the layout_align8 fixture.
//
// The two structs carry one 64-bit field each (i64, f64). The fixture's
// cross-module rows prove the emitted C pins the model's align-8 layout for
// types defined in an imported module too, not just in the entry module.
pub const HS = struct { a: u8, b: i64, c: u8 };
pub const HF = struct { a: u8, b: f64, c: u8 };

pub fn makeHS(a: u8, b: i64, c: u8) HS {
    return HS{ .a = a, .b = b, .c = c };
}

pub fn makeHF(a: u8, b: f64, c: u8) HF {
    return HF{ .a = a, .b = b, .c = c };
}
