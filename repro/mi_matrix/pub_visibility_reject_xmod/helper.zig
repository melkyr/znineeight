// helper.zig — Task 15 (S3) reject-fixture support module.
//
// Every declaration below is deliberately NON-`pub`: main.zig references each
// one across the module boundary, which official Zig 0.15.2 rejects with
// `'<name>' is not marked 'pub'` (the flat `helper.secret(21)` defect).
pub fn visible(x: i32) i32 {
    return x + 1;
}

fn secret(x: i32) i32 {
    return x;
}

const hidden_const: i32 = 5;
const HiddenAlias = i32;
var hidden_var: i32 = 9;
pub const inner = @import("inner.zig");
