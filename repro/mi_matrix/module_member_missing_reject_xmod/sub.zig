// sub.zig — nested module for module_member_missing_reject_xmod.
//
// `h.sub.nope` is a missing member of this module (the chain base resolves to
// `sub`); `answer` really exists and is used by the accepted control fixture.
pub const answer: i32 = 7;
