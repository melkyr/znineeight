// const_rodata_xmod_xmod — M2 T1C-F cross-module const-rodata fixture.
//
// A `pub const` table + scalar used cross-module, and `&` of a `pub const`
// array (extern const + addr_of cast path). The owner emits `const` rodata
// with external linkage and an `extern const` header row; the importer folds
// scalar uses and loads the aggregate.
pub const K: u32 = 40 + 2;
pub const TBL = [3]u32{ 10, 20, 30 };
pub const ARR = [3]i32{ 7, 8, 9 };
pub const TAG: bool = true;
