// typealias_fn_xmod mod_b — cross-module `pub` function-type alias
// (`pub const F = fn(i32) i32`, i.e. pointer-to-function) plus the function
// it is assigned.
pub const F = fn(i32) i32;

pub fn addone(x: i32) i32 {
    return x + 1;
}
