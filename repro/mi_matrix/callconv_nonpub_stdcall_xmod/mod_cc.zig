// callconv_nonpub_stdcall_xmod module — cross-module calling-convention
// registration for a NON-pub `extern "stdcall"` function.
//
// `cc_std` is deliberately NOT public: a non-pub cross-module symbol misses the
// `pub` fast path in `semanticAnalyzerResolveFieldAccess` and reaches the
// fn-type fallback that (before the fix) built the function type with
// convention 0 (cdecl) even though the declaration carries stdcall.
// `cc_cdecl` is the public default-cdecl counterpart of the same signature.
extern "stdcall" fn cc_std(x: i32) i32;
pub extern fn cc_cdecl(x: i32) i32;
