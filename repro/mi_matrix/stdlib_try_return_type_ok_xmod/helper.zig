// FX12 (Volume II ch12) positive-fixture helper: a cross-module operand whose
// error set is the same named set as the caller's (`E!i32` into `E!i32`).
pub const E = error{Boom};

pub fn gOk() E!i32 {
    return 77;
}
