// FX3 (D6 extras) cross-module helper: an f32 parameter and an f32-field
// struct whose initializer sites take the same value-aware narrowing path as
// the in-module ones.
pub fn take(x: f32) f32 { return x; }

pub const S = struct { x: f32 };
