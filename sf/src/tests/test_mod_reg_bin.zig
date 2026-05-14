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

    var standalone_queue = mr_mod.importQueueInit(&a, &diag);

    mr_mod.importQueueEnqueue(&standalone_queue, 42);
    mr_mod.importQueueEnqueue(&standalone_queue, 99);
    mr_mod.importQueueEnqueue(&standalone_queue, 42);

    if (standalone_queue.pending_len != @intCast(usize, 2)) { var s: []const u8 = "FAIL dup\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (standalone_queue.pending_items[0] != 42) { var s: []const u8 = "FAIL item0\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (standalone_queue.pending_items[1] != 99) { var s: []const u8 = "FAIL item1\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var popped = mr_mod.importQueueDequeue(&standalone_queue);
    if (popped) |v| { if (v != 99) { var s: []const u8 = "FAIL deq\n"; pal_mod.stdout_write(s); pal_mod.exit(1); } } else { var s: []const u8 = "FAIL deq_null\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (standalone_queue.pending_len != @intCast(usize, 1)) { var s: []const u8 = "FAIL deq_len\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    if (mr.import_queue.pending_len != @intCast(usize, 0)) { var s: []const u8 = "FAIL reg_q_init\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    mr_mod.moduleRegistrySortModules(&mr);

    var m3 = mr_mod.moduleRegistryAddModule(&mr, 100);
    if (m3 != 2) { var s: []const u8 = "FAIL m3\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    mr_mod.moduleRegistryAddImport(&mr, 1, 0);
    mr_mod.moduleRegistryAddImport(&mr, 2, 0);
    mr_mod.moduleRegistryAddImport(&mr, 2, 1);

    mr_mod.moduleRegistrySortModules(&mr);

    if (mr.modules.items[0].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL m0_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr.modules.items[1].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL m1_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr.modules.items[2].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL m2_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var mr2 = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var c0 = mr_mod.moduleRegistryAddModule(&mr2, 10);
    var c1 = mr_mod.moduleRegistryAddModule(&mr2, 20);
    if (c0 != 0) { var s: []const u8 = "FAIL c0\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (c1 != 1) { var s: []const u8 = "FAIL c1\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    mr_mod.moduleRegistryAddImport(&mr2, 0, 1);
    mr_mod.moduleRegistryAddImport(&mr2, 1, 0);
    mr_mod.moduleRegistrySortModules(&mr2);
    if (mr2.modules.items[0].state != mr_mod.ModuleState.failed) { var s: []const u8 = "FAIL c0_cycle\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr2.modules.items[1].state != mr_mod.ModuleState.failed) { var s: []const u8 = "FAIL c1_cycle\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var s: []const u8 = "ModuleRegistry tests passed.\n";
    pal_mod.stdout_write(s);
}
