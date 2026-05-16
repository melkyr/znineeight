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

    var mr3 = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var x0 = mr_mod.moduleRegistryAddModule(&mr3, 100);
    var x1 = mr_mod.moduleRegistryAddModule(&mr3, 200);
    var x2 = mr_mod.moduleRegistryAddModule(&mr3, 300);
    mr_mod.moduleRegistryAddImport(&mr3, 0, 1);
    mr_mod.moduleRegistryAddImport(&mr3, 1, 2);
    mr_mod.moduleRegistryAddImport(&mr3, 2, 0);
    mr_mod.moduleRegistrySortModules(&mr3);
    _ = x0; _ = x1; _ = x2;
    if (mr3.modules.items[0].state != mr_mod.ModuleState.failed) { var s: []const u8 = "FAIL i0_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr3.modules.items[1].state != mr_mod.ModuleState.failed) { var s: []const u8 = "FAIL i1_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr3.modules.items[2].state != mr_mod.ModuleState.failed) { var s: []const u8 = "FAIL i2_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var mr4 = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var s0 = mr_mod.moduleRegistryAddModule(&mr4, 1000);
    var s1 = mr_mod.moduleRegistryAddModule(&mr4, 2000);
    var s2 = mr_mod.moduleRegistryAddModule(&mr4, 3000);
    mr_mod.moduleRegistryAddImport(&mr4, 1, 0);
    mr_mod.moduleRegistryAddImport(&mr4, 2, 1);
    mr_mod.moduleRegistrySortModules(&mr4);
    if (mr4.modules.items[0].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL s0_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr4.modules.items[1].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL s1_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr4.modules.items[2].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL s2_state\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr4.modules.items[@intCast(usize, s0)].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL s0_orig\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr4.modules.items[@intCast(usize, s1)].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL s1_orig\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (mr4.modules.items[@intCast(usize, s2)].state != mr_mod.ModuleState.resolved) { var s: []const u8 = "FAIL s2_orig\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var da = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var db = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var d0a = mr_mod.moduleRegistryAddModule(&da, 100); var d0b = mr_mod.moduleRegistryAddModule(&db, 100);
    var d1a = mr_mod.moduleRegistryAddModule(&da, 200); var d1b = mr_mod.moduleRegistryAddModule(&db, 200);
    var d2a = mr_mod.moduleRegistryAddModule(&da, 300); var d2b = mr_mod.moduleRegistryAddModule(&db, 300);
    if (d0a != d0b or d1a != d1b or d2a != d2b) { var s: []const u8 = "FAIL det_id\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (da.modules.items[@intCast(usize, d0a)].path_id != db.modules.items[@intCast(usize, d0b)].path_id) { var s: []const u8 = "FAIL det_path\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
    if (da.modules.items[@intCast(usize, d1a)].path_id != db.modules.items[@intCast(usize, d1b)].path_id) { var s: []const u8 = "FAIL det_path2\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }

    var sc_a = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var sc_b = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    _ = mr_mod.moduleRegistryAddModule(&sc_a, 10); _ = mr_mod.moduleRegistryAddModule(&sc_b, 10);
    _ = mr_mod.moduleRegistryAddModule(&sc_a, 20); _ = mr_mod.moduleRegistryAddModule(&sc_b, 20);
    _ = mr_mod.moduleRegistryAddModule(&sc_a, 30); _ = mr_mod.moduleRegistryAddModule(&sc_b, 30);
    mr_mod.moduleRegistryAddImport(&sc_a, 1, 0); mr_mod.moduleRegistryAddImport(&sc_b, 1, 0);
    mr_mod.moduleRegistryAddImport(&sc_a, 2, 1); mr_mod.moduleRegistryAddImport(&sc_b, 2, 1);
    mr_mod.moduleRegistrySortModules(&sc_a);
    mr_mod.moduleRegistrySortModules(&sc_b);
    var si: usize = 0;
    while (si < @intCast(usize, 3)) {
        if (sc_a.modules.items[si].state != sc_b.modules.items[si].state) { var s: []const u8 = "FAIL det_sort\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
        if (sc_a.modules.items[si].id != sc_b.modules.items[si].id) { var s: []const u8 = "FAIL det_sort_id\n"; pal_mod.stdout_write(s); pal_mod.exit(1); }
        si += 1;
    }

    var s: []const u8 = "ModuleRegistry tests passed.\n";
    pal_mod.stdout_write(s);
}
