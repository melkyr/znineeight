// inner.zig — Task 15 (S3) const-fold reject-fixture nested-module support.
//
// `helper.inner` is a `pub` module alias, but `hidden_const2` is not `pub`;
// the nested const-fold positions (`helper.inner.hidden_const2`) are the same
// shape two levels deep.
const hidden_const2: i32 = 6;
