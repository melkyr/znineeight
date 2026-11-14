// D5/D10 fix-round-2 companion module: a cross-module extern declaration with
// a convention that disagrees with the definition in sibling_xmod_mismatch.zig
// (stdcall here, cdecl there). Must be rejected with 0 emitted `.c`.

pub extern "stdcall" fn xm_mismatch(x: u32) i32;

pub fn touch() u32 {
    return 1;
}
