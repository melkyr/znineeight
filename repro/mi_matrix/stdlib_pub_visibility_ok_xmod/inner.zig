// inner.zig — Task 15 (S3) positive-control nested-module support.
//
// `helper.inner` is a `pub` module alias and every member main.zig references
// is `pub`; `call_own2` exercises the same-module private access through the
// nested module.
pub fn visible2(x: i32) i32 {
    return x + 2;
}

fn secret2(x: i32) i32 {
    return x;
}

pub fn call_own2() i32 {
    return secret2(3);
}

pub const shown_const2: i32 = 8;
