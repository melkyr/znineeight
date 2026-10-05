// error_union_capture_reject_xmod — A8-F error-union condition-capture reject census.
//
// A condition that resolves to an ERROR UNION may not be captured in `if`/`while`
// without an `else |e|` arm (Volume IV Amendment A8, operator option A). Before
// the fix these shapes compiled rc 0 and the capture bound the whole error union,
// so the emitted C failed gcc (`used struct type value where scalar is required`).
// Zig 0.15.2 rejects the same no-else shape (`expected optional type, found
// 'error{Bad}!i32'`). After the fix the no-else capture is a clean level-0 reject:
//   error[3058]: error union capture is not supported; use 'catch', 'switch', or 'orelse'
// rc 2, 0 `.c`, one diagnostic per capture (no cascade). The `else |e|` form is a
// separate pre-existing parser reject and is covered by its own fixtures.
const E = error{Bad};
fn h() E!i32 { return 42; }

pub fn main() void {
    if (h()) |v| {
        _ = v;
    }
    while (h()) |v| {
        _ = v;
        break;
    }
}
