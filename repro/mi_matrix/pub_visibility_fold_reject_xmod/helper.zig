// helper.zig — Task 15 (S3) const-fold reject-fixture support module.
//
// `hidden_const` is deliberately NON-`pub`: main.zig references it in an
// array-size and an enum-initializer position, which official Zig 0.15.2
// rejects with `'hidden_const' is not marked 'pub'` (the type-resolver
// const-fold path, fix round 1).
pub const inner = @import("inner.zig");

const hidden_const: i32 = 5;
