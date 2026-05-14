const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const mr_mod = @import("module_registry.zig");
const sym_mod = @import("symbol_table.zig");
const SymbolRegistry = sym_mod.SymbolRegistry;
const AstKind = @import("ast.zig").AstKind;
const ast_mod = @import("ast.zig");
const AstStore = @import("ast.zig").AstStore;
const type_mod = @import("type_registry.zig");
const TypeKind = type_mod.TypeKind;

fn registerDecl(sym_reg: *SymbolRegistry, type_reg: *type_mod.TypeRegistry, store: *AstStore, mod_id: u32, decl_idx: u32) void {
    var node = store.nodes.items[decl_idx];
    switch (node.kind) {
        AstKind.var_decl => {
            var name_id = node.payload;
            var sym = sym_mod.Symbol{
                .name_id = name_id,
                .type_id = @intCast(u32, 0),
                .kind = sym_mod.SymbolKind.global,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.fn_decl => {
            var proto = store.fn_protos.items[@intCast(usize, node.payload)];
            var sym = sym_mod.Symbol{
                .name_id = proto.name_id,
                .type_id = @intCast(u32, 0),
                .kind = sym_mod.SymbolKind.function,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.test_decl => {
            if (node.payload != 0) {
                var sym = sym_mod.Symbol{
                    .name_id = node.payload,
                    .type_id = @intCast(u32, 0),
                    .kind = sym_mod.SymbolKind.test_sym,
                    .flags = @intCast(u16, node.flags),
                    .decl_node = decl_idx,
                    .module_id = mod_id,
                    .scope_level = @intCast(u32, 0),
                };
                var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
                _ = sym_mod.symbolTableInsert(table, sym);
            }
        },
        AstKind.struct_decl, AstKind.enum_decl, AstKind.union_decl => {
            var name_id = node.payload;
            var type_kind: TypeKind = switch (node.kind) {
                AstKind.struct_decl => TypeKind.struct_type,
                AstKind.enum_decl => TypeKind.enum_type,
                AstKind.union_decl => if ((@intCast(u16, node.flags) & 1) != 0) TypeKind.tagged_union_type else TypeKind.union_type,
                else => TypeKind.void_type,
            };
            var tid = type_mod.typeRegistryRegisterNamedType(type_reg, mod_id, name_id, type_kind);
            var sym = sym_mod.Symbol{
                .name_id = name_id,
                .type_id = tid,
                .kind = sym_mod.SymbolKind.type_alias,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.error_set_decl => {
            var name_id = node.payload;
            var tid = type_mod.typeRegistryRegisterNamedType(type_reg, mod_id, name_id, TypeKind.error_set_type);
            var sym = sym_mod.Symbol{
                .name_id = name_id,
                .type_id = tid,
                .kind = sym_mod.SymbolKind.type_alias,
                .flags = @intCast(u16, node.flags),
                .decl_node = decl_idx,
                .module_id = mod_id,
                .scope_level = @intCast(u32, 0),
            };
            var table = sym_mod.symbolRegistryGetTable(sym_reg, mod_id);
            _ = sym_mod.symbolTableInsert(table, sym);
        },
        AstKind.import_expr => {},
        else => {},
    }
}

pub fn registerModuleSymbols(reg: *mr_mod.ModuleRegistry, sym_reg: *SymbolRegistry, type_reg: *type_mod.TypeRegistry, store: *AstStore, module_id: u32) void {
    var entry = reg.modules.items[@intCast(usize, module_id)];
    if (entry.state != mr_mod.ModuleState.resolved or entry.ast_root == 0) return;
    var root = store.nodes.items[@intCast(usize, entry.ast_root)];
    if (root.kind != AstKind.module_root) return;
    var decls = ast_mod.astStoreGetExtraChildren(store, root.payload);
    var i: usize = 0;
    while (i < decls.len) {
        registerDecl(sym_reg, type_reg, store, module_id, decls[i]);
        i += 1;
    }
}
