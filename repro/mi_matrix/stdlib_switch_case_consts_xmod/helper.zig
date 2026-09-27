// FX1 cross-module helper for stdlib_switch_case_consts_xmod: module-level
// constants (typed/untyped ints, enum-member consts, an `enum(u8)` with gaps)
// referenced as switch case items and range bounds through the `helper.`
// qualifier. `pub` so the cross-module member visibility rule accepts them.
pub const LO: i32 = 1;
pub const HI: i32 = 5;
pub const PICK = 3;
pub const Color = enum { Red, Green, Blue };
pub const LOMEM = Color.Red;
pub const HIMEM = Color.Green;
pub const Code = enum(u8) { A = 1, B = 5, C = 9 };
pub const CODE_A: Code = .A;
