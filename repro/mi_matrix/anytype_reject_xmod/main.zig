// repro/mi_matrix/anytype_reject_xmod/main.zig — A1-F anytype reject census.
//
// The `anytype` marker is not supported in Z98. Ruling 3 moved the FX13-F
// positive control's `fn anyf(x: anytype) void {}` shape here: every
// signature/type position carrying `anytype` now rejects with level-0
// `error[16]` (`ERR_2012_ANYTYPE_NOT_SUPPORTED`, "anytype not supported in
// Z98"), one diagnostic per node, rc 2 / 0 emitted `.c` (classify FAIL). The
// shapes: declaration-only, called, return position, nested fn-pointer arg.
//
// census (expected_error.txt): 16 4
fn declOnly(x: anytype) void {}
fn called(x: anytype) void {}
fn returnsAny() anytype { }
fn nested(cb: fn (anytype) void) void {}

pub fn main() void { called(5); }
