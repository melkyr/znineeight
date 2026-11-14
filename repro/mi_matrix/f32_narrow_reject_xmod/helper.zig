// FX3 (D6 extras) cross-module helper: a runtime f64 argument and a typed
// inexact f64 const reach the same value-aware reject as the in-module sites.
pub fn take(x: f32) f32 { return x; }

pub const BadF: f64 = 0.1;
