// callconv_nonpub_stdcall_xmod — final-review regression fixture (Track 1).
//
// PURPOSE: a NON-pub cross-module `extern "stdcall" fn` accessed as a field
// value (`lib.cc_std`) must report its declared stdcall convention, exactly like
// the public path already does. Before the fix the fn-type fallback in
// `semanticAnalyzerResolveFieldAccess` built the type with convention 0, so
// assigning the stdcall value to a stdcall fn-pointer (`CbS`) raised a FALSE
// `error[3000]` (source cdecl, target stdcall) while the same value was
// silently accepted by the cdecl fn-pointer (`CbC`).
//
// After the fix no diagnostic is emitted, the stdcall value is cast to the
// `FS_...` convention typedef, and the cdecl value keeps its cdecl emission.
//
// The program takes the address of extern symbols (never calls them), so it is
// an emission-only fixture (not linked/run).
//
// EMISSION ASSERTION (compile-time, for harnesses that only dump C89):
//   the stdcall value is cast to the `FS_...` typedef
//     zT_... = ((zT_..._FS_int_int)cc_std);
//   and the cdecl value keeps the default typed/mangled emission with no cast.
const lib = @import("mod_cc.zig");

const CbS = extern "stdcall" fn(i32) i32;
const CbC = fn(i32) i32;

pub fn main() void {
    var s: CbS = lib.cc_std;
    var c: CbC = lib.cc_cdecl;
    _ = s;
    _ = c;
}
