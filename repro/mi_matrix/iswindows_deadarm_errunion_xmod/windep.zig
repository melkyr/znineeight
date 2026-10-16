// windep.zig — Windows-only dependency module for iswindows_deadarm_*_xmod.
// Referenced ONLY from the `@isWindows()` arm of the fixture's main.zig.
// The platform-only `@cInclude` is the D2 weaponization: when the
// comptime-dead arm still marks this module reachable, it is emitted into the
// output dir and its `@cInclude("<windows.h>")` breaks every non-mingw gcc.
// `open` returns an error union (the D2 trigger shape — a plain non-error-union
// reference in a dead arm is already pruned; see the D2 defect entry).
@cInclude("<windows.h>");
pub const E = error{ OpenFailed };

var g: u32 = 0;

pub fn open(rate: u32, channels: u8) E!*void {
    if (rate == 0) return error.OpenFailed;
    _ = channels;
    return @ptrCast(*void, &g);
}
