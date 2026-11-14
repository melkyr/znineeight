// Helper module for sig_known_type_ok_xmod. `Good` is the cross-module
// `helper.Good` member form; `T` is referenced BARE from main.zig and is only
// reachable through the resolver's global name-cache scan (the same
// broader-than-Zig lookup the 39 `voiddecl_chain_r2` names depend on).
pub const Good = struct { g: i32 };
pub const T = i32;
