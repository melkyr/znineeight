// helper.zig — module for module_member_missing_reject_xmod.
//
// `main.zig` names `nope`, a member that does not exist, in read/call/store/
// address positions and through the nested module `sub`. Each site must report
// Zig's `no field or member function named '...' in module` as error[3060], not
// fall through to error[3042] / warning[3023].
pub const answer: i32 = 42;
pub const sub = @import("sub.zig");
