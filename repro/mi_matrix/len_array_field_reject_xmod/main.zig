// len_array_field_reject_xmod — Task 11N fix-round-1 negative pin.
//
// `s.a.foo` (an unknown field on an array field) must be REJECTED. The Task 11N
// analyzer fallback originally called `semanticAnalyzerArrayFieldLen` for every
// field access reaching the scalar fallback without checking the accessed name,
// so `s.a.foo` was wrongly accepted as `usize` (a widening: pre-fix `error[3000]
// void`, buggy 11N rc=0). The fallback is now gated on `field_name_id == "len"`,
// mirroring the lowerer intercept, restoring the clean rejection.
//
// Expected (fixed): dump rc=2, `error[3000]: cannot declare variable of type
// void`, 0 `.c` emitted — the canonical classifier's GREEN clean-reject bucket.
const S = struct { a: [4]u8 };

pub fn main() void {
    var s: S = undefined;
    const n = s.a.foo;
    _ = n;
}
