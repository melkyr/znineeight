// Helper module for tuple_elem_type_reject_xmod (FB2): a pub named tuple type
// referenced as a TYPE VALUE from a tuple element (`.{ helper.Pair, 5 }`),
// which must clean-reject error[3063] on both print paths.
pub const Pair = struct { i32, i32 };
