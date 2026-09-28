// Helper module for sig_unknown_type_reject_xmod: `Good` is a valid member
// used by the positive control; `Missing` deliberately does not exist so the
// cross-module member form (`helper.Missing`) is exercised.
pub const Good = struct { g: i32 };
