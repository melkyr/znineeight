// ptr_to_array_index_xmod — element access through a genuine pointer-to-array
// (`var pp: *[4]u8;`) (Track-4 Task 2g-I, RED at the fixed point
// 7f9afa82deaa2356633b20a693282cf1).
//
// `pp: *[4]u8`. `pp[0]` should yield the pointed-to ARRAY `[4]u8`, so
// `pp[0][1]` is the element at index 1. The defect is in the shared index
// type resolver: `typeRegistryIndexedElemType` (`sf/src/type_registry.zig:978`)
// takes the `ptr_type` branch, sees the pointee is an array, and returns the
// pointee's ELEMENT (`u8`) instead of the pointee array itself (`[4]u8`).
// `semanticAnalyzerResolveIndexAccess` (`sf/src/semantic_analyzer.zig:3228`)
// therefore types `pp[0]` as `u8`; the lowerer's 2f-F array-decay branch
// (`sf/src/lower.zig:3157`) never fires (elem is not an array), so the emitter
// renders `zT_7 = (*pp)[zT_6];` — a scalar — and the following `[1]` subscripts
// a scalar. Pre-existing: BASE 8a322dd9 and fix 7f9afa82 byte-identical.
//
// RED (fixed point 7f9afa82…): dump rc=0, 0 target diagnostics (SILENT), 4 `.c`;
// gcc rejects `subscripted value is neither array nor pointer nor vector` (x2).
// Shape:
//   zT_..._Arr_unsigned_char_4* pp;
//   zT_7 = (*pp)[zT_6];       /* zT_7 declared `unsigned char` */
//   zT_7[zT_8] = zT_5;        /* subscript a scalar; invalid C89 */
//
// GREEN contract (OPERATOR DECISION REQUIRED — see the task-2g report Q2/Q3):
//   (A) compile-clean valid C: fix `typeRegistryIndexedElemType` to return the
//       pointee ARRAY for a pointer-to-array (then the 2f-F decay-2 path emits
//       `zT = &pp[0]` and `(*zT)[1]`), OR
//   (B) hard `error[3000]`: `docs/reference/Language_Spec_Z98.md:32` states
//       `ptr[i]` is "strictly rejected for single-item pointers".
// Current behavior is neither: silent invalid C. Whatever is chosen, contract
// = dump rc=0, gcc clean, link+run rc=0, no stdout (A), or rc=2, 0 `.c`, one
// located diagnostic (B). Never silent invalid C.
pub fn main() void {
    var a: [4]u8 = undefined;
    var pp: *[4]u8 = &a;
    pp[0][1] = 3;
    var v: u8 = pp[0][1];
    if (v != 3) {
        @panic("ptr_to_array_index_xmod: element value mismatch");
    }
}
