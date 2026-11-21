// if_capture_else_reject_xmod — A7-F capture-scope reject census.
//
// An `if (opt) |v|` capture is scoped to the THEN arm only (Zig parity).
// Before the fix the capture stayed live across the else arm, so this program
// compiled rc 0 and the else arm read uninitialized storage (the value varied
// per run). After the fix an else-arm use is the ordinary undeclared-identifier
// reject:
//   error[20]: identifier 'v' is not declared or imported in this module
// both for the statement form and the expression form. rc 2, 0 `.c`. Zig 0.15.2
// rejects the same shapes (`use of undeclared identifier 'v'`). The count is one
// diagnostic per else-arm use (no cascade).
fn maybe() ?i32 { return null; }

pub fn main() void {
    const opt = maybe();
    if (opt) |v| {
        _ = v;
    } else {
        _ = v;
    }
    const y = if (opt) |v| v else v;
    _ = y;
}
