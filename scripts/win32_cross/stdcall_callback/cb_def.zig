// Phase 3.5 Task 5 ABI evidence fixture: Z98-defined stdcall callbacks.
//
// `cb` is registered by the C host via CreateThread and invoked on a new
// thread; `cb2` is invoked directly through a stdcall function pointer. The
// generated definitions must carry Z98_STDCALL so i386 uses `ret $N`.
pub extern "stdcall" fn cb(x: u32) i32 {
    return @intCast(i32, x) + 1;
}

pub extern "stdcall" fn cb2(x: u32, y: u32) i32 {
    return @intCast(i32, x + y);
}
