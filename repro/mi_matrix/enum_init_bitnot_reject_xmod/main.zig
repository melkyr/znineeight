// enum_init_bitnot_reject_xmod — Task 11J negative control: bitwise NOT in an
// enum initializer is a clean reject.
//
// Official Zig propagates the enum backing type into the initializer, so `~0`
// over `enum(u8)` is plausibly 255 — a result-type/width semantic Z98's
// 64-bit evaluators do not model. Folding `~0` as all-ones (`-1`) would ship a
// wrong value or spuriously fail the backing fit-check, so 11J hard-rejects it
// (never a silent auto-increment).
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: enum member value is not a comptime-known integer expression.
const E = enum(u8) { A = ~0, B };

pub fn main() void {
    _ = E.A;
}
