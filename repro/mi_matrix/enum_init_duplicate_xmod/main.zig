// enum_init_duplicate_xmod — Task 11J negative control: duplicate enum tag
// values are a clean reject.
//
// Official Zig rejects `enum(u8){ A = 1, B = 1 }` (`error: enum tag value 1
// already taken`). The post-layout re-evaluation pass computes the full member
// sequence and rejects a repeated tag value with the dedicated hard error.
// Before the fix the duplicate was accepted (both members emitted 1).
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: duplicate enum tag value (tag values must be unique).
const E = enum(u8) { A = 1, B = 1 };

pub fn main() void {
    _ = E.A;
    _ = E.B;
}
