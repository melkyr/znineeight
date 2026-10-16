// linuxdep.zig — live-platform dependency module for iswindows_deadarm_prune_xmod
// (harmless variant). Referenced only from the live non-`@isWindows()` arm on a
// linux build; `open` returns an error union (the D2 trigger shape).
pub const E = error{ OpenFailed };

var g: u32 = 0;

pub fn open(rate: u32, channels: u8) E!*void {
    if (rate == 0) return error.OpenFailed;
    _ = channels;
    return @ptrCast(*void, &g);
}
