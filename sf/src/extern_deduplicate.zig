const sand_mod = @import("allocator.zig");
const Sand = sand_mod.Sand;
const lir_mod = @import("lir.zig");
const LirFunctionArrayList = lir_mod.LirFunctionArrayList;
const hash_mod = @import("util/hash.zig");

pub fn phase_ExternDeduplicate(lir_fns: *LirFunctionArrayList, alloc: *Sand) void {
    var seen = hash_mod.u32ToU32MapInit(alloc);
    var read: usize = @intCast(usize, 0);
    var write: usize = @intCast(usize, 0);
    var zero: u8 = @intCast(u8, 0);
    while (read < lir_fns.len) : (read += @intCast(usize, 1)) {
        if (lir_fns.items[read].is_extern != zero) {
            if (hash_mod.u32ToU32MapGet(&seen, lir_fns.items[read].name_id)) |_| {
                continue;
            }
            hash_mod.u32ToU32MapPut(&seen, lir_fns.items[read].name_id, @intCast(u32, 1));
        }
        if (write != read) {
            lir_fns.items[write] = lir_fns.items[read];
        }
        write += @intCast(usize, 1);
    }
    lir_fns.len = write;
}
