// const_size_inline_ctrl_xmod — GREEN controls for the array-size fold family.
// All three shapes already fold at the Task 2b-F fixed point
// 0da3f1391075e3e77c54b626d5550e3b (dump rc=0, 4 `.c`, gcc clean, run rc=0).
//
//   x: [A * B]u8 — an INLINE arithmetic expression of module consts: handled
//                  directly by the `array_type` arm (`sf/src/type_resolver.zig:
//                  1123-1139`), independent of `evalConstU32Full`'s binary gap.
//   y: [16]u8    — a bare int literal.
//   z: [N]u8     — a direct MODULE-LEVEL ident const (`const N: usize = 16`),
//                  handled by `evalConstU32Full`'s `ident_expr` arm.
//
// These pin that the Task 2c-F fix must not regress the already-working
// inline/literal/direct-ident forms.
const A: usize = 4;
const B: usize = 4;
const N: usize = 16;

pub fn main() void {
    var x: [A * B]u8 = undefined;
    var y: [16]u8 = undefined;
    var z: [N]u8 = undefined;
    if (x.len != 16) { @panic("x"); }
    if (y.len != 16) { @panic("y"); }
    if (z.len != 16) { @panic("z"); }
}
