// Helper module for tuple_model_reject_xmod: cross-module tuple index
// out of range (error[3070] in this file).
const A = struct { i32, i32 };

pub fn oob(p: A) i32 {
    return p[7];
}
