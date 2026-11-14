// D12 cross-module helper: a mutable-slice parameter.
pub fn take(m: []i32) void {
    m[0] = 9;
}
