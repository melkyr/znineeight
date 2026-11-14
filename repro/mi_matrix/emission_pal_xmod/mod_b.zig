const mod_a = @import("mod_a.zig");
const pal_mod = @import("pal.zig");

pub fn resolveType(name_id: u32) u32 {
    var rdt_sv: []const u8 = "SVO\n";
    pal.markerWrite(rdt_sv);
    return mod_a.addOne(name_id);
}

pub fn lookupType(sym_type: u32) u32 {
    var u2n_m: []const u8 = "U2N:e";
    pal.markerWrite(u2n_m);
    return sym_type + mod_a.addOne(1);
}
