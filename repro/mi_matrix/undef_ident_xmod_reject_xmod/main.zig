// undef_ident_xmod_reject_xmod — Task 6F cross-module regression fixture
// (variant S).
//
// An undeclared identifier in a NON-ROOT module (`lib.zig`). Pins that the
// diagnostic carries the imported file's `source_file_id` and a precise span
// (`lib.zig:2:5`), not the root module's.
//
// DEFECT (before the fix): rc=0, no diagnostic; `lib_*.c` emitted
// `zT_0 = nope;` (gcc: `nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at lib.zig:5:4.
const lib = @import("lib.zig");

pub fn main() void {
    lib.go();
}
