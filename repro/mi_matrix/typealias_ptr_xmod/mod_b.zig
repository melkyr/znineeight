// typealias_ptr_xmod mod_b — cross-module `pub` pointer alias (`pub const
// P = *u8`) used in parameter position and re-exported by name.
pub const P = *u8;

pub fn deref(p: P) u8 {
    return p.*;
}
