const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const ResolvedTypeTable = @import("resolved_type_table.zig").ResolvedTypeTable;
const ast_mod = @import("ast.zig");
const type_mod = @import("type_registry.zig");
const diag_mod = @import("diagnostics.zig");
const rtt_mod = @import("resolved_type_table.zig");

pub fn checkReturnType(store: *AstStore, reg: *TypeRegistry, diag: *DiagnosticCollector, node_idx: u32, return_expr_type: u32, current_fn_return: u32) void {
    var node = store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind != AstKind.return_stmt) return;
    if (node.child_0 == @intCast(u32, 0)) {
        if (current_fn_return != type_mod.TYPE_VOID and current_fn_return != type_mod.TYPE_NORETURN) {
            var msg: []const u8 = "return with no value";
            diag_mod.diagnosticCollectorAdd(diag, @intCast(u8, 0), @intCast(u16, 0),
                @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
        }
    } else {
        if (return_expr_type == @intCast(u32, 0)) return;
        if (!type_mod.typeRegistryIsAssignable(reg, return_expr_type, current_fn_return)) {
            var msg: []const u8 = "return type mismatch";
            diag_mod.diagnosticCollectorAdd(diag, @intCast(u8, 0), @intCast(u16, 0),
                @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
        }
    }
}

pub fn checkSwitchExhaust(store: *AstStore, reg: *TypeRegistry, diag: *DiagnosticCollector, rtt: *ResolvedTypeTable, node_idx: u32) void {
    var node = store.nodes.items[@intCast(usize, node_idx)];
    if (node.child_0 == @intCast(u32, 0)) return;
    var cond_tid = rtt_mod.resolvedTypeTableGet(rtt, node.child_0);
    if (cond_tid) |tid| {
        if (tid == type_mod.TYPE_VOID or tid == @intCast(u32, 0)) return;
        var ty = reg.types_items[@intCast(usize, tid)];
        if (ty.kind != type_mod.TypeKind.enum_type and ty.kind != type_mod.TypeKind.tagged_union_type) return;
        if (node.payload == @intCast(u32, 0)) return;
        var member_count: u16 = 0;
        if (ty.kind == type_mod.TypeKind.enum_type) {
            var ep = reg.en_items[@intCast(usize, ty.payload_idx)];
            member_count = ep.members_count;
        } else {
            var tp = reg.tu_items[@intCast(usize, ty.payload_idx)];
            member_count = tp.fields_count;
        }
        var prongs = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var covered_count: u16 = 0;
        var has_else: u8 = 0;
        var pi: usize = 0;
        while (pi < prongs.len) : (pi += 1) {
            var prong = store.nodes.items[@intCast(usize, prongs[pi])];
            if ((prong.flags & @intCast(u8, 1)) != @intCast(u8, 0)) { has_else = 1; } else {
                if (prong.payload != @intCast(u32, 0)) {
                    var items = ast_mod.astStoreGetExtraChildren(store, prong.payload);
                    var count: u16 = @intCast(u16, items.len);
                    covered_count += count;
                }
            }
        }
        if (has_else == @intCast(u8, 0) and covered_count < member_count) {
            var msg: []const u8 = "switch not exhaustive";
            diag_mod.diagnosticCollectorAdd(diag, @intCast(u8, 0),
                @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3004_SWITCH_NOT_EXHAUSTIVE)),
                @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
        }
    }
}

pub fn constraintCheckerCheckBreakContinue(store: *AstStore, diag: *DiagnosticCollector, root_idx: u32) void {
    if (root_idx == @intCast(u32, 0)) return;
    var stack_n: [512]u32 = undefined;
    var stack_d: [512]u8 = undefined;
    var sp: usize = @intCast(usize, 0);
    stack_n[sp] = root_idx;
    stack_d[sp] = @intCast(u8, 0);
    sp += 1;
    while (sp > @intCast(usize, 0)) {
        sp -= 1;
        var n: u32 = stack_n[sp];
        var depth: u8 = stack_d[sp];
        var node = store.nodes.items[@intCast(usize, n)];
        var nd: u8 = depth;
        if (node.kind == AstKind.while_stmt or node.kind == AstKind.for_stmt) nd += 1;
        if (node.kind == AstKind.break_stmt or node.kind == AstKind.continue_stmt) {
            if (depth == @intCast(u8, 0)) {
                var msg: []const u8 = "break/continue outside loop";
                diag_mod.diagnosticCollectorAdd(diag, @intCast(u8, 0), @intCast(u16, 0),
                    @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
            }
            if (node.child_0 != @intCast(u32, 0)) { stack_n[sp] = node.child_0; stack_d[sp] = nd; sp += 1; }
            if (node.child_1 != @intCast(u32, 0)) { stack_n[sp] = node.child_1; stack_d[sp] = nd; sp += 1; }
            if (node.child_2 != @intCast(u32, 0)) { stack_n[sp] = node.child_2; stack_d[sp] = nd; sp += 1; }
            if (node.payload != @intCast(u32, 0)) {
                var extra = ast_mod.astStoreGetExtraChildren(store, node.payload);
                var ei: usize = 0;
                while (ei < extra.len) : (ei += 1) { stack_n[sp] = extra[ei]; stack_d[sp] = nd; sp += 1; }
            }
            continue;
        }
        if (node.child_0 != @intCast(u32, 0)) { stack_n[sp] = node.child_0; stack_d[sp] = nd; sp += 1; }
        if (node.child_1 != @intCast(u32, 0)) { stack_n[sp] = node.child_1; stack_d[sp] = nd; sp += 1; }
        if (node.child_2 != @intCast(u32, 0)) { stack_n[sp] = node.child_2; stack_d[sp] = nd; sp += 1; }
        if (node.payload != @intCast(u32, 0)) {
            var extra = ast_mod.astStoreGetExtraChildren(store, node.payload);
            var ei: usize = 0;
            while (ei < extra.len) : (ei += 1) { stack_n[sp] = extra[ei]; stack_d[sp] = nd; sp += 1; }
        }
    }
}
