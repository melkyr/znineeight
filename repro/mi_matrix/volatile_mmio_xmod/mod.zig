// volatile_mmio_xmod mod — cross-module pointer-to-volatile surface.
// `pub const Reg = *volatile u32` + `*volatile u32` parameters force the
// volatile pointee type through signatures, returns and a `pub` alias.
pub const Reg = *volatile u32;

pub fn poke(p: *volatile u32, v: u32) void {
    p.* = v;
}

pub fn peek(p: *volatile u32) u32 {
    return p.*;
}
