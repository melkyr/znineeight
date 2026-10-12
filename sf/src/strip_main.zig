const pal = @import("pal.zig");
const NameMangler = @import("name_mangler.zig").NameMangler;
const nameManglerInit = @import("name_mangler.zig").nameManglerInit;

pub fn main() void {
    var nm = nameManglerInit();
    _ = nm;
    pal.stderr_write("zig1\n");
}
