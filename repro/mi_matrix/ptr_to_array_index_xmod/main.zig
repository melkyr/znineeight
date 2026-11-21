// ptr_to_array_index_xmod — element access through a genuine pointer-to-array
// (`var pp: *[4]u8;`) (Track-4 Task 2g-I pinned; Task 2g-F hard-error contract).
//
// OPERATOR RULING (2026-09-16, verified against the Zig langref): real Zig
// REJECTS `var pp: *[4]u8; pp[0][1] = 3;`. A `*[N]T` supports index syntax
// `array_ptr[i]`, but `pp[0]` yields the ELEMENT (`u8`), not the array; the
// element is reached via `pp[1]` or `pp.*[1]`. Indexing the resulting scalar
// (`pp[0][1]`) is therefore a type error, so Z98 must reject it with a hard
// `error[3000]` (matching real Zig and `docs/reference/Language_Spec_Z98.md:32`,
// "`ptr[i]` is allowed for many-item pointers, but strictly rejected for
// single-item pointers"). This is option (B); the compile-clean decay (A) was
// explicitly rejected.
//
// The pre-2g-F defect: `typeRegistryIndexedElemType` (`sf/src/type_registry.zig:978`)
// types `pp[0]` as `u8` (correct), but `semanticAnalyzerResolveIndexAccess`
// (`sf/src/semantic_analyzer.zig:3228`) then let the outer `[1]` index that
// scalar, and the emitter rendered `zT_7 = (*pp)[zT_6]; zT_7[zT_8] = ...` —
// SILENT invalid C89. Pre-existing: BASE 8a322dd9 and fix 7f9afa82 byte-identical.
//
// RED (fixed point 7f9afa82…): dump rc=0, 0 target diagnostics (SILENT), 4 `.c`;
// gcc rejects `subscripted value is neither array nor pointer nor vector` (x2).
//
// GREEN (Task 2g-F, option B): dump rc=2, 0 `.c`, one located
// `error[3000] cannot index a value of non-array, non-pointer type`. Never
// silent invalid C.
pub fn main() void {
    var a: [4]u8 = undefined;
    var pp: *[4]u8 = &a;
    pp[0][1] = 3;
    var v: u8 = pp[0][1];
    if (v != 3) {
        @panic("ptr_to_array_index_xmod: element value mismatch");
    }
}
