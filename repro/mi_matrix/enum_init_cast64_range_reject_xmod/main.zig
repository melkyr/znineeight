// enum_init_cast64_range_reject_xmod — Task B3 item 2 clean-reject control for
// the type_resolver (enum-initializer) evaluator.
//
// The `evalConstI64Full` cast arm range-checks `@as`/`@intCast` via
// `intValueFitsType`, which also returned `true` for every `wb >= 64` target.
// `@as(u64, -1)` therefore folded to `18446744073709551615` and the enum
// compiled silently, though the value does not fit u64 (invalid Zig).
//
// FIX (Task B3 item 2): `intValueFitsType` classifies the operand syntactically
// (mirroring the comptime evaluator) and rejects the negative-to-unsigned
// mismatch; the enum member walk fails and emits `error[3055]` with 0 `.c`.
//
// Contract (post-fix): dump rc=2, 0 `.c`, `error[3055]` (the enum-member
// reject code — the canonical classifier GREENs only `error[3000]`, so this
// buckets FAIL, consistent with the other `enum_init_*_reject_xmod` controls).
const E = enum(u64) { A = @as(u64, -1) };

pub fn main() void {
    _ = E;
}
