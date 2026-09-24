// inner.zig — Task 15 (S3) reject-fixture nested-module support.
//
// `helper.inner` is a `pub` module alias, but the members referenced from
// main.zig are not `pub`; the nested shape (`mod.sub.member`) had no
// visibility gate before Task 15.
pub fn visible2(x: i32) i32 {
    return x + 2;
}

fn secret2(x: i32) i32 {
    return x;
}

const hidden_const2: i32 = 6;
