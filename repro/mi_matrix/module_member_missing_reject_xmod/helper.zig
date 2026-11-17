// helper.zig — module for module_member_missing_reject_xmod.
//
// `main.zig` reads `h.nope`, a member that does not exist. Lowering must report
// Zig's `no field or member function named '...' in module` as error[3060], not
// fall through to error[3042] / warning[3023].
pub const answer: i32 = 42;
