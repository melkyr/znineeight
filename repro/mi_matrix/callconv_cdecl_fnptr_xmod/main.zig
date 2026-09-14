// callconv_cdecl_fnptr_xmod — Task 3R review-fix regression fixture.
//
// PURPOSE: a default-cdecl extern function VALUE assigned to a cdecl
// fn-pointer type must keep the pre-3R mangled emission:
//   zT_1 = zF_..._z98_cdecl_probe;
// The 3R `.func_ref` change originally took the original/unmangled extern-name
// path for ANY extern fn type (is_extern != 0), which changed default-cdecl
// bytes for this shape. The fix restricts that path to extern fn types that
// also carry FN_FLAG_STDCALL (i.e. when the convention cast actually applies).
//
// The program takes the address of an extern symbol (never calls it), so it is
// an emission-only fixture (not linked/run).
//
// EMISSION ASSERTION (compile-time, for harnesses that only dump C89):
//   the function value is emitted with its MANGLED name and NO cast:
//     zT_1 = zF_..._z98_cdecl_probe;
//   and no `FS_...` typedef is emitted (no convention-bearing type here).

const Cb = fn(i32) void;
extern fn z98_cdecl_probe(x: i32) void;

pub fn main() void {
    var cb: Cb = z98_cdecl_probe;
    _ = cb;
}
