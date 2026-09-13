// typealias_opt_xmod mod_b — cross-module `pub` optional alias
// (`pub const O = ?i32`) used in parameter/return position.
pub const O = ?i32;

pub fn pick(x: i32) O {
    if (x < 0) return null;
    return x;
}
