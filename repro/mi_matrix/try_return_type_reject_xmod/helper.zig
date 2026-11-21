// FX12 (Volume II ch12) reject-fixture helper: the cross-module operand set
// for the A3 shape. The caller's `E1!void` does not contain helper `E2`'s
// member, so `try helper.gA3();` is a set-incompatibility reject.
pub const E2 = error{B};

pub fn gA3() E2!void {
    return error.B;
}
