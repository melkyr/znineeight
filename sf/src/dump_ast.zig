const pal = @import("pal.zig");
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const ast_mod = @import("ast.zig");
const AstKind = ast_mod.AstKind;
const AstNode = ast_mod.AstNode;
const AstStore = ast_mod.AstStore;
const dh = @import("dump_helpers.zig");

fn astKindToString(kind: AstKind, buf: []u8) []u8 {
    var idx: usize = 0;
    switch (kind) {
        AstKind.err => { var s: []const u8 = "err"; dh.copyStr(buf, &idx, s); },
        AstKind.var_decl => { var s: []const u8 = "var_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.fn_decl => { var s: []const u8 = "fn_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.struct_decl => { var s: []const u8 = "struct_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.enum_decl => { var s: []const u8 = "enum_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.union_decl => { var s: []const u8 = "union_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.field_decl => { var s: []const u8 = "field_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.param_decl => { var s: []const u8 = "param_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.test_decl => { var s: []const u8 = "test_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.error_set_decl => { var s: []const u8 = "error_set_decl"; dh.copyStr(buf, &idx, s); },
        AstKind.int_literal => { var s: []const u8 = "int_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.float_literal => { var s: []const u8 = "float_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.string_literal => { var s: []const u8 = "string_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.char_literal => { var s: []const u8 = "char_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.bool_literal => { var s: []const u8 = "bool_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.null_literal => { var s: []const u8 = "null_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.undefined_literal => { var s: []const u8 = "undefined_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.unreachable_expr => { var s: []const u8 = "unreachable_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.enum_literal => { var s: []const u8 = "enum_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.error_literal => { var s: []const u8 = "error_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.tuple_literal => { var s: []const u8 = "tuple_literal"; dh.copyStr(buf, &idx, s); },
        AstKind.struct_init => { var s: []const u8 = "struct_init"; dh.copyStr(buf, &idx, s); },
        AstKind.array_init => { var s: []const u8 = "array_init"; dh.copyStr(buf, &idx, s); },
        AstKind.field_init => { var s: []const u8 = "field_init"; dh.copyStr(buf, &idx, s); },
        AstKind.ident_expr => { var s: []const u8 = "ident_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.field_access => { var s: []const u8 = "field_access"; dh.copyStr(buf, &idx, s); },
        AstKind.index_access => { var s: []const u8 = "index_access"; dh.copyStr(buf, &idx, s); },
        AstKind.slice_expr => { var s: []const u8 = "slice_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.deref => { var s: []const u8 = "deref"; dh.copyStr(buf, &idx, s); },
        AstKind.address_of => { var s: []const u8 = "address_of"; dh.copyStr(buf, &idx, s); },
        AstKind.fn_call => { var s: []const u8 = "fn_call"; dh.copyStr(buf, &idx, s); },
        AstKind.builtin_call => { var s: []const u8 = "builtin_call"; dh.copyStr(buf, &idx, s); },
        AstKind.paren_expr => { var s: []const u8 = "paren_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.add => { var s: []const u8 = "add"; dh.copyStr(buf, &idx, s); },
        AstKind.sub => { var s: []const u8 = "sub"; dh.copyStr(buf, &idx, s); },
        AstKind.mul => { var s: []const u8 = "mul"; dh.copyStr(buf, &idx, s); },
        AstKind.div => { var s: []const u8 = "div"; dh.copyStr(buf, &idx, s); },
        AstKind.mod_op => { var s: []const u8 = "mod_op"; dh.copyStr(buf, &idx, s); },
        AstKind.bit_and => { var s: []const u8 = "bit_and"; dh.copyStr(buf, &idx, s); },
        AstKind.bit_or => { var s: []const u8 = "bit_or"; dh.copyStr(buf, &idx, s); },
        AstKind.bit_xor => { var s: []const u8 = "bit_xor"; dh.copyStr(buf, &idx, s); },
        AstKind.shl => { var s: []const u8 = "shl"; dh.copyStr(buf, &idx, s); },
        AstKind.shr => { var s: []const u8 = "shr"; dh.copyStr(buf, &idx, s); },
        AstKind.bool_and => { var s: []const u8 = "bool_and"; dh.copyStr(buf, &idx, s); },
        AstKind.bool_or => { var s: []const u8 = "bool_or"; dh.copyStr(buf, &idx, s); },
        AstKind.cmp_eq => { var s: []const u8 = "cmp_eq"; dh.copyStr(buf, &idx, s); },
        AstKind.cmp_ne => { var s: []const u8 = "cmp_ne"; dh.copyStr(buf, &idx, s); },
        AstKind.cmp_lt => { var s: []const u8 = "cmp_lt"; dh.copyStr(buf, &idx, s); },
        AstKind.cmp_le => { var s: []const u8 = "cmp_le"; dh.copyStr(buf, &idx, s); },
        AstKind.cmp_gt => { var s: []const u8 = "cmp_gt"; dh.copyStr(buf, &idx, s); },
        AstKind.cmp_ge => { var s: []const u8 = "cmp_ge"; dh.copyStr(buf, &idx, s); },
        AstKind.assign => { var s: []const u8 = "assign"; dh.copyStr(buf, &idx, s); },
        AstKind.add_assign => { var s: []const u8 = "add_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.sub_assign => { var s: []const u8 = "sub_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.mul_assign => { var s: []const u8 = "mul_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.div_assign => { var s: []const u8 = "div_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.mod_assign => { var s: []const u8 = "mod_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.shl_assign => { var s: []const u8 = "shl_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.shr_assign => { var s: []const u8 = "shr_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.and_assign => { var s: []const u8 = "and_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.xor_assign => { var s: []const u8 = "xor_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.or_assign => { var s: []const u8 = "or_assign"; dh.copyStr(buf, &idx, s); },
        AstKind.negate => { var s: []const u8 = "negate"; dh.copyStr(buf, &idx, s); },
        AstKind.bool_not => { var s: []const u8 = "bool_not"; dh.copyStr(buf, &idx, s); },
        AstKind.bit_not => { var s: []const u8 = "bit_not"; dh.copyStr(buf, &idx, s); },
        AstKind.try_expr => { var s: []const u8 = "try_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.catch_expr => { var s: []const u8 = "catch_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.orelse_expr => { var s: []const u8 = "orelse_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.if_stmt => { var s: []const u8 = "if_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.if_expr => { var s: []const u8 = "if_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.if_capture => { var s: []const u8 = "if_capture"; dh.copyStr(buf, &idx, s); },
        AstKind.while_stmt => { var s: []const u8 = "while_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.while_capture => { var s: []const u8 = "while_capture"; dh.copyStr(buf, &idx, s); },
        AstKind.for_stmt => { var s: []const u8 = "for_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.switch_expr => { var s: []const u8 = "switch_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.switch_prong => { var s: []const u8 = "switch_prong"; dh.copyStr(buf, &idx, s); },
        AstKind.block => { var s: []const u8 = "block"; dh.copyStr(buf, &idx, s); },
        AstKind.return_stmt => { var s: []const u8 = "return_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.break_stmt => { var s: []const u8 = "break_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.continue_stmt => { var s: []const u8 = "continue_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.defer_stmt => { var s: []const u8 = "defer_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.errdefer_stmt => { var s: []const u8 = "errdefer_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.labeled_stmt => { var s: []const u8 = "labeled_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.expr_stmt => { var s: []const u8 = "expr_stmt"; dh.copyStr(buf, &idx, s); },
        AstKind.ptr_type => { var s: []const u8 = "ptr_type"; dh.copyStr(buf, &idx, s); },
        AstKind.many_ptr_type => { var s: []const u8 = "many_ptr_type"; dh.copyStr(buf, &idx, s); },
        AstKind.array_type => { var s: []const u8 = "array_type"; dh.copyStr(buf, &idx, s); },
        AstKind.slice_type => { var s: []const u8 = "slice_type"; dh.copyStr(buf, &idx, s); },
        AstKind.optional_type => { var s: []const u8 = "optional_type"; dh.copyStr(buf, &idx, s); },
        AstKind.error_union_type => { var s: []const u8 = "error_union_type"; dh.copyStr(buf, &idx, s); },
        AstKind.fn_type => { var s: []const u8 = "fn_type"; dh.copyStr(buf, &idx, s); },
        AstKind.import_expr => { var s: []const u8 = "import_expr"; dh.copyStr(buf, &idx, s); },
        AstKind.module_root => { var s: []const u8 = "module_root"; dh.copyStr(buf, &idx, s); },
        AstKind.payload_capture => { var s: []const u8 = "payload_capture"; dh.copyStr(buf, &idx, s); },
        AstKind.range_exclusive => { var s: []const u8 = "range_exclusive"; dh.copyStr(buf, &idx, s); },
        AstKind.range_inclusive => { var s: []const u8 = "range_inclusive"; dh.copyStr(buf, &idx, s); },
    }
    buf[idx] = 0;
    return buf[0..idx];
}
    buf[idx] = 0;
    return buf[0..idx];
}

fn nodeGetNameId(store: *AstStore, node: AstNode) u32 {
    switch (node.kind) {
        AstKind.var_decl => { return node.payload; },
        AstKind.field_decl => { return node.payload; },
        AstKind.param_decl => { return node.payload; },
        AstKind.field_access => { return node.payload; },
        AstKind.enum_literal => { return node.payload; },
        AstKind.error_literal => { return node.payload; },
        AstKind.labeled_stmt => { return node.payload; },
        AstKind.break_stmt => { return node.payload; },
        AstKind.continue_stmt => { return node.payload; },
        AstKind.if_capture => { return node.payload; },
        AstKind.while_capture => { return node.payload; },
        AstKind.for_stmt => { return node.payload; },
        AstKind.builtin_call => { return node.payload; },
        AstKind.import_expr => { return node.payload; },
        AstKind.fn_decl => {
            if (@intCast(usize, node.payload) < store.fn_protos.len) {
                return store.fn_protos.items[node.payload].name_id;
            }
            return @intCast(u32, 0);
        },
        else => { return @intCast(u32, 0); },
    }
}

pub fn dumpAst(store: *AstStore, root: u32, interner: *StringInterner) void {
    var st_idx: [512]u32 = undefined;
    var st_indent: [512]u32 = undefined;
    var st_state: [512]u8 = undefined;
    var sp: usize = 0;
    var s2: []const u8 = "  ";
    var spc: []const u8 = " ";
    var nl: []const u8 = "\n";
    var q: []const u8 = "\"";
    var op: []const u8 = "(";
    var cp: []const u8 = ")";
    var kind_buf: [32]u8 = undefined;
    var fmt_buf: [32]u8 = undefined;

    st_idx[sp] = root; st_indent[sp] = 0; st_state[sp] = 0; sp += 1;

    while (sp > 0) {
        sp -= 1;
        var idx = st_idx[sp];
        var indent = st_indent[sp];
        var is_post = st_state[sp];
        var node = store.nodes.items[idx];

        if (is_post != 0) {
            var ii: u32 = 0;
            while (ii < indent) { pal.stdout_write(s2); ii += 1; }
            pal.stdout_write(cp);
            pal.stdout_write(nl);
        } else {
            var ii: u32 = 0;
            while (ii < indent) { pal.stdout_write(s2); ii += 1; }
            var ks = astKindToString(node.kind, kind_buf[0..]);
            pal.stdout_write(op);
            pal.stdout_write(ks);

            var name_id = nodeGetNameId(store, node);
            if (name_id != 0) {
                pal.stdout_write(spc);
                pal.stdout_write(q);
                var name = interner_mod.stringInternerGet(interner, name_id);
                pal.stdout_write(name);
                pal.stdout_write(q);
            } else if (node.kind == AstKind.int_literal or node.kind == AstKind.char_literal) {
                if (@intCast(usize, node.payload) < store.int_values.len) {
                    var val = store.int_values.items[node.payload];
                    pal.stdout_write(spc);
                    var fs = dh.formatU64(val, fmt_buf[0..], 32);
                    pal.stdout_write(fs);
                }
            } else if (node.kind == AstKind.float_literal) {
                if (@intCast(usize, node.payload) < store.float_values.len) {
                    var val = store.float_values.items[node.payload];
                    pal.stdout_write(spc);
                    var fs = dh.formatF64(val, fmt_buf[0..], 32);
                    pal.stdout_write(fs);
                }
            } else if (node.kind == AstKind.string_literal) {
                if (@intCast(usize, node.payload) < store.string_values.len) {
                    var str_id = store.string_values.items[node.payload];
                    pal.stdout_write(spc);
                    pal.stdout_write(q);
                    var str_val = interner_mod.stringInternerGet(interner, str_id);
                    pal.stdout_write(str_val);
                    pal.stdout_write(q);
                }
            } else if (node.kind == AstKind.ident_expr) {
                if (@intCast(usize, node.payload) < store.identifiers.len) {
                    var id_val = store.identifiers.items[@intCast(usize, node.payload)];
                    pal.stdout_write(spc);
                    pal.stdout_write(q);
                    var id_str = interner_mod.stringInternerGet(interner, id_val);
                    pal.stdout_write(id_str);
                    pal.stdout_write(q);
                }
            } else if (node.kind == AstKind.bool_literal) {
                pal.stdout_write(spc);
                if (node.child_0 != 0) {
                    var ts: []const u8 = "true";
                    pal.stdout_write(ts);
                } else {
                    var fs: []const u8 = "false";
                    pal.stdout_write(fs);
                }
            } else if (node.kind == AstKind.null_literal) {
                pal.stdout_write(spc);
                var ns: []const u8 = "null";
                pal.stdout_write(ns);
            } else if (node.kind == AstKind.undefined_literal) {
                pal.stdout_write(spc);
                var us: []const u8 = "undefined";
                pal.stdout_write(us);
            } else if (node.kind == AstKind.unreachable_expr) {
                pal.stdout_write(spc);
                var us: []const u8 = "unreachable";
                pal.stdout_write(us);
            }

            if (node.flags != 0) {
                if ((node.flags & @intCast(u8, 0x02)) != 0) {
                    var ps: []const u8 = " pub=true";
                    pal.stdout_write(ps);
                }
                if ((node.flags & @intCast(u8, 0x01)) != 0) {
                    var cs: []const u8 = " const=true";
                    pal.stdout_write(cs);
                }
                if ((node.flags & @intCast(u8, 0x04)) != 0) {
                    var es: []const u8 = " extern=true";
                    pal.stdout_write(es);
                }
                if ((node.flags & @intCast(u8, 0x80)) != 0) {
                    var ms: []const u8 = " mutable=true";
                    pal.stdout_write(ms);
                }
                if ((node.flags & @intCast(u8, 0x08)) != 0) {
                    var es2: []const u8 = " export=true";
                    pal.stdout_write(es2);
                }
            }

            var has_children: u8 = 0;
            if (node.child_0 != 0 or node.child_1 != 0 or node.child_2 != 0) {
                has_children = 1;
            } else if (ast_mod.nodeHasExtraChildren(node.kind) and node.payload != 0) {
                var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
                if (ec.len > 0) has_children = 1;
            }

            if (has_children == 0) {
                pal.stdout_write(cp);
                pal.stdout_write(nl);
            } else {
                pal.stdout_write(nl);
                st_idx[sp] = idx; st_indent[sp] = indent; st_state[sp] = 1; sp += 1;
                if (node.child_2 != 0) { st_idx[sp] = node.child_2; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                if (node.child_1 != 0) { st_idx[sp] = node.child_1; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                if (node.child_0 != 0) { st_idx[sp] = node.child_0; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                if (ast_mod.nodeHasExtraChildren(node.kind) and node.payload != 0) {
                    var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
                    var ei: usize = 0;
                    while (ei < ec.len) {
                        var c = ec[ec.len - 1 - ei];
                        if (c != 0) { st_idx[sp] = c; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                        ei += 1;
                    }
                }
            }
        }
    }
}
