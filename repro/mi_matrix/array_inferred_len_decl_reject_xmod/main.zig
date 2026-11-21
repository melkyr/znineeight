// repro/mi_matrix/array_inferred_len_decl_reject_xmod/main.zig
//   — A3-F `[_]T` declaration/annotation reject census (Amendment A3, m1500).
//
// `[_]T` is legal ONLY as the outer annotation of an array literal
// (`[_]T{...}` / `[N]T = [_]T{...}`). Everywhere a concrete type is required
// it now cleanly rejects with level-0 `error[3000]`
// ("unable to infer array size", Zig 0.15.2 oracle text), span on the `_`,
// one diagnostic per node, rc 2 / 0 emitted `.c` (classify GREEN).
//
// Baseline (fp 7fc6083) accepted every shape (rc 0 / 4 `.c`): the field was
// dropped from the emitted struct, the param degraded to C `int`, the bare
// alias and module var silently became unresolved/inferred types.
//
// census (expected_error.txt): 3000 5
const S = struct { f: [_]i32 };
fn f(x: [_]i32) void { _ = x; }
fn g() [_]i32 { return undefined; }
const T = [_]i32;
var gv: [_]i32 = undefined;

pub fn main() void {
    _ = f;
    _ = g;
    _ = T;
    _ = S{ .f = undefined };
    _ = gv;
}
