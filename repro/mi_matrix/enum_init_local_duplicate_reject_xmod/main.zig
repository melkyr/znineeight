// enum_init_local_duplicate_reject_xmod — Task 11J fix round 1 (AMENDMENT 13)
// negative control: duplicate tags in a FUNCTION-LOCAL enum are a clean reject.
//
// Official Zig rejects `enum(u8){ A = 1, B = 1 }` wherever it appears. The
// module-level post-layout pass only sees module enums, so the semantic
// analyzer now runs the same shared member walk in check-only strict mode for a
// function-local enum declaration and emits the dedicated hard error.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: duplicate enum tag value (tag values must be unique).
fn f() u8 {
    const E = enum(u8) { A = 1, B = 1 };
    return @enumToInt(E.A);
}

pub fn main() void {
    _ = f();
}
