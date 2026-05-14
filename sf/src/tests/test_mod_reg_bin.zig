const alloc_mod = @import("../allocator.zig");
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const mr_mod = @import("../module_registry.zig");
const pal_mod = @import("../pal.zig");

pub fn main() void {
    var buf: [65536]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var interner = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var diag = diag_mod.diagnosticCollectorInit(&a, &sm, &interner);

    var mr = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var id = mr_mod.moduleRegistryAddModule(&mr, 42);
    if (id != 0) { var s: []const u8 = "FAIL add\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var found = mr_mod.moduleRegistryGetOrCreateModule(&mr, 99);
    if (found != 1) { var s: []const u8 = "FAIL create\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var found2 = mr_mod.moduleRegistryGetOrCreateModule(&mr, 99);
    if (found2 != 1) { var s: []const u8 = "FAIL get\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var s: []const u8 = "ModuleRegistry tests passed.\n";
    pal_mod.stdout_write(s);
}
