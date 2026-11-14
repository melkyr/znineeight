// D10 cross-module helper (FH conversion, 2026-09-27): a single-item pointer
// indexed inside the imported module rejects `error[3066]`.
pub fn atOne(p: *i32) i32 {
    return p[1];
}
