// ptr_slice_reject_xmod cross-module site: indexing a `*i32` inside an
// imported module rejects `error[3066]` exactly like the in-module shape.
pub fn atOne(p: *i32) i32 {
    return p[1];
}
