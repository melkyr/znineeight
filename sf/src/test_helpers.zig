pub fn assertTrue(condition: bool) void {
    if (!condition) @panic("assertTrue failed");
}
pub fn assertEqU32(actual: u32, expected: u32) void {
    if (actual != expected) @panic("assertEqU32 failed");
}
pub fn assertEqU64(actual: u64, expected: u64) void {
    if (actual != expected) @panic("assertEqU64 failed");
}
