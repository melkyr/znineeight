// linuxdep.zig — Linux-only dependency module for iswindows_deadarm_*_xmod.
// Referenced ONLY from the non-`@isWindows()` arm of the fixture's main.zig.
// Symmetric twin of windep.zig: on an `-osw` (mingw) build the else arm is
// comptime-dead and never lowered, yet this module is still emitted — its
// `E!*void` return type is a cross-module type name that `pruneTypeMarkByValue`
// (`sf/src/main.zig:1149-1199`) marks owner-reachable (see NOTES.md
// "Mechanism") — and its `@cInclude("<sys/ioctl.h>")` breaks mingw gcc (the
// D2 defect is confirmed symmetric in the defect entry).
@cInclude("<sys/ioctl.h>");
pub const E = error{ OpenFailed };

var g: u32 = 0;

pub fn open(rate: u32, channels: u8) E!*void {
    if (rate == 0) return error.OpenFailed;
    _ = channels;
    return @ptrCast(*void, &g);
}
