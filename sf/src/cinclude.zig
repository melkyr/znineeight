const mr_mod = @import("module_registry.zig");
const ModuleRegistry = mr_mod.ModuleRegistry;
const Sand = @import("allocator.zig").Sand;
const ga_mod = @import("growable_array.zig");
const hash_mod = @import("util/hash.zig");

pub fn cincludeUnionAll(module_reg: *ModuleRegistry, alloc: *Sand) []u32 {
    var temp = ga_mod.u32ArrayListInit(alloc);
    var mods = mr_mod.moduleRegistryGetModules(module_reg);
    var hint: usize = @intCast(usize, 0);
    var hi: usize = @intCast(usize, 0);
    while (hi < mods.len) : (hi += @intCast(usize, 1)) {
        var m_incs_h = ga_mod.u32ArrayListGetSlice(&mods[hi].c_includes);
        hint += m_incs_h.len;
    }
    var seen = hash_mod.u32ToU32MapInitCap(alloc, hint);
    var mi: usize = @intCast(usize, 0);
    while (mi < mods.len) : (mi += @intCast(usize, 1)) {
        var m_incs = ga_mod.u32ArrayListGetSlice(&mods[mi].c_includes);
        var ci: usize = @intCast(usize, 0);
        while (ci < m_incs.len) : (ci += @intCast(usize, 1)) {
            var name_id = m_incs[ci];
            if (hash_mod.u32ToU32MapGet(&seen, name_id)) |_| {
                // skip duplicate
            } else {
                hash_mod.u32ToU32MapPut(&seen, name_id, @intCast(u32, 1));
                ga_mod.u32ArrayListAppend(&temp, name_id);
            }
        }
    }
    return ga_mod.u32ArrayListGetSlice(&temp);
}
