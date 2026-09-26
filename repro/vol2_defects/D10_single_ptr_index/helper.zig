// D10 cross-module helper: a single-item pointer indexed inside the imported
// module.
pub fn atOne(p: *i32) i32 {
    return p[1];
}
