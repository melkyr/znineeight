// Cross-module `*[N]T` slice: the parameter is a pointer-to-array, the
// returned `[]i32` is the Z98 slice result (`(i32*)pa + start`, len end-start).
pub fn mid(pa: *[5]i32) []i32 {
    return pa[1..4];
}

// Cross-module many-item-pointer open end: `[*]T` in, `[*]T` out (Zig
// 0.15.2 parity; the pointer offset by `start`, no length).
pub fn midmp(p: [*]i32) [*]i32 {
    return p[1..];
}
