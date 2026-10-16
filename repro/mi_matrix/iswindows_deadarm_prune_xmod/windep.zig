// windep.zig — wrong-platform dependency module for iswindows_deadarm_prune_xmod
// (harmless variant: no platform-only `@cInclude`, so the fixture builds and
// runs on the host and its runtime golden is measurable PRE-FIX). Referenced
// only from the comptime-dead `@isWindows()` arm; `open` returns an error union
// (the D2 trigger). Emission contract: this module's `.c/.h` must NOT appear in
// the output dir of a non-Windows build after T3 (pre-fix it does — NOTES.md).
pub const E = error{ OpenFailed };

var g: u32 = 0;

pub fn open(rate: u32, channels: u8) E!*void {
    if (rate == 0) return error.OpenFailed;
    _ = channels;
    return @ptrCast(*void, &g);
}
