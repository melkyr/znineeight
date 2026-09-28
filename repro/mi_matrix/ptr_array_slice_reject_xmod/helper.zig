// Cross-module many-item-pointer open-end site (clean `error[3067]`).
pub fn open(p: [*]i32) []i32 {
    return p[1..];
}
