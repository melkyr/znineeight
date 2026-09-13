// typealias_eu_xmod mod_b — cross-module `pub` error-union alias
// (`pub const E = error{Bad}!i32`) used in parameter/return position.
pub const E = error{Bad}!i32;

pub fn eu(x: i32) E {
    if (x < 0) return error.Bad;
    return x;
}
