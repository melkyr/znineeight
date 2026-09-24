// helper.zig — Task 15 (S3) positive-control support module.
//
// The Task 15 rule must leave every VALID form unchanged: `pub` declarations
// are reachable across modules, and a non-`pub` declaration stays reachable
// from its OWN module (the sanctioned same-module pattern: a `pub` wrapper
// calls a private helper).
pub fn visible(x: i32) i32 {
    return x + 1;
}

fn secret(x: i32) i32 {
    return x;
}

const hidden_const: i32 = 5;

fn hidden_only(x: i32) i32 {
    return x * 2;
}

pub fn call_own() i32 {
    return secret(41) + hidden_const;
}

pub fn uses_hidden(x: i32) i32 {
    return hidden_only(x);
}

pub const shown_const: i32 = 7;
pub const ShownAlias = i32;
pub var shown_var: i32 = 10;
pub const inner = @import("inner.zig");
