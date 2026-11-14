// enum_init_overflow_expr_xmod — Task 11J negative control: an expression whose
// folded value does not fit the backing width is rejected, never silently 0.
//
// `@sizeOf(u64) + 250` = 258 > 255 (u8 max). Before the fix the initializer
// failed to fold, the stored value stayed 0, and the backing-width fit-check
// passed — a silent miscompile. After the fix the post-layout pass stores the
// true 258 and the existing sema fit-check rejects it with the canonical
// `error[3000]` (the classifier's GREEN clean-reject bucket).
//
// Contract: dump rc=2, 0 `.c`,
//   error[3000]: enum tag value does not fit the enum backing width ...
const E = enum(u8) { A = @sizeOf(u64) + 250 };

pub fn main() void {
    _ = E.A;
}
