// real.zig — the LIVE module selected by both conditional forms of
// conditional_import_lazy_xmod (C1b). `missing.zig` never exists: the dead
// arms reference it and must never load it.
const std = @import("std");

pub fn ping() void {
    std.io.write("real ping\n");
}
