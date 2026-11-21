// callconv_mixed_fnptr_typedef_xmod — REGRESSION fixture for the convention-aware
// fn-pointer typedef collision (review finding on Track1 Task 3).
//
// PURPOSE: declare BOTH a default (cdecl) function-pointer type and an
// `extern "stdcall"` function-pointer type with the SAME structural signature
// `fn(i32) void` in one program, and assign each to its own variable:
//   const CbC = fn(i32) void;
//   const CbS = extern "stdcall" fn(i32) void;
//   var c: CbC = undefined;
//   var s: CbS = undefined;
// Before the fix, `getCTypeName` built the same emitted C typedef name for both
// entries (the convention was not part of the name), and the special-type emitter
// dedups typedefs by C name, so only ONE `zT_..._F?_void_int` typedef was emitted
// and both variables used it (the convention of whichever emitted first won).
// After the fix the stdcall entry emits a DISTINCT typedef name carrying
// `Z98_STDCALL`; the cdecl entry keeps exactly today's name.
//
// The program has no observable stdout and is self-contained (never references an
// extern symbol), so it also runs on linux.
//
// RUNRC=0
// EXPECTED STDOUT: (empty)
//
// EMISSION ASSERTION (compile-time, for harnesses that only dump C89):
//   exactly two fn-pointer typedefs are emitted for this fixture and exactly one
//   of them contains `Z98_STDCALL`:
//     typedef void (*zT_..._F?_void_int)(int);
//     typedef void (Z98_STDCALL *zT_..._F?_void_int)(int);

const CbC = fn(i32) void;
const CbS = extern "stdcall" fn(i32) void;

pub fn main() void {
    var c: CbC = undefined;
    var s: CbS = undefined;
    _ = c;
    _ = s;
}
