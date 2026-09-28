// Cross-module `*[N]T` slice: the parameter is a pointer-to-array, the
// returned `[]i32` is the Z98 slice result (`(i32*)pa + start`, len end-start).
pub fn mid(pa: *[5]i32) []i32 {
    return pa[1..4];
}
