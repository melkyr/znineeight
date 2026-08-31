const pal = @import("pal.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeKind = @import("type_registry.zig").TypeKind;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const diag_mod = @import("diagnostics.zig");
const LirInst = @import("lir.zig").LirInst;
const SwitchCaseArrayList = @import("lir.zig").SwitchCaseArrayList;
const U32ArrayList = @import("growable_array.zig").U32ArrayList;
const U64ToU32Map = @import("util/hash.zig").U64ToU32Map;
const U32ToU32Map = @import("util/hash.zig").U32ToU32Map;
const alloc_mod = @import("allocator.zig");
const Sand = @import("allocator.zig").Sand;
const hash_mod = @import("util/hash.zig");
const interner_mod = @import("string_interner.zig");
const type_mod = @import("type_registry.zig");
const mr_mod = @import("module_registry.zig");

const type_resolver = @import("type_resolver.zig");
const itoa_mod = @import("util/itoa.zig");
const format_mod = @import("util/format.zig");
const mem_mod = @import("util/mem.zig");
const TypeResolver = type_resolver.TypeResolver;
const sym_reg = @import("symbol_registrator.zig");
const lir_mod = @import("lir.zig");
const LirFunction = @import("lir.zig").LirFunction;
const LirParam = @import("lir.zig").LirParam;
const lir_stream_mod = @import("lir_stream.zig");

pub const BufferedWriter = struct {
    buf: [4096]u8,
    pos: usize,
    fd: usize,
};

pub fn bufferedWriterInit() BufferedWriter {
    return BufferedWriter{ .buf = undefined, .pos = @intCast(usize, 0), .fd = @intCast(usize, 1) };
}

pub fn bufferedWriterInitFd(fd: usize) BufferedWriter {
    return BufferedWriter{ .buf = undefined, .pos = @intCast(usize, 0), .fd = fd };
}

pub fn bufferedWriterFlush(self: *BufferedWriter) void {
    if (self.pos == @intCast(usize, 0)) return;
    var fp_m: []const u8 = "FL:p"; pal.markerWriteInt(fp_m, @intCast(u32, self.pos));
    pal.fileWrite(self.fd, self.buf[0..self.pos]);
    self.pos = @intCast(usize, 0);
    var fe_m: []const u8 = "FE:p"; pal.measureMarkerWriteInt(fe_m, @intCast(u32, self.pos));
}

 pub fn bufferedWriterWrite(self: *BufferedWriter, data: []const u8) void {
    var remaining = data;
    while (remaining.len > @intCast(usize, 0)) {
        var space = 4096 - self.pos;
        var copy_len = if (remaining.len < space) remaining.len else space;
        var i: usize = @intCast(usize, 0);
        while (i < copy_len) : (i += @intCast(usize, 1)) {
            self.buf[self.pos + i] = remaining[i];
        }
        self.pos += copy_len;
        remaining = remaining[copy_len..];
        if (self.pos == 4096) bufferedWriterFlush(self);
    }
}

pub fn bufferedWriterWriteByte(self: *BufferedWriter, byte: u8) void {
    if (self.pos == 4096) bufferedWriterFlush(self);
    self.buf[self.pos] = byte;
    self.pos += @intCast(usize, 1);
}

pub fn bufferedWriterWriteIndent(self: *BufferedWriter, level: u32) void {
    var total: u32 = level * @intCast(u32, 4);
    var i: u32 = @intCast(u32, 0);
    while (i < total) : (i += @intCast(u32, 1)) {
    if (self.pos == 4096) bufferedWriterFlush(self);
        self.buf[self.pos] = @intCast(u8, ' ');
        self.pos += @intCast(usize, 1);
    }
}

fn dbgPrintU32(val: u32) void {
    var buf: [20]u8 = undefined;
    var len = itoa_mod.itoa(val, buf[0..]);
    var sbase: usize = @intCast(usize, 19) - @intCast(usize, len);
    var send: usize = @intCast(usize, 19);
    pal.markerWrite(buf[sbase .. send]);
}

pub const NameMangler = struct {
    hash_seed: u32,
    cache: U64ToU32Map,
    keyword_set: U32ToU32Map,
    collision_mod: U32ToU32Map,
    collision_name: U32ToU32Map,
    interner: *StringInterner,
};

fn writeHex(buf: []u8, pos: *usize, value: u32) void {
    var v = value;
    var hex_buf: [8]u8 = undefined;
    var i: u32 = @intCast(u32, 8);
    while (i > @intCast(u32, 0)) {
        i -= @intCast(u32, 1);
        var nibble = v & @intCast(u32, 0xF);
        if (nibble < @intCast(u32, 10)) {
            hex_buf[@intCast(usize, i)] = @intCast(u8, '0') + @intCast(u8, nibble);
        } else {
            hex_buf[@intCast(usize, i)] = @intCast(u8, 'A') + @intCast(u8, nibble - @intCast(u32, 10));
        }
        v = v >> @intCast(u32, 4);
    }
    var j: usize = @intCast(usize, 0);
    while (j < @intCast(usize, 8)) : (j += @intCast(usize, 1)) {
        buf[@intCast(usize, pos.*) + j] = hex_buf[j];
    }
    pos.* += @intCast(usize, 8);
}

fn isTempOrBuiltin(name: []const u8) u8 {
    if (name.len < @intCast(usize, 5)) return @intCast(u8, 0);
    if (name[0] != '_' or name[1] != '_') return @intCast(u8, 0);
    if (name[2] == 't' and name[3] == 'm' and name[4] == 'p') return @intCast(u8, 1);
    if (name[2] == 'r' and name[3] == 'e' and name[4] == 't') return @intCast(u8, 1);
    if (name.len >= @intCast(usize, 11) and name[2] == 'b' and name[3] == 'o' and name[4] == 'o' and
        name[5] == 't' and name[6] == 's' and name[7] == 't' and name[8] == 'r' and name[9] == 'a' and name[10] == 'p') {
        return @intCast(u8, 1);
    }
    return @intCast(u8, 0);
}

fn isC89Keyword(self: *NameMangler, name_id: u32) u8 {
    if (hash_mod.u32ToU32MapGet(&self.keyword_set, name_id)) |_| return @intCast(u8, 1);
    return @intCast(u8, 0);
}

fn isBasePtrToArray(emitter: *C89Emitter, base_temp: u32) u8 {
    var hs = emitter.current_fn.hoisted_temps;
    var ht = hs.items[@intCast(usize, base_temp)];
    var btid = ht.type_id;
    var bty = emitter.registry.types_items[@intCast(usize, btid)];
    if (bty.kind != type_mod.TypeKind.ptr_type and bty.kind != type_mod.TypeKind.many_ptr_type) return @intCast(u8, 0);
    var pointee = emitter.registry.ptr_items[@intCast(usize, bty.payload_idx)].base;
    var pty = emitter.registry.types_items[@intCast(usize, pointee)];
    if (pty.kind == type_mod.TypeKind.array_type) return @intCast(u8, 1);
    return @intCast(u8, 0);
}

// I/F-GLOBVAR: a module-level `var` array must never be lowered to a stack temp that
// copies the whole global. When the emitted C89 array temp would exceed this many bytes,
// the load_global result temp is aliased straight to the global (resolveTempName -> global
// name) and neither the stack declaration nor the dead copy loop is emitted. 2 MiB is a safe
// ceiling for any single stack frame; the only currently-GREEN programs carrying module-level
// var arrays (mud [2]Room, lisp [131072]u64) stay below it, so byte-identity is preserved.
const GLOBVAR_MAX_STACK_ARRAY_BYTES: u64 = 2097152;

fn globvarTypeScalarSize(emitter: *C89Emitter, tid: u32) u64 {
    if (tid == type_mod.TYPE_U8 or tid == type_mod.TYPE_I8 or tid == type_mod.TYPE_BOOL or tid == type_mod.TYPE_C_CHAR) return @intCast(u64, 1);
    if (tid == type_mod.TYPE_U16 or tid == type_mod.TYPE_I16) return @intCast(u64, 2);
    if (tid == type_mod.TYPE_U32 or tid == type_mod.TYPE_I32 or tid == type_mod.TYPE_F32 or tid == type_mod.TYPE_USIZE or tid == type_mod.TYPE_ISIZE) return @intCast(u64, 4);
    if (tid == type_mod.TYPE_U64 or tid == type_mod.TYPE_I64 or tid == type_mod.TYPE_F64) return @intCast(u64, 8);
    if (@intCast(usize, tid) >= emitter.registry.types_len) return @intCast(u64, 1);
    var gv_ty = emitter.registry.types_items[@intCast(usize, tid)];
    var gv_k = gv_ty.kind;
    if (gv_k == type_mod.TypeKind.ptr_type or gv_k == type_mod.TypeKind.many_ptr_type or gv_k == type_mod.TypeKind.slice_type or gv_k == type_mod.TypeKind.fn_type) return @intCast(u64, 4);
    if (gv_k == type_mod.TypeKind.array_type) {
        var gv_ap = emitter.registry.array_items[@intCast(usize, gv_ty.payload_idx)];
        return @intCast(u64, gv_ap.length) * globvarTypeScalarSize(emitter, gv_ap.elem);
    }
    if (gv_ty.size != @intCast(u32, 0)) return @intCast(u64, gv_ty.size);
    return @intCast(u64, 1);
}

fn isLargeModuleVarArrayType(emitter: *C89Emitter, tid: u32) bool {
    if (tid == type_mod.TYPE_UNDEFINED) return false;
    if (@intCast(usize, tid) >= emitter.registry.types_len) return false;
    var gv_ty = emitter.registry.types_items[@intCast(usize, tid)];
    if (gv_ty.kind != type_mod.TypeKind.array_type) return false;
    return globvarTypeScalarSize(emitter, tid) > GLOBVAR_MAX_STACK_ARRAY_BYTES;
}

/// Emit indexed access in C89: `base[idx]` or `(*base)[idx]` depending on whether base is ptr-to-array.
/// kind: 0 = load (emit result = X;), 1 = assign (emit X = src;)
fn emitBaseIdxAccess(emitter: *C89Emitter, base_temp: u32, idx_temp: u32, name_or_src: []const u8, kind: u8) void {
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var base_name = resolveTempName(emitter, base_temp);
    var idx_name = resolveTempName(emitter, idx_temp);
    var is_ptr_arr = isBasePtrToArray(emitter, base_temp);
    if (kind == @intCast(u8, 0)) {
        // load: result = (*base)[idx]; or result = base[idx];
        bufferedWriterWrite(&emitter.writer, name_or_src);   // result name
        var eq: []const u8 = " = ";
        bufferedWriterWrite(&emitter.writer, eq);
        if (is_ptr_arr == @intCast(u8, 1)) {
            var lp: []const u8 = "(*";  bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, base_name);
            var rp: []const u8 = ")["; bufferedWriterWrite(&emitter.writer, rp);
        } else {
            bufferedWriterWrite(&emitter.writer, base_name);
            var lb: []const u8 = "[";   bufferedWriterWrite(&emitter.writer, lb);
        }
        bufferedWriterWrite(&emitter.writer, idx_name);
        var rc: []const u8 = "];\n";    bufferedWriterWrite(&emitter.writer, rc);
    } else {
        // assign: (*base)[idx] = src; or base[idx] = src;
        if (is_ptr_arr == @intCast(u8, 1)) {
            var lp2: []const u8 = "(*"; bufferedWriterWrite(&emitter.writer, lp2);
            bufferedWriterWrite(&emitter.writer, base_name);
            var rp2: []const u8 = ")["; bufferedWriterWrite(&emitter.writer, rp2);
        } else {
            bufferedWriterWrite(&emitter.writer, base_name);
            var lb2: []const u8 = "[";  bufferedWriterWrite(&emitter.writer, lb2);
        }
        bufferedWriterWrite(&emitter.writer, idx_name);
        var eq2: []const u8 = "] = ";   bufferedWriterWrite(&emitter.writer, eq2);
        bufferedWriterWrite(&emitter.writer, name_or_src);   // src name
        var sc: []const u8 = ";\n";     bufferedWriterWrite(&emitter.writer, sc);
    }
}

fn emitFieldAssign(writer: *BufferedWriter, indent_val: u32, registry: *TypeRegistry, mangler: *NameMangler, interner: *StringInterner, current_fn: *LirFunction, hoisted_temps_items: [*]lir_mod.TempDecl, hoisted_temps_len: usize, base: []const u8, base_temp: u32, field_id: u32, src: []const u8, src_temp: u32, emitter2: *C89Emitter) void {
    var fn_prefix: []const u8 = ".f_";
    var found: u8 = @intCast(u8, 0);
    var is_arr: [1]u32 = [1]u32{@intCast(u32, 0)};
    var arr_len: [1]u32 = [1]u32{@intCast(u32, 0)};
    var cast_name: []const u8 = "";
    var fld_name_val: []const u8 = fn_prefix;
    var tj: usize = @intCast(usize, 0);
    while (tj < hoisted_temps_len) : (tj += @intCast(usize, 1)) {
        var ht: lir_mod.TempDecl = hoisted_temps_items[tj];
        if (ht.temp_id == base_temp) {
            if (ht.type_id != type_mod.TYPE_UNDEFINED) {
                var bty: type_mod.Type = registry.types_items[@intCast(usize, ht.type_id)];
                if (bty.kind == TypeKind.slice_type) {
                    if (field_id == type_mod.SLICE_FIELD_PTR) { var pn: []const u8 = ".ptr"; fn_prefix = pn; found = @intCast(u8, 1); var sl_elem = registry.slice_items[@intCast(usize, bty.payload_idx)].elem; cast_name = ptrCTypeNameFromElem(registry, mangler, sl_elem); }
                    else if (field_id == type_mod.SLICE_FIELD_LEN) { var pn: []const u8 = ".len"; fn_prefix = pn; found = @intCast(u8, 1); }
                } else if (bty.kind == TypeKind.tagged_union_type) {
                    if (field_id == type_mod.TU_FIELD_TAG) { var pn: []const u8 = ".tag"; fn_prefix = pn; found = @intCast(u8, 1); }
                    else if (field_id == type_mod.TU_FIELD_PAYLOAD) {
                        var af_src_ty: u32 = @intCast(u32, 0xFFFFFFFF);
                        var af_stj: usize = @intCast(usize, 0);
                        while (af_stj < hoisted_temps_len) : (af_stj += @intCast(usize, 1)) {
                            var af_sht: lir_mod.TempDecl = hoisted_temps_items[af_stj];
                            if (af_sht.temp_id == src_temp) { af_src_ty = af_sht.type_id; }
                        }
                        var af_vfound: u8 = @intCast(u8, 0);
                        if (af_src_ty != @intCast(u32, 0xFFFFFFFF) and af_src_ty != type_mod.TYPE_VOID) {
                            var af_tp = registry.tu_items[@intCast(usize, bty.payload_idx)];
                            var af_vfi: usize = @intCast(usize, 0);
                            while (af_vfi < @intCast(usize, af_tp.fields_count) and af_vfound == @intCast(u8, 0)) : (af_vfi += @intCast(usize, 1)) {
                                var af_vfe = registry.fe_items[@intCast(usize, af_tp.fields_start) + af_vfi];
                                if (af_vfe.type_id == af_src_ty) {
                                    af_vfound = @intCast(u8, 1);
                                    var af_pld: []const u8 = ".payload."; bufferedWriterWrite(writer, af_pld);
                                    var af_vname = interner_mod.stringInternerGet(interner, af_vfe.name_id);
                                    bufferedWriterWrite(writer, af_vname);
                                    var af_dot: []const u8 = "._"; bufferedWriterWrite(writer, af_dot);
                                    var af_sfe_idx: u32 = @intCast(u32, 0);
                                    if (hash_mod.u32ToU32MapGet(&current_fn.temp_variant_sub_field, src_temp)) |svi| { af_sfe_idx = svi; }
                                    var af_sfib: [10]u8 = undefined; var af_sfil = itoa_mod.itoa(af_sfe_idx, af_sfib[0..]); var af_sfis: usize = @intCast(usize, 9) - @intCast(usize, af_sfil); bufferedWriterWrite(writer, af_sfib[af_sfis..@intCast(usize, 9)]);
                                    var af_empty: []const u8 = ""; fn_prefix = af_empty; found = @intCast(u8, 1);
                                }
                            }
                        }
                        if (af_vfound == @intCast(u8, 0)) { var pn: []const u8 = ".payload"; fn_prefix = pn; found = @intCast(u8, 1); }
                    }
                } else if (bty.kind == TypeKind.ptr_type or bty.kind == TypeKind.many_ptr_type) {
                    var pointee = registry.ptr_items[@intCast(usize, bty.payload_idx)].base;
                    var pty = registry.types_items[@intCast(usize, pointee)];
                    if (pty.kind == TypeKind.struct_type) {
                        var arrow_s: []const u8 = "->";
                        bufferedWriterWrite(writer, arrow_s);
                        var pst = registry.st_items[@intCast(usize, pty.payload_idx)];
                        var fe = registry.fe_items[@intCast(usize, pst.fields_start) + @intCast(usize, field_id)];
                        var pn2: []const u8 = interner_mod.stringInternerGet(interner, fe.name_id);
                        fn_prefix = pn2;
                        fld_name_val = pn2;
                        found = @intCast(u8, 1);
                    }
                } else if (bty.kind == TypeKind.struct_type) {
                    var dot_s: []const u8 = ".";
                    bufferedWriterWrite(writer, dot_s);
                    var fe: type_mod.FieldEntry = registry.fe_items[@intCast(usize, registry.st_items[@intCast(usize, bty.payload_idx)].fields_start) + @intCast(usize, field_id)];
                    var pn: []const u8 = interner_mod.stringInternerGet(interner, fe.name_id);
                    fn_prefix = pn;
                    fld_name_val = pn;
                    found = @intCast(u8, 1);
                    if (typeIsPtrKind(registry, fe.type_id) != @intCast(u8, 0)) { cast_name = getCTypeName(registry, mangler, fe.type_id); }
                    var af_fety: type_mod.Type = registry.types_items[@intCast(usize, fe.type_id)];
                    if (af_fety.kind == TypeKind.array_type) {
                        var afap: type_mod.ArrayPayload = registry.array_items[@intCast(usize, af_fety.payload_idx)];
                        is_arr[0] = @intCast(u32, 1);
                        arr_len[0] = afap.length;
                    }
                } else if (bty.kind == TypeKind.union_type) {
                    var dot_s: []const u8 = ".";
                    bufferedWriterWrite(writer, dot_s);
                    var fe: type_mod.FieldEntry = registry.fe_items[@intCast(usize, registry.un_items[@intCast(usize, bty.payload_idx)].fields_start) + @intCast(usize, field_id)];
                    var pn: []const u8 = interner_mod.stringInternerGet(interner, fe.name_id);
                    fn_prefix = pn;
                    fld_name_val = pn;
                    found = @intCast(u8, 1);
                    if (typeIsPtrKind(registry, fe.type_id) != @intCast(u8, 0)) { cast_name = getCTypeName(registry, mangler, fe.type_id); }
                    var af_fety: type_mod.Type = registry.types_items[@intCast(usize, fe.type_id)];
                    if (af_fety.kind == TypeKind.array_type) {
                        var afap: type_mod.ArrayPayload = registry.array_items[@intCast(usize, af_fety.payload_idx)];
                        is_arr[0] = @intCast(u32, 1);
                        arr_len[0] = afap.length;
                    }
                }
            }
            break;
        }
    }
    if (found == @intCast(u8, 0)) {
        bufferedWriterWrite(writer, fn_prefix);
        var fb: [16]u8 = undefined;
        var fl: u32 = itoa_mod.itoa(field_id, fb[0..]);
        var fn_idx: u32 = @intCast(u32, @intCast(u32, 15) - fl);
        var fn_start: usize = @intCast(usize, fn_idx);
        var fn_end: usize = @intCast(usize, 15);
        bufferedWriterWrite(writer, fb[fn_start..fn_end]);
    } else {
        bufferedWriterWrite(writer, fn_prefix);
    }
    if (is_arr[0] != @intCast(u32, 0)) {
        var afsemi: []const u8 = ";\n"; bufferedWriterWrite(writer, afsemi);
        bufferedWriterWriteIndent(writer, indent_val);
        var afblk: []const u8 = "{\n"; bufferedWriterWrite(writer, afblk);
        var afli: []const u8 = "    unsigned int _j = 0;\n"; bufferedWriterWrite(writer, afli);
        var aflw: []const u8 = "    while (_j < "; bufferedWriterWrite(writer, aflw);
        var afalb: [20]u8 = undefined; var afall: u32 = itoa_mod.itoa(arr_len[0], afalb[0..]); var afals: usize = @intCast(usize, 19) - @intCast(usize, afall); bufferedWriterWrite(writer, afalb[afals..@intCast(usize, 19)]);
        var aflb2: []const u8 = ") {\n        "; bufferedWriterWrite(writer, aflb2);
        bufferedWriterWrite(writer, base);
        var dot_s2: []const u8 = "."; bufferedWriterWrite(writer, dot_s2);
        bufferedWriterWrite(writer, fld_name_val);
        var aflb3: []const u8 = "[_j] = 0;\n        _j++;\n    }\n}\n"; bufferedWriterWrite(writer, aflb3);
    } else {
        var fa_cast: []const u8 = "";
        if (cast_name.len != @intCast(usize, 0)) {
            var fa_src_ty: u32 = @intCast(u32, 0xFFFFFFFF);
            var fa_ssg: u8 = @intCast(u8, 0);
            if (getTempEffType(emitter2, src_temp, &fa_src_ty, &fa_ssg) == @intCast(u8, 1) and typeIsIntKind(registry, fa_src_ty) != @intCast(u8, 0)) {
                fa_cast = cast_name;
            }
        }
        var sep2: []const u8 = " = "; bufferedWriterWrite(writer, sep2);
        if (fa_cast.len != @intCast(usize, 0)) {
            var fc0: []const u8 = "("; bufferedWriterWrite(writer, fc0);
            bufferedWriterWrite(writer, fa_cast);
            var fc1: []const u8 = ")"; bufferedWriterWrite(writer, fc1);
        }
        bufferedWriterWrite(writer, src);
        var sep3: []const u8 = ";\n"; bufferedWriterWrite(writer, sep3);
    }
}

fn mangleC89Keyword(self: *NameMangler, name: []const u8) u32 {
    var buf: [33]u8 = undefined;
    buf[0] = @intCast(u8, 'z');
    buf[1] = @intCast(u8, '_');
    var i: usize = @intCast(usize, 0);
    while (i < name.len and i + @intCast(usize, 2) < @intCast(usize, 33)) : (i += @intCast(usize, 1)) {
        buf[i + @intCast(usize, 2)] = name[i];
    }
    return interner_mod.stringInternerIntern(self.interner, buf[0 .. i + @intCast(usize, 2)]);
}

fn nameManglerPopulateKeywords(self: *NameMangler) void {
    var k0: []const u8 = "auto";
    var k1: []const u8 = "break";
    var k2: []const u8 = "case";
    var k3: []const u8 = "char";
    var k4: []const u8 = "const";
    var k5: []const u8 = "continue";
    var k6: []const u8 = "default";
    var k7: []const u8 = "do";
    var k8: []const u8 = "double";
    var k9: []const u8 = "else";
    var k10: []const u8 = "enum";
    var k11: []const u8 = "extern";
    var k12: []const u8 = "float";
    var k13: []const u8 = "for";
    var k14: []const u8 = "goto";
    var k15: []const u8 = "if";
    var k16: []const u8 = "int";
    var k17: []const u8 = "long";
    var k18: []const u8 = "register";
    var k19: []const u8 = "return";
    var k20: []const u8 = "short";
    var k21: []const u8 = "signed";
    var k22: []const u8 = "sizeof";
    var k23: []const u8 = "static";
    var k24: []const u8 = "struct";
    var k25: []const u8 = "switch";
    var k26: []const u8 = "typedef";
    var k27: []const u8 = "union";
    var k28: []const u8 = "unsigned";
    var k29: []const u8 = "void";
    var k30: []const u8 = "volatile";
    var k31: []const u8 = "while";
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k0), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k1), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k2), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k3), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k4), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k5), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k6), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k7), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k8), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k9), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k10), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k11), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k12), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k13), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k14), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k15), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k16), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k17), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k18), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k19), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k20), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k21), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k22), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k23), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k24), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k25), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k26), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k27), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k28), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k29), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k30), @intCast(u32, 1));
    hash_mod.u32ToU32MapPut(&self.keyword_set, interner_mod.stringInternerIntern(self.interner, k31), @intCast(u32, 1));
}

pub fn nameManglerInit(interner: *StringInterner, alloc: *Sand, cache_hint: usize) NameMangler {
    var mangler = NameMangler{
        .hash_seed = @intCast(u32, 0),
        .cache = hash_mod.u64ToU32MapInitCap(alloc, cache_hint),
        .keyword_set = hash_mod.u32ToU32MapInitCap(alloc, @intCast(usize, 32)),
        .collision_mod = hash_mod.u32ToU32MapInit(alloc),
        .collision_name = hash_mod.u32ToU32MapInit(alloc),
        .interner = interner,
    };
    nameManglerPopulateKeywords(&mangler);
    return mangler;
}

pub fn nameManglerMangle(self: *NameMangler, name_id: u32, kind: u8, module_id: u32) u32 {
    var name = interner_mod.stringInternerGet(self.interner, name_id);
    if (isTempOrBuiltin(name) != @intCast(u8, 0)) return name_id;
    if (isC89Keyword(self, name_id) != @intCast(u8, 0)) return mangleC89Keyword(self, name);
    var key: u64 = (@intCast(u64, module_id) << @intCast(u64, 35)) | (@intCast(u64, kind) << @intCast(u64, 32)) | @intCast(u64, name_id);
    if (hash_mod.u64ToU32MapGet(&self.cache, key)) |cached| {
        return cached;
    }
    var hash = hash_mod.fnv1a(name);
    var kind_char: u8 = @intCast(u8, 'L');
    if (kind == @intCast(u8, 0)) { kind_char = @intCast(u8, 'F'); }
    else if (kind == @intCast(u8, 1)) { kind_char = @intCast(u8, 'G'); }
    else if (kind == @intCast(u8, 2)) { kind_char = @intCast(u8, 'T'); }
    var buf: [32]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    buf[p] = @intCast(u8, 'z'); p += @intCast(usize, 1);
    buf[p] = kind_char;          p += @intCast(usize, 1);
    buf[p] = @intCast(u8, '_');  p += @intCast(usize, 1);
    writeHex(buf[0..], &p, hash);
    buf[p] = @intCast(u8, '_');  p += @intCast(usize, 1);
    var prefix_end = p;
    var idx: usize = @intCast(usize, 0);
    while (idx < name.len and p < @intCast(usize, 31)) : (idx += @intCast(usize, 1)) {
        buf[p] = name[idx];
        p += @intCast(usize, 1);
    }
    if (p > @intCast(usize, 31)) p = @intCast(usize, 31);
    var mangled_id = interner_mod.stringInternerIntern(self.interner, buf[0..p]);
    // Collision resolution: if mangled_id already used by a different (module_id,name_id),
    // append _N suffix, truncating base name to fit within 31-char C89 limit.
    // Digit count computed dynamically to avoid truncation inside the suffix number.
    var counter: u32 = @intCast(u32, 0);
    while (true) {
        var existing_mod = hash_mod.u32ToU32MapGet(&self.collision_mod, mangled_id);
        if (existing_mod) |_| {
            counter += @intCast(u32, 1);
            p = prefix_end;
            var cnt = counter;
            var dc: u32 = @intCast(u32, 1);
            while (cnt >= @intCast(u32, 10)) : (cnt /= @intCast(u32, 10)) {
                dc += @intCast(u32, 1);
            }
            var max_nc: usize = @intCast(usize, 31) - prefix_end - @intCast(usize, 1) - @intCast(usize, dc);
            var ci: usize = @intCast(usize, 0);
            while (ci < name.len and p < prefix_end + max_nc) : (ci += @intCast(usize, 1)) {
                buf[p] = name[ci];
                p += @intCast(usize, 1);
            }
            buf[p] = @intCast(u8, '_'); p += @intCast(usize, 1);
            var cv = counter;
            var cd: [4]u8 = undefined;
            var di: u32 = @intCast(u32, 0);
            while (cv > @intCast(u32, 0)) {
                cd[@intCast(usize, di)] = @intCast(u8, '0') + @intCast(u8, cv % @intCast(u32, 10));
                cv /= @intCast(u32, 10);
                di += @intCast(u32, 1);
            }
            if (di == @intCast(u32, 0)) {
                buf[p] = @intCast(u8, '0'); p += @intCast(usize, 1);
            } else {
                var dk: u32 = di;
                while (dk > @intCast(u32, 0)) {
                    dk -= @intCast(u32, 1);
                    buf[p] = cd[@intCast(usize, dk)]; p += @intCast(usize, 1);
                }
            }
            if (p > @intCast(usize, 31)) p = @intCast(usize, 31);
            mangled_id = interner_mod.stringInternerIntern(self.interner, buf[0..p]);
        } else {
            break;
        }
    }
    hash_mod.u32ToU32MapPut(&self.collision_mod, mangled_id, module_id);
    hash_mod.u32ToU32MapPut(&self.collision_name, mangled_id, name_id);
    hash_mod.u64ToU32MapPut(&self.cache, key, mangled_id);
    return mangled_id;
}

pub fn nameManglerMangleGlobal(self: *NameMangler, registry: *TypeRegistry, name_id: u32, module_id: u32, type_id: u32) u32 {
    if (type_id < @intCast(u32, registry.types_len)) {
        var ty = registry.types_items[@intCast(usize, type_id)];
        if (ty.name_id != @intCast(u32, 0) and ty.name_id == name_id) {
            // Type-storage global: identity = the stored type (name + owning module),
            // so every module aliasing this type agrees on ONE C symbol.
            return nameManglerMangle(self, ty.name_id, @intCast(u8, 1), ty.module_id);
        }
    }
    // User module global: keep per-module keying.
    return nameManglerMangle(self, name_id, @intCast(u8, 1), module_id);
}

 pub const C89Emitter = struct {
     writer: BufferedWriter,
     indent: u32,
     alloc: *Sand,
     registry: *TypeRegistry,
     interner: *StringInterner,
     mangler: *NameMangler,
     diag: *DiagnosticCollector,
     switch_cases: *SwitchCaseArrayList,
     call_args: *U32ArrayList,
     current_fn: *LirFunction,
     spill: *lir_stream_mod.LirStream,
     fn_slots: [*]lir_mod.LirSlot,
     fn_slots_start: usize,
     fn_slots_len: usize,
     spill_arena: *Sand,
     d4_wtype: [*]u32,
     d4_wflag: [*]u8,
     d4_t2p: [*]u32,
      d4_dead: [*]u8,
      d4_max_temp: u32,
      d4_local: [*]u8,
      d4_nodecl: [*]u8,
      d4_lread: [*]u8,
      bb_used: [*]u8,
      bb_used_count: u32,
      dl_hoisted: u8,
     emitted_type_set: U32ToU32Map,
     fwd_decl_set: U32ToU32Map,
     pointer_only_map: U32ToU32Map,
      shared_set: U32ToU32Map,
      module_reg: *mr_mod.ModuleRegistry,
      error_code_registry: *hash_mod.U32ToU32Map,
      dedup_names: [*]u32,
      dedup_cap: u32,
     dedup_count: u32,
      fl_name_ids: [*]u32,
       fl_temps: [*]u32,
        fl_count: u32,
      temp_global_map: U32ToU32Map,
      ts_ref_set: U32ToU32Map,
      global_decls: [*]lir_mod.ModuleGlobalDecl,
      global_decls_len: u32,
   };

pub fn c89EmitterInit(reg: *TypeRegistry, interner: *StringInterner, mangler: *NameMangler, diag: *DiagnosticCollector, sc: *SwitchCaseArrayList, ca: *U32ArrayList, alloc: *Sand, error_code_reg: *hash_mod.U32ToU32Map, pointer_only_len: u32) C89Emitter {
    return C89Emitter{
        .writer = bufferedWriterInit(),
        .indent = @intCast(u32, 0),
        .alloc = alloc,
        .registry = reg,
        .interner = interner,
        .mangler = mangler,
        .diag = diag,
         .switch_cases = sc,
         .call_args = ca,
         .current_fn = undefined,
         .spill = undefined,
         .fn_slots = undefined,
         .fn_slots_start = @intCast(usize, 0),
         .fn_slots_len = @intCast(usize, 0),
         .spill_arena = undefined,
         .d4_wtype = undefined,
         .d4_wflag = undefined,
         .d4_t2p = undefined,
         .d4_dead = undefined,
         .d4_max_temp = @intCast(u32, 0),
         .d4_local = undefined,
         .d4_nodecl = undefined,
         .d4_lread = undefined,
         .bb_used = undefined,
         .bb_used_count = @intCast(u32, 0),
         .dl_hoisted = @intCast(u8, 0),
         .emitted_type_set = hash_mod.u32ToU32MapInitCap(alloc, reg.types_len),
         .fwd_decl_set = hash_mod.u32ToU32MapInitCap(alloc, reg.types_len),
         .pointer_only_map = hash_mod.u32ToU32MapInitCap(alloc, @intCast(usize, pointer_only_len)),
         .shared_set = hash_mod.u32ToU32MapInit(alloc),
         .module_reg = undefined,
         .error_code_registry = error_code_reg,
          .dedup_names = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 128) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable),
          .dedup_cap = @intCast(u32, 128),
          .dedup_count = @intCast(u32, 0),
            .fl_name_ids = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 128) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable),
            .fl_temps = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 128) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable),
            .fl_count = @intCast(u32, 0),
           .temp_global_map = hash_mod.u32ToU32MapInit(alloc),
           .ts_ref_set = hash_mod.u32ToU32MapInit(alloc),
           .global_decls = undefined,
           .global_decls_len = @intCast(u32, 0),
       };
}

fn aggregateKeyword(kind: TypeKind) []const u8 {
    if (kind == TypeKind.union_type) { var s: []const u8 = "union "; return s; }
    var s: []const u8 = "struct "; return s;
}

fn getCTypeName(reg: *TypeRegistry, mangler: *NameMangler, tid: u32) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    if (tid >= @intCast(u32, 20)) {
        var d6m: []const u8 = "D6:"; pal.markerWrite(d6m);
        var d6tb: [20]u8 = undefined; var d6tl = itoa_mod.itoa(tid, d6tb[0..]); var d6ts: usize = @intCast(usize, 19) - @intCast(usize, d6tl); pal.markerWrite(d6tb[d6ts..@intCast(usize, 19)]);
        var d6kn: []const u8 = "k"; pal.markerWrite(d6kn);
        var d6kb: [20]u8 = undefined; var d6kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), d6kb[0..]); var d6ks: usize = @intCast(usize, 19) - @intCast(usize, d6kl); pal.markerWrite(d6kb[d6ks..@intCast(usize, 19)]);
        var d6nn: []const u8 = "n"; pal.markerWrite(d6nn);
        var d6nb: [20]u8 = undefined; var d6nl = itoa_mod.itoa(ty.name_id, d6nb[0..]); var d6ns: usize = @intCast(usize, 19) - @intCast(usize, d6nl); pal.markerWrite(d6nb[d6ns..@intCast(usize, 19)]);
        var d6nl2: []const u8 = "\n"; pal.markerWrite(d6nl2);
    }
    if (ty.kind == TypeKind.void_type) { var s: []const u8 = "void"; return s; }
    if (ty.kind == TypeKind.bool_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.i8_type) { var s: []const u8 = "signed char"; return s; }
    if (ty.kind == TypeKind.i16_type) { var s: []const u8 = "short"; return s; }
    if (ty.kind == TypeKind.i32_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.i64_type) {
        var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
        return interner_mod.stringInternerGet(mangler.interner, mid);
    }
    if (ty.kind == TypeKind.u8_type) { var s: []const u8 = "unsigned char"; return s; }
    if (ty.kind == TypeKind.u16_type) { var s: []const u8 = "unsigned short"; return s; }
    if (ty.kind == TypeKind.u32_type) { var s: []const u8 = "unsigned int"; return s; }
    if (ty.kind == TypeKind.u64_type) {
        var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
        return interner_mod.stringInternerGet(mangler.interner, mid);
    }
    if (ty.kind == TypeKind.f32_type) { var s: []const u8 = "float"; return s; }
    if (ty.kind == TypeKind.f64_type) { var s: []const u8 = "double"; return s; }
    if (ty.kind == TypeKind.usize_type) { var s: []const u8 = "unsigned int"; return s; }
    if (ty.kind == TypeKind.isize_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.c_char_type) { var s: []const u8 = "char"; return s; }
    if (ty.kind == TypeKind.va_list_type) { var s: []const u8 = "va_list"; return s; }
    if (ty.kind == TypeKind.enum_type) {
        var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
        return interner_mod.stringInternerGet(mangler.interner, mid);
    }
    if (ty.kind == TypeKind.array_type) {
        var ap = reg.array_items[@intCast(usize, ty.payload_idx)];
        var e_cname = getCTypeName(reg, mangler, ap.elem);
        var abuf: [128]u8 = undefined;
        var ap2: usize = @intCast(usize, 0);
        var a_pfx: []const u8 = "Arr_"; var apfx: usize = 0;
        while (apfx < a_pfx.len and ap2 < 127) : (apfx += 1) { abuf[ap2] = a_pfx[apfx]; ap2 += 1; }
        var aei: usize = 0;
        while (aei < e_cname.len and ap2 < 127) : (aei += 1) { var ac = e_cname[aei]; if (ac == 32) { ac = '_'; } else if (ac == 42) { ac = '_'; } abuf[ap2] = ac; ap2 += 1; }
        if (ap2 < 127) { abuf[ap2] = '_'; ap2 += 1; }
        var albuf: [16]u8 = undefined;
        var all = itoa_mod.itoa(ap.length, albuf[0..]);
        var alst: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, all);
        var ali: usize = alst;
        while (ali < @intCast(usize, 16) - @intCast(usize, 1) and ap2 < 127) : (ali += 1) { abuf[ap2] = albuf[ali]; ap2 += 1; }
        var anid = interner_mod.stringInternerIntern(mangler.interner, abuf[0..ap2]);
        var amid = nameManglerMangle(mangler, anid, @intCast(u8, 2), @intCast(u32, 0));
        return interner_mod.stringInternerGet(mangler.interner, amid);
    }
    if (ty.kind == TypeKind.ptr_type or ty.kind == TypeKind.many_ptr_type) {
        var pp = reg.ptr_items[@intCast(usize, ty.payload_idx)];
        var et = reg.types_items[@intCast(usize, pp.base)];
        if (et.kind == TypeKind.fn_type) { return getCTypeName(reg, mangler, pp.base); }
        if (et.kind == TypeKind.u8_type) { var s: []const u8 = "unsigned char*"; return s; }
        if (et.kind == TypeKind.u32_type) { var s: []const u8 = "unsigned int*"; return s; }
        if (et.kind == TypeKind.i32_type) { var s: []const u8 = "int*"; return s; }
        if (et.kind == TypeKind.f64_type) { var s: []const u8 = "double*"; return s; }
        if (et.kind == TypeKind.c_char_type) { var s: []const u8 = "char*"; return s; }
        if (et.kind == TypeKind.usize_type) { var s: []const u8 = "unsigned int*"; return s; }
        var base_cname = getCTypeName(reg, mangler, pp.base);
        var pbuf: [128]u8 = undefined;
        var bi: usize = 0;
        while (bi < base_cname.len and bi < 126) : (bi += 1) { pbuf[bi] = base_cname[bi]; }
        pbuf[bi] = '*'; bi += 1;
        pbuf[bi] = 0; bi += 1;
        var ptr_mid = interner_mod.stringInternerIntern(mangler.interner, pbuf[0..bi - @intCast(usize, 1)]);
        return interner_mod.stringInternerGet(mangler.interner, ptr_mid);
    }
    if (ty.kind == TypeKind.undefined_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.integer_literal_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.null_type) { var nul_m: []const u8 = "NUL:TYnul "; pal.markerWrite(nul_m); var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.slice_type) {
        var sp = reg.slice_items[@intCast(usize, ty.payload_idx)];
        var elem_ty2 = reg.types_items[@intCast(usize, sp.elem)];
        var elem_mid2 = nameManglerMangle(mangler, elem_ty2.name_id, @intCast(u8, 2), @intCast(u32, 0));
        var elem_mangled2 = interner_mod.stringInternerGet(mangler.interner, elem_mid2);
        var buf2: [64]u8 = undefined;
        var p2: usize = @intCast(usize, 0);
        var ssl: []const u8 = "Slice_";
        var ssi: usize = @intCast(usize, 0);
        while (ssi < ssl.len and p2 < @intCast(usize, 63)) : (ssi += @intCast(usize, 1)) { buf2[p2] = ssl[ssi]; p2 += @intCast(usize, 1); }
        var sei: usize = @intCast(usize, 0);
        while (sei < elem_mangled2.len and p2 < @intCast(usize, 63)) : (sei += @intCast(usize, 1)) { buf2[p2] = elem_mangled2[sei]; p2 += @intCast(usize, 1); }
        if (p2 > @intCast(usize, 63)) p2 = @intCast(usize, 63);
        var slice_nid2 = interner_mod.stringInternerIntern(mangler.interner, buf2[0..p2]);
        var slice_mid2 = nameManglerMangle(mangler, slice_nid2, @intCast(u8, 2), @intCast(u32, 0));
        return interner_mod.stringInternerGet(mangler.interner, slice_mid2);
    }
    if (ty.kind == TypeKind.optional_type) {
        var op = reg.opt_items[@intCast(usize, ty.payload_idx)];
        var buf: [64]u8 = undefined;
        var p: usize = @intCast(usize, 0);
        var pref: []const u8 = "Opt_";
        var pi: usize = @intCast(usize, 0);
        while (pi < pref.len and p < @intCast(usize, 63)) : (pi += @intCast(usize, 1)) { buf[p] = pref[pi]; p += @intCast(usize, 1); }
        var ps_b: [10]u8 = undefined;
        var ps_len = itoa_mod.itoa(op.payload, ps_b[0..]);
        var ps_s: usize = @intCast(usize, 9) - @intCast(usize, ps_len);
        var wi: usize = @intCast(usize, 0);
        while (wi < @intCast(usize, ps_len) and p < @intCast(usize, 63)) : (wi += @intCast(usize, 1)) { buf[p] = ps_b[ps_s + wi]; p += @intCast(usize, 1); }
        if (p > @intCast(usize, 63)) p = @intCast(usize, 63);
        var opt_nid = interner_mod.stringInternerIntern(mangler.interner, buf[0..p]);
        var mangled_id = nameManglerMangle(mangler, opt_nid, @intCast(u8, 2), @intCast(u32, 0));
        return interner_mod.stringInternerGet(mangler.interner, mangled_id);
    }
    if (ty.c_name_id != 0) {
        return interner_mod.stringInternerGet(mangler.interner, ty.c_name_id);
    }
    if (ty.kind == TypeKind.error_union_type) {
        var ep = reg.eu_items[@intCast(usize, ty.payload_idx)];
        var buf: [64]u8 = undefined;
        var p: usize = @intCast(usize, 0);
        var pref: []const u8 = "EU_";
        var pi: usize = @intCast(usize, 0);
        while (pi < pref.len and p < @intCast(usize, 63)) : (pi += @intCast(usize, 1)) { buf[p] = pref[pi]; p += @intCast(usize, 1); }
        var pl = ep.payload;
        var di: usize = p;
        while (pl > @intCast(u32, 0) or di == p) : (di += @intCast(usize, 1)) {
            buf[di] = @intCast(u8, @intCast(u32, '0') + (pl % @intCast(u32, 10)));
            pl = pl / @intCast(u32, 10);
            if (di >= @intCast(usize, 63)) break;
        }
        p = di;
        var eu_nid = nameManglerMangle(mangler, interner_mod.stringInternerIntern(mangler.interner, buf[0..p]), @intCast(u8, 2), @intCast(u32, 0));
        return interner_mod.stringInternerGet(mangler.interner, eu_nid);
    }
    if (ty.kind == TypeKind.fn_type) {
        var fpp = reg.fn_items[@intCast(usize, ty.payload_idx)];
        var fbuf: [96]u8 = undefined;
        var fpos: usize = @intCast(usize, 0);
        fbuf[0] = @intCast(u8, 70);
        fbuf[2] = @intCast(u8, 95);
        if ((ty.flags & @as(u32, 1)) != @as(u32, 0)) {
            fbuf[1] = @intCast(u8, 80);
        } else {
            fbuf[1] = @intCast(u8, 78);
        }
        fpos = @intCast(usize, 3);
        var fret_c = getCTypeName(reg, mangler, fpp.return_type);
        var fri: usize = @intCast(usize, 0);
        while (fri < fret_c.len and fpos < @intCast(usize, 95)) : (fri += @intCast(usize, 1)) {
            var fc = fret_c[fri];
            if (fc == @intCast(u8, 32) or fc == @intCast(u8, 42)) {
                fc = @intCast(u8, 95);
            }
            fbuf[fpos] = fc;
            fpos += @intCast(usize, 1);
        }
        var fpcnt: u16 = fpp.params_count;
        var fpend: usize = @intCast(usize, fpp.params_start) + @intCast(usize, fpcnt);
        if (fpend <= reg.xt_len) {
            var fpcur: usize = @intCast(usize, fpp.params_start);
            while (fpcur < fpend and fpos < @intCast(usize, 95)) : (fpcur += @intCast(usize, 1)) {
                if (fpos < @intCast(usize, 95)) {
                    fbuf[fpos] = @intCast(u8, 95);
                    fpos += @intCast(usize, 1);
                }
                var fptid = reg.xt_items[fpcur];
                var fp_c = getCTypeName(reg, mangler, fptid);
                var fpj: usize = @intCast(usize, 0);
                while (fpj < fp_c.len and fpos < @intCast(usize, 95)) : (fpj += @intCast(usize, 1)) {
                    var fc2 = fp_c[fpj];
                    if (fc2 == @intCast(u8, 32) or fc2 == @intCast(u8, 42)) {
                        fc2 = @intCast(u8, 95);
                    }
                    fbuf[fpos] = fc2;
                    fpos += @intCast(usize, 1);
                }
            }
        }
        var fp_nid = interner_mod.stringInternerIntern(mangler.interner, fbuf[0..fpos]);
        var fp_mid = nameManglerMangle(mangler, fp_nid, @intCast(u8, 2), @intCast(u32, 0));
        return interner_mod.stringInternerGet(mangler.interner, fp_mid);
    }
    if (ty.kind == TypeKind.error_set_type) {
        if (ty.name_id == @intCast(u32, 0)) {
            var buf: [64]u8 = undefined;
            var p: usize = @intCast(usize, 0);
            var pref: []const u8 = "ES_";
            var pi: usize = @intCast(usize, 0);
            while (pi < pref.len and p < @intCast(usize, 63)) : (pi += @intCast(usize, 1)) { buf[p] = pref[pi]; p += @intCast(usize, 1); }
            var pl = ty.payload_idx;
            var di: usize = p;
            while (pl > @intCast(u32, 0) or di == p) : (di += @intCast(usize, 1)) {
                buf[di] = @intCast(u8, @intCast(u32, '0') + (pl % @intCast(u32, 10)));
                pl = pl / @intCast(u32, 10);
                if (di >= @intCast(usize, 63)) break;
            }
            p = di;
            var es_nid = nameManglerMangle(mangler, interner_mod.stringInternerIntern(mangler.interner, buf[0..p]), @intCast(u8, 2), @intCast(u32, 0));
            return interner_mod.stringInternerGet(mangler.interner, es_nid);
        }
        var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
        return interner_mod.stringInternerGet(mangler.interner, mid);
    }
    var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    return interner_mod.stringInternerGet(mangler.interner, mid);
}

fn getTempTypeByIndex(emitter: *C89Emitter, temp_id: u32) u32 {
    var ti: usize = @intCast(usize, 0);
    while (ti < emitter.current_fn.hoisted_temps.len) : (ti += @intCast(usize, 1)) {
        var ht = emitter.current_fn.hoisted_temps.items[ti];
        if (ht.temp_id == temp_id) { return ht.type_id; }
    }
    return @intCast(u32, 0xFFFFFFFF);
}


pub fn emitIncludes(writer: *BufferedWriter) void {
    var l0: []const u8 = "#include \"zig_compat.h\"\n";
    bufferedWriterWrite(writer, l0);
    var l1: []const u8 = "#include \"zig_runtime.h\"\n";
    bufferedWriterWrite(writer, l1);
}

pub fn emitZigCompatH(writer: *BufferedWriter) void {
    var l00: []const u8 = "/* zig_compat.h - C89 compatibility layer */\n";
    bufferedWriterWrite(writer, l00);
    var l01: []const u8 = "#ifndef ZIG_COMPAT_H\n";
    bufferedWriterWrite(writer, l01);
    var l02: []const u8 = "#define ZIG_COMPAT_H\n";
    bufferedWriterWrite(writer, l02);
    var l03: []const u8 = "\n#ifdef _MSC_VER\n    typedef __int64 z64;\n    typedef unsigned __int64 zu64;\n#elif defined(__WATCOMC__)\n    typedef long long z64;\n    typedef unsigned long long zu64;\n#else\n    typedef long long z64;\n    typedef unsigned long long zu64;\n#endif\n\n#if !defined(__cplusplus) && !defined(__WATCOMC__)\n    typedef signed char i8;\n    typedef short i16;\n    typedef int i32;\n    typedef z64 i64;\n    typedef unsigned char u8;\n    typedef unsigned short u16;\n    typedef unsigned int u32;\n    typedef zu64 u64;\n    typedef float f32;\n    typedef double f64;\n    typedef unsigned int usize;\n#endif\n\ntypedef int bool;\n#define true 1\n#define false 0\n\n#ifndef NULL\n#define NULL ((void*)0)\n#endif\n\n#endif /* ZIG_COMPAT_H */\n";
    bufferedWriterWrite(writer, l03);
}

// DEAD CODE — never called. Frozen mirror of sf/src/include/zig_pal.c.
// If zig_pal.c is modified, update this function to keep byte-identity.
pub fn emitZigPalC(writer: *BufferedWriter) void {
    var h01: []const u8 = "/* zig_pal.c - Platform Abstraction Layer (generated by zig1) */\n#ifndef ZIG_PAL_C\n#define ZIG_PAL_C\n#include \"zig_compat.h\"\n\n#ifdef _WIN32\n#include <windows.h>\n#else\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#include <fcntl.h>\n#endif\n\n"; bufferedWriterWrite(writer, h01);
    var h02: []const u8 = "#ifdef _WIN32\ntypedef void* PlatFile;\n#define PLAT_INVALID_FILE ((void*)-1)\n#else\ntypedef int PlatFile;\n#define PLAT_INVALID_FILE (-1)\n#endif\n\n"; bufferedWriterWrite(writer, h02);
    var h03: []const u8 = "static usize pal_strlen(const char* s)\n{\n#ifdef _WIN32\n    const char* p = s;\n    while (*p) p++;\n    return (usize)(p - s);\n#else\n    return (usize)strlen(s);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h03);
    var h04: []const u8 = "static void pal_memcpy(void* dst, const void* src, usize n)\n{\n#ifdef _WIN32\n    char* d = (char*)dst;\n    const char* s = (const char*)src;\n    while (n--) *d++ = *s++;\n#else\n    memcpy(dst, src, (size_t)n);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h04);
    var h05: []const u8 = "static void pal_reverse(char* buf, int len)\n{\n    int i = 0;\n    int j = len - 1;\n    while (i < j) {\n        char t = buf[i];\n        buf[i] = buf[j];\n        buf[j] = t;\n        i++;\n        j--;\n    }\n}\n\n"; bufferedWriterWrite(writer, h05);
    var h06: []const u8 = "static int pal_u64_to_str_buf(u64 value, char* buf, int bufsize)\n{\n    int i;\n    if (bufsize <= 0) return 0;\n    if (value == 0) {\n        buf[0] = '0';\n        buf[1] = '\\0';\n        return 1;\n    }\n    i = 0;\n    while (value > 0 && i < bufsize - 1) {\n        buf[i++] = '0' + (char)(value % 10);\n        value /= 10;\n    }\n    buf[i] = '\\0';\n    pal_reverse(buf, i);\n    return i;\n}\n\n"; bufferedWriterWrite(writer, h06);
    var h07: []const u8 = "void pal_print_stderr(const char* msg, usize len)\n{\n#ifdef _WIN32\n    HANDLE h;\n    DWORD written;\n    if (!msg || len == 0) return;\n    h = GetStdHandle(STD_ERROR_HANDLE);\n    if (h == INVALID_HANDLE_VALUE || h == NULL) return;\n    if (!WriteConsoleA(h, msg, (DWORD)len, &written, NULL))\n        WriteFile(h, msg, (DWORD)len, &written, NULL);\n#else\n    write(2, msg, (size_t)len);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h07);
    var h07b: []const u8 = "void pal_print_stdout(const char* msg, usize len)\n{\n#ifdef _WIN32\n    HANDLE h;\n    DWORD written;\n    if (!msg || len == 0) return;\n    h = GetStdHandle(STD_OUTPUT_HANDLE);\n    if (h == INVALID_HANDLE_VALUE || h == NULL) return;\n    if (!WriteConsoleA(h, msg, (DWORD)len, &written, NULL))\n        WriteFile(h, msg, (DWORD)len, &written, NULL);\n#else\n    write(1, msg, (size_t)len);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h07b);
    var h08: []const u8 = "void pal_abort(void)\n{\n#ifdef _WIN32\n    TerminateProcess(GetCurrentProcess(), 3);\n#else\n    abort();\n#endif\n}\n\n"; bufferedWriterWrite(writer, h08);
    var h09: []const u8 = "int pal_i64_to_str(i64 value, char* buf, int bufsize)\n{\n    u64 uval;\n    int is_neg;\n    int dlen;\n    if (bufsize <= 0) return 0;\n    if (value == 0) {\n        buf[0] = '0';\n        buf[1] = '\\0';\n        return 1;\n    }\n    is_neg = (value < 0) ? 1 : 0;\n    uval = is_neg ? (u64)(-(value + 1)) + 1 : (u64)value;\n    if (is_neg) {\n        buf[0] = '-';\n        dlen = pal_u64_to_str_buf(uval, buf + 1, bufsize - 1);\n        return dlen + 1;\n    }\n    return pal_u64_to_str_buf(uval, buf, bufsize);\n}\n\n"; bufferedWriterWrite(writer, h09);
    var h10: []const u8 = "int pal_u64_to_str(u64 value, char* buf, int bufsize)\n{\n    return pal_u64_to_str_buf(value, buf, bufsize);\n}\n\n"; bufferedWriterWrite(writer, h10);
    var h11: []const u8 = "int pal_f64_to_str(f64 value, char* buf, int bufsize)\n{\n    int int_len;\n    int i;\n    f64 frac_part;\n    i64 int_part;\n    u64 frac_int;\n    int pos;\n    if (bufsize < 2) {\n        if (bufsize == 1) buf[0] = '\\0';\n        return 0;\n    }\n    if (value < 0.0) {\n        buf[0] = '-';\n        pos = 1;\n        value = -value;\n    } else {\n        pos = 0;\n    }\n    int_part = (i64)value;\n    int_len = pal_i64_to_str(int_part, buf + pos, bufsize - pos);\n    if (int_len <= 0) return 0;\n    pos += int_len;\n    buf[pos++] = '.';\n    frac_part = value - (f64)int_part;\n    i = 0;\n    while (i < 6 && pos < bufsize - 1) {\n        frac_part *= 10.0;\n        frac_int = (u64)frac_part;\n        buf[pos++] = '0' + (char)(frac_int % 10);\n        frac_part -= (f64)frac_int;\n        i++;\n    }\n    while (pos > 0 && buf[pos - 1] == '0') pos--;\n    if (buf[pos - 1] == '.') pos++;\n    buf[pos] = '\\0';\n    return pos;\n}\n\n"; bufferedWriterWrite(writer, h11);
    var h12: []const u8 = "PlatFile pal_file_open(const char* path, int flags) {\n#ifdef _WIN32\n    HANDLE h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,\n                           FILE_ATTRIBUTE_NORMAL, NULL);\n    if (h == INVALID_HANDLE_VALUE) return PLAT_INVALID_FILE;\n    return h;\n#else\n    if (!path) return PLAT_INVALID_FILE;\n    return open(path, O_WRONLY | O_CREAT | O_TRUNC | flags, 0644);\n#endif\n}\nint pal_file_write(PlatFile fd, const char* buf, unsigned int len) {\n#ifdef _WIN32\n    HANDLE h = (HANDLE)fd; DWORD w = 0;\n    if (!buf || !WriteFile(h, buf, (DWORD)len, &w, NULL)) return -1;\n    return (int)w;\n#else\n    size_t off = 0; if (!buf) return -1;\n    while (off < (size_t)len) {\n        ssize_t n = write(fd, buf + off, (size_t)len - off);\n        if (n <= 0) return -1;\n        off += (size_t)n;\n    }\n    return (int)off;\n#endif\n}\nint pal_file_close(PlatFile fd) {\n#ifdef _WIN32\n    return CloseHandle((HANDLE)fd) ? 0 : -1;\n#else\n    return close(fd);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h12);
    var h13: []const u8 = "#if defined(_WIN32) && defined(ZIG_NO_CRT)\nint main(void);\nvoid __cdecl mainCRTStartup(void)\n{\n    int result = main();\n    ExitProcess((UINT)result);\n}\n#endif\n\n#endif /* ZIG_PAL_C */\n"; bufferedWriterWrite(writer, h13);
}

fn c89NeedsEmitEdge(kind: TypeKind) bool {
    if (kind == TypeKind.slice_type) return true;
    if (kind == TypeKind.struct_type) return true;
    if (kind == TypeKind.union_type) return true;
    if (kind == TypeKind.tagged_union_type) return true;
    if (kind == TypeKind.array_type) return true;
    if (kind == TypeKind.optional_type) return true;
    if (kind == TypeKind.error_union_type) return true;
    if (kind == TypeKind.enum_type) return true;            // ADD — embeddable by value
    if (kind == TypeKind.error_set_type) return true;       // ADD — embeddable by value
    if (kind == TypeKind.tuple_type) return true;
    if (kind == TypeKind.unresolved_name) return true;
    return false;
}




fn tstSeenInRange(reg: *TypeRegistry, start: u32, count: u32, tid: u32) bool {
    var j: usize = @intCast(usize, 0);
    while (j < @intCast(usize, count)) : (j += 1) {
        if (reg.fe_items[@intCast(usize, start) + j].type_id == tid) return true;
    }
    return false;
}

fn tstEdgesCount(reg: *TypeRegistry, ti: u32) u32 {
    var ty = reg.types_items[@intCast(usize, ti)];
    var c: u32 = @intCast(u32, 0);
    if (ty.kind == TypeKind.struct_type) {
        var sp = reg.st_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, sp.fields_count)) : (i += 1) {
            var ft = reg.fe_items[@intCast(usize, sp.fields_start) + i].type_id;
            if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, ft)].kind) and ft != ti) {
                if (!tstSeenInRange(reg, sp.fields_start, @intCast(u32, i), ft)) c += 1;
            }
        }
    } else if (ty.kind == TypeKind.tagged_union_type) {
        var tp = reg.tu_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, tp.fields_count)) : (i += 1) {
            var ft = reg.fe_items[@intCast(usize, tp.fields_start) + i].type_id;
            if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, ft)].kind) and ft != ti) {
                if (!tstSeenInRange(reg, tp.fields_start, @intCast(u32, i), ft)) c += 1;
            }
        }
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, tp.tag_type)].kind) and tp.tag_type != ti) {
            if (!tstSeenInRange(reg, tp.fields_start, tp.fields_count, tp.tag_type)) c += 1;
        }
    } else if (ty.kind == TypeKind.array_type) {
        var et = reg.array_items[@intCast(usize, ty.payload_idx)].elem;
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, et)].kind) and et != ti) c += 1;
    } else if (ty.kind == TypeKind.error_union_type) {
        var eup = reg.eu_items[@intCast(usize, ty.payload_idx)].payload;
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, eup)].kind) and eup != ti) c += 1;
    } else if (ty.kind == TypeKind.optional_type) {                              // ADD
        var op = reg.opt_items[@intCast(usize, ty.payload_idx)].payload;
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, op)].kind) and op != ti) c += 1;
    } else if (ty.kind == TypeKind.slice_type) {                                 // ADD
        var se = reg.slice_items[@intCast(usize, ty.payload_idx)].elem;
        var sek = reg.types_items[@intCast(usize, se)].kind;
        if (c89NeedsEmitEdge(sek) and se != ti and (sek == TypeKind.enum_type or sek == TypeKind.error_set_type)) c += 1;
    } else if (ty.kind == TypeKind.union_type) {                                 // ADD
        var up = reg.un_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, up.fields_count)) : (i += 1) {
            var ft = reg.fe_items[@intCast(usize, up.fields_start) + i].type_id;
            if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, ft)].kind) and ft != ti) {
                if (!tstSeenInRange(reg, up.fields_start, @intCast(u32, i), ft)) c += 1;
            }
        }
    }
    return c;
}

fn tstEdgesFill(reg: *TypeRegistry, ti: u32, tgt: [*]u32, start: u32) void {
    var ty = reg.types_items[@intCast(usize, ti)];
    var off: u32 = start;
    if (ty.kind == TypeKind.struct_type) {
        var sp = reg.st_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, sp.fields_count)) : (i += 1) {
            var ft = reg.fe_items[@intCast(usize, sp.fields_start) + i].type_id;
            if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, ft)].kind) and ft != ti) {
                if (!tstSeenInRange(reg, sp.fields_start, @intCast(u32, i), ft)) {
                    tgt[@intCast(usize, off)] = ft; off += 1;
                }
            }
        }
    } else if (ty.kind == TypeKind.tagged_union_type) {
        var tp = reg.tu_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, tp.fields_count)) : (i += 1) {
            var ft = reg.fe_items[@intCast(usize, tp.fields_start) + i].type_id;
            if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, ft)].kind) and ft != ti) {
                if (!tstSeenInRange(reg, tp.fields_start, @intCast(u32, i), ft)) {
                    tgt[@intCast(usize, off)] = ft; off += 1;
                }
            }
        }
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, tp.tag_type)].kind) and tp.tag_type != ti) {
            if (!tstSeenInRange(reg, tp.fields_start, tp.fields_count, tp.tag_type)) {
                tgt[@intCast(usize, off)] = tp.tag_type; off += 1;
            }
        }
    } else if (ty.kind == TypeKind.array_type) {
        var et = reg.array_items[@intCast(usize, ty.payload_idx)].elem;
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, et)].kind) and et != ti) {
            tgt[@intCast(usize, off)] = et; off += 1;
        }
    } else if (ty.kind == TypeKind.error_union_type) {
        var eup = reg.eu_items[@intCast(usize, ty.payload_idx)].payload;
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, eup)].kind) and eup != ti) {
            tgt[@intCast(usize, off)] = eup; off += 1;
        }
    } else if (ty.kind == TypeKind.optional_type) {                              // ADD
        var op = reg.opt_items[@intCast(usize, ty.payload_idx)].payload;
        if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, op)].kind) and op != ti) {
            tgt[@intCast(usize, off)] = op; off += 1;
        }
    } else if (ty.kind == TypeKind.slice_type) {                                 // ADD
        var se = reg.slice_items[@intCast(usize, ty.payload_idx)].elem;
        var sek = reg.types_items[@intCast(usize, se)].kind;
        if (c89NeedsEmitEdge(sek) and se != ti and (sek == TypeKind.enum_type or sek == TypeKind.error_set_type)) {
            tgt[@intCast(usize, off)] = se; off += 1;
        }
    } else if (ty.kind == TypeKind.union_type) {                                 // ADD
        var up = reg.un_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, up.fields_count)) : (i += 1) {
            var ft = reg.fe_items[@intCast(usize, up.fields_start) + i].type_id;
            if (c89NeedsEmitEdge(reg.types_items[@intCast(usize, ft)].kind) and ft != ti) {
                if (!tstSeenInRange(reg, up.fields_start, @intCast(u32, i), ft)) {
                    tgt[@intCast(usize, off)] = ft; off += 1;
                }
            }
        }
    }
}

fn tstIsDep(reg: *TypeRegistry, ti: u32, target: u32) bool {
    var ty = reg.types_items[@intCast(usize, ti)];
    if (!c89NeedsEmitEdge(reg.types_items[@intCast(usize, target)].kind) or target == ti) return false;
    if (ty.kind == TypeKind.struct_type) {
        var sp = reg.st_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, sp.fields_count)) : (i += 1) {
            if (reg.fe_items[@intCast(usize, sp.fields_start) + i].type_id == target) return true;
        }
    } else if (ty.kind == TypeKind.tagged_union_type) {
        var tp = reg.tu_items[@intCast(usize, ty.payload_idx)];
        if (tp.tag_type == target) return true;
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, tp.fields_count)) : (i += 1) {
            if (reg.fe_items[@intCast(usize, tp.fields_start) + i].type_id == target) return true;
        }
    } else if (ty.kind == TypeKind.array_type) {
        if (reg.array_items[@intCast(usize, ty.payload_idx)].elem == target) return true;

    } else if (ty.kind == TypeKind.error_union_type) {
        if (reg.eu_items[@intCast(usize, ty.payload_idx)].payload == target) return true;
    } else if (ty.kind == TypeKind.optional_type) {                              // ADD
        if (reg.opt_items[@intCast(usize, ty.payload_idx)].payload == target) return true;
    } else if (ty.kind == TypeKind.slice_type) {                                 // ADD
        var se = reg.slice_items[@intCast(usize, ty.payload_idx)].elem;
        var sek = reg.types_items[@intCast(usize, se)].kind;
        if (se == target and (sek == TypeKind.enum_type or sek == TypeKind.error_set_type)) return true;
    } else if (ty.kind == TypeKind.union_type) {                                 // ADD
        var up = reg.un_items[@intCast(usize, ty.payload_idx)];
        var i: usize = @intCast(usize, 0);
        while (i < @intCast(usize, up.fields_count)) : (i += 1) {
            if (reg.fe_items[@intCast(usize, up.fields_start) + i].type_id == target) return true;
        }
    }
    return false;
}

pub fn tstTopologicalSort(reg: *TypeRegistry, alloc: *Sand) [*]u32 {
    var tl: usize = reg.types_len;
    var indegree_raw = alloc_mod.sandAlloc(alloc, 4 * tl, 4) catch unreachable;
    var indegree: [*]u32 = @ptrCast([*]u32, indegree_raw);
    var ti: u32 = @intCast(u32, 0);
    while (@intCast(usize, ti) < tl) : (ti += 1) {
        indegree[@intCast(usize, ti)] = tstEdgesCount(reg, ti);
    }
    var result_raw = alloc_mod.sandAlloc(alloc, 4 * tl, 4) catch unreachable;
    var result: [*]u32 = @ptrCast([*]u32, result_raw);
    var queue_raw = alloc_mod.sandAlloc(alloc, 4 * tl, 4) catch unreachable;
    var queue: [*]u32 = @ptrCast([*]u32, queue_raw);
    var qhead: usize = 0;
    var qtail: usize = 0;
    ti = @intCast(u32, 0);
    while (@intCast(usize, ti) < tl) : (ti += 1) {
        if (indegree[@intCast(usize, ti)] == 0) {
            queue[qtail] = ti; qtail += 1;
        }
    }
    var ri: usize = 0;
    while (qhead < qtail) {
        var cur = queue[qhead]; qhead += 1;
        result[ri] = cur; ri += 1;
        var tj: u32 = @intCast(u32, 0);
        while (@intCast(usize, tj) < tl) : (tj += 1) {
            if (tstIsDep(reg, tj, cur)) {
                var idx = @intCast(usize, tj);
                indegree[idx] = indegree[idx] - @intCast(u32, 1);
                if (indegree[idx] == 0) {
                    queue[qtail] = tj; qtail += 1;
                }
            }
        }
    }
    return result;
}

fn ctypeGuardWrite(writer: *BufferedWriter, kind: TypeKind) void {
    if (kind == TypeKind.struct_type or kind == TypeKind.tagged_union_type) {
        var tag: []const u8 = "ZIG_STRUCT_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.union_type) {
        var tag: []const u8 = "ZIG_UNION_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.enum_type) {
        var tag: []const u8 = "ZIG_ENUM_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.error_set_type) {
        var tag: []const u8 = "ZIG_ERROR_SET_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.slice_type) {
        var tag: []const u8 = "ZIG_SLICE_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.optional_type) {
        var tag: []const u8 = "ZIG_OPTIONAL_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.error_union_type) {
        var tag: []const u8 = "ZIG_ERRORUNION_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.array_type) {
        var tag: []const u8 = "ZIG_ARRAY_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.fn_type) {
        var tag: []const u8 = "ZIG_FNPTR_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.i64_type) {
        var tag: []const u8 = "ZIG_I64_"; bufferedWriterWrite(writer, tag);
    } else if (kind == TypeKind.u64_type) {
        var tag: []const u8 = "ZIG_U64_"; bufferedWriterWrite(writer, tag);
    } else {
        var tag: []const u8 = "ZIG_TYPE_"; bufferedWriterWrite(writer, tag);
    }
}

pub fn computeSharedSet(reg: *TypeRegistry, emitter: *C89Emitter, alloc: *Sand) void {
    var ti: u32 = @intCast(u32, 0);
    while (@intCast(usize, ti) < reg.types_len) : (ti += 1) {
        var ty = reg.types_items[@intCast(usize, ti)];
        var is_synthetic: u8 = @intCast(u8, 0);
        if (ty.name_id == @intCast(u32, 0)) {
            if (ty.kind == TypeKind.slice_type or
                ty.kind == TypeKind.optional_type or
                ty.kind == TypeKind.error_union_type or
                ty.kind == TypeKind.error_set_type or
                ty.kind == TypeKind.tagged_union_type or
                ty.kind == TypeKind.union_type or
                ty.kind == TypeKind.array_type or
                ty.kind == TypeKind.fn_type)
            {
                is_synthetic = @intCast(u8, 1);
            }
        }
        var is_clsv: u8 = @intCast(u8, 0);
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, ti) == null) {
            is_clsv = @intCast(u8, 1);
        }
        var is_i64u64: u8 = @intCast(u8, 0);
        if (ty.kind == TypeKind.i64_type or ty.kind == TypeKind.u64_type) {
            is_i64u64 = @intCast(u8, 1);
        }
        var is_fn_named: u8 = @intCast(u8, 0);
        if (ty.kind == TypeKind.fn_type and ty.name_id != @intCast(u32, 0)) {
            is_fn_named = @intCast(u8, 1);
        }
        if (is_synthetic != @intCast(u8, 0) or is_clsv != @intCast(u8, 0) or is_i64u64 != @intCast(u8, 0) or is_fn_named != @intCast(u8, 0)) {
            hash_mod.u32ToU32MapPut(&emitter.shared_set, ti, @intCast(u32, 1));
        }
    }
    var changed: u32 = @intCast(u32, 1);
    while (changed != @intCast(u32, 0)) {
        changed = @intCast(u32, 0);
        var ti2: u32 = @intCast(u32, 0);
        while (@intCast(usize, ti2) < reg.types_len) : (ti2 += 1) {
            var ty2 = reg.types_items[@intCast(usize, ti2)];
            if (ty2.name_id == @intCast(u32, 0)) continue;
            if (hash_mod.u32ToU32MapGet(&emitter.shared_set, ti2) != null) continue;
            if (ty2.kind != TypeKind.struct_type and
                ty2.kind != TypeKind.tagged_union_type and
                ty2.kind != TypeKind.union_type and
                ty2.kind != TypeKind.enum_type and
                ty2.kind != TypeKind.error_set_type) continue;
            if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, ti2) == null) continue;
            var sj: u32 = @intCast(u32, 0);
            while (@intCast(usize, sj) < reg.types_len) : (sj += 1) {
                if (hash_mod.u32ToU32MapGet(&emitter.shared_set, sj) == null) continue;
                if (tstIsDep(reg, sj, ti2)) {
                    hash_mod.u32ToU32MapPut(&emitter.shared_set, ti2, @intCast(u32, 1));
                    changed = @intCast(u32, 1);
                    break;
                }
            }
        }
    }
}

pub fn emitSharedHeader(emitter: *C89Emitter, reg: *TypeRegistry, sorted: [*]u32) void {
    computeSharedSet(reg, emitter, emitter.alloc);
    var fg0: []const u8 = "#ifndef ZIG_SPECIAL_TYPES_H\n";
    bufferedWriterWrite(&emitter.writer, fg0);
    var fg1: []const u8 = "#define ZIG_SPECIAL_TYPES_H\n";
    bufferedWriterWrite(&emitter.writer, fg1);
    var fg2: []const u8 = "\n";
    bufferedWriterWrite(&emitter.writer, fg2);
    var pg0: []const u8 = "#include \"zig_compat.h\"\n";
    bufferedWriterWrite(&emitter.writer, pg0);
    var pg1: []const u8 = "#include \"zig_runtime.h\"\n";
    bufferedWriterWrite(&emitter.writer, pg1);
    var pg2: []const u8 = "\n";
    bufferedWriterWrite(&emitter.writer, pg2);
    emitErrorCodePrologue(emitter);
    var lfwd: hash_mod.U32ToU32Map = hash_mod.u32ToU32MapInitCap(emitter.alloc, reg.types_len);
    var lemit: hash_mod.U32ToU32Map = hash_mod.u32ToU32MapInitCap(emitter.alloc, reg.types_len);
    var tsi: usize = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        var ty = reg.types_items[@intCast(usize, tid)];
        if (ty.kind == TypeKind.struct_type or ty.kind == TypeKind.tagged_union_type or ty.kind == TypeKind.union_type) {
            if (ty.name_id != @intCast(u32, 0)) {
                var cname = getCTypeName(reg, emitter.mangler, tid);
                var dedup_key: u32 = @intCast(u32, 0);
                var h_ci: usize = @intCast(usize, 0);
                while (h_ci < cname.len) : (h_ci += 1) {
                    dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
                }
                if (hash_mod.u32ToU32MapGet(&lfwd, dedup_key) == null) {
                    var pre_s: []const u8 = "typedef "; bufferedWriterWrite(&emitter.writer, pre_s);
                    var pre_kw = aggregateKeyword(ty.kind); bufferedWriterWrite(&emitter.writer, pre_kw);
                    bufferedWriterWrite(&emitter.writer, cname);
                    var pre_s2: []const u8 = " "; bufferedWriterWrite(&emitter.writer, pre_s2);
                    bufferedWriterWrite(&emitter.writer, cname);
                    var pre_s3: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, pre_s3);
                    hash_mod.u32ToU32MapPut(&lfwd, dedup_key, @intCast(u32, 1));
                }
            }
        }
    }
    // Sub-pass 2a: emit pointer-only types that are in the shared set
    tsi = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        if (hash_mod.u32ToU32MapGet(&emitter.shared_set, tid) == null) continue;
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) == null) continue;
        var ty = reg.types_items[@intCast(usize, tid)];
        var e2m: []const u8 = "E2A:t"; pal.markerWrite(e2m); var e2b: [10]u8 = undefined; var e2l = itoa_mod.itoa(tid, e2b[0..]); var e2s: usize = @intCast(usize, 9) - @intCast(usize, e2l); pal.markerWrite(e2b[e2s..@intCast(usize, 9)]); var e2k: []const u8 = "k"; pal.markerWrite(e2k); var e2kb: [10]u8 = undefined; var e2kl2 = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), e2kb[0..]); var e2ks: usize = @intCast(usize, 9) - @intCast(usize, e2kl2); pal.markerWrite(e2kb[e2ks..@intCast(usize, 9)]); var e2nl2: []const u8 = "\n"; pal.markerWrite(e2nl2);
        if (ty.kind == TypeKind.void_type) { var vfs_m: []const u8 = "VFLOW:spv\n"; pal.markerWrite(vfs_m); continue; }
        if (ty.kind == TypeKind.bool_type) continue;
        if (ty.kind == TypeKind.noreturn_type) continue;
        if (ty.kind == TypeKind.null_type) continue;
        if (ty.kind == TypeKind.undefined_type) continue;
        if (ty.kind == TypeKind.integer_literal_type) continue;
        if (ty.kind == TypeKind.type_type) continue;
        if (ty.kind == TypeKind.module_type) continue;
        if (ty.name_id == @intCast(u32, 0)) {
            if (ty.kind != TypeKind.slice_type and
                ty.kind != TypeKind.optional_type and
                ty.kind != TypeKind.error_union_type and
                ty.kind != TypeKind.error_set_type and
                ty.kind != TypeKind.tagged_union_type and
                ty.kind != TypeKind.union_type and
                ty.kind != TypeKind.array_type and
                ty.kind != TypeKind.fn_type)
            {
                var est_m: []const u8 = "ESTA:t"; pal.markerWrite(est_m); var est_b: [10]u8 = undefined; var est_l = itoa_mod.itoa(tid, est_b[0..]); var est_s: usize = @intCast(usize, 9) - @intCast(usize, est_l); pal.markerWrite(est_b[est_s..@intCast(usize, 9)]); var est_km: []const u8 = "k"; pal.markerWrite(est_km); var est_kb: [10]u8 = undefined; var est_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), est_kb[0..]); var est_ks: usize = @intCast(usize, 9) - @intCast(usize, est_kl); pal.markerWrite(est_kb[est_ks..@intCast(usize, 9)]); var est_nm: []const u8 = "n"; pal.markerWrite(est_nm); var est_nb: [10]u8 = undefined; var est_nl2 = itoa_mod.itoa(ty.name_id, est_nb[0..]); var est_ns: usize = @intCast(usize, 9) - @intCast(usize, est_nl2); pal.markerWrite(est_nb[est_ns..@intCast(usize, 9)]); var est_nl: []const u8 = "\n"; pal.markerWrite(est_nl);
                continue;
            }
        }
        var cname = getCTypeName(reg, emitter.mangler, tid);
        var dedup_key: u32 = @intCast(u32, 0);
        var h_ci: usize = @intCast(usize, 0);
        while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
            dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
        }
        if (hash_mod.u32ToU32MapGet(&lemit, dedup_key)) |_| continue;
        hash_mod.u32ToU32MapPut(&lemit, dedup_key, @intCast(u32, 1));
        var g0: []const u8 = "#ifndef "; bufferedWriterWrite(&emitter.writer, g0);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g1: []const u8 = "\n#define "; bufferedWriterWrite(&emitter.writer, g1);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g2: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, g2);
        emitTypeDefinition(emitter, tid);
        var g3: []const u8 = "#endif /* "; bufferedWriterWrite(&emitter.writer, g3);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g4: []const u8 = " */\n"; bufferedWriterWrite(&emitter.writer, g4);
    }

    // Sub-pass 2b: emit value-embedding types entirely
    tsi = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) != null) continue;
        var ty = reg.types_items[@intCast(usize, tid)];
        var e2m: []const u8 = "E2B:t"; pal.markerWrite(e2m); var e2b: [10]u8 = undefined; var e2l = itoa_mod.itoa(tid, e2b[0..]); var e2s: usize = @intCast(usize, 9) - @intCast(usize, e2l); pal.markerWrite(e2b[e2s..@intCast(usize, 9)]); var e2k: []const u8 = "k"; pal.markerWrite(e2k); var e2kb: [10]u8 = undefined; var e2kl2 = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), e2kb[0..]); var e2ks: usize = @intCast(usize, 9) - @intCast(usize, e2kl2); pal.markerWrite(e2kb[e2ks..@intCast(usize, 9)]); var e2nm: []const u8 = "n"; pal.markerWrite(e2nm); var e2nb: [10]u8 = undefined; var e2nl3 = itoa_mod.itoa(ty.name_id, e2nb[0..]); var e2ns: usize = @intCast(usize, 9) - @intCast(usize, e2nl3); pal.markerWrite(e2nb[e2ns..@intCast(usize, 9)]); var e2nl2: []const u8 = "\n"; pal.markerWrite(e2nl2);
        if (ty.kind == TypeKind.void_type) { var vfs_m: []const u8 = "VFLOW:spv\n"; pal.markerWrite(vfs_m); continue; }
        if (ty.kind == TypeKind.bool_type) continue;
        if (ty.kind == TypeKind.noreturn_type) continue;
        if (ty.kind == TypeKind.null_type) continue;
        if (ty.kind == TypeKind.undefined_type) continue;
        if (ty.kind == TypeKind.integer_literal_type) continue;
        if (ty.kind == TypeKind.type_type) continue;
        if (ty.kind == TypeKind.module_type) continue;
        if (ty.name_id == @intCast(u32, 0)) {
            if (ty.kind != TypeKind.slice_type and
                ty.kind != TypeKind.optional_type and
                ty.kind != TypeKind.error_union_type and
                ty.kind != TypeKind.error_set_type and
                ty.kind != TypeKind.tagged_union_type and
                ty.kind != TypeKind.union_type and
                ty.kind != TypeKind.array_type and
                ty.kind != TypeKind.fn_type)
            {
                var est_m: []const u8 = "ESTB:t"; pal.markerWrite(est_m); var est_b: [10]u8 = undefined; var est_l = itoa_mod.itoa(tid, est_b[0..]); var est_s: usize = @intCast(usize, 9) - @intCast(usize, est_l); pal.markerWrite(est_b[est_s..@intCast(usize, 9)]); var est_km: []const u8 = "k"; pal.markerWrite(est_km); var est_kb: [10]u8 = undefined; var est_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), est_kb[0..]); var est_ks: usize = @intCast(usize, 9) - @intCast(usize, est_kl); pal.markerWrite(est_kb[est_ks..@intCast(usize, 9)]); var est_nm: []const u8 = "n"; pal.markerWrite(est_nm); var est_nb: [10]u8 = undefined; var est_nl2 = itoa_mod.itoa(ty.name_id, est_nb[0..]); var est_ns: usize = @intCast(usize, 9) - @intCast(usize, est_nl2); pal.markerWrite(est_nb[est_ns..@intCast(usize, 9)]); var est_nl: []const u8 = "\n"; pal.markerWrite(est_nl);
                continue;
            }
        }
        var cname = getCTypeName(reg, emitter.mangler, tid);
        var dedup_key: u32 = @intCast(u32, 0);
        var h_ci: usize = @intCast(usize, 0);
        while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
            dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
        }
        if (hash_mod.u32ToU32MapGet(&lemit, dedup_key)) |_| continue;
        hash_mod.u32ToU32MapPut(&lemit, dedup_key, @intCast(u32, 1));
        var g0: []const u8 = "#ifndef "; bufferedWriterWrite(&emitter.writer, g0);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g1: []const u8 = "\n#define "; bufferedWriterWrite(&emitter.writer, g1);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g2: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, g2);
        emitTypeDefinition(emitter, tid);
        var g3: []const u8 = "#endif /* "; bufferedWriterWrite(&emitter.writer, g3);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g4: []const u8 = " */\n"; bufferedWriterWrite(&emitter.writer, g4);
    }
    var eg0: []const u8 = "#endif /* ZIG_SPECIAL_TYPES_H */\n";
    bufferedWriterWrite(&emitter.writer, eg0);
}

pub fn emitSpecialTypes(emitter: *C89Emitter, reg: *TypeRegistry, sorted: [*]u32) void {
    var tsi: usize = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        var ty = reg.types_items[@intCast(usize, tid)];
        if (ty.kind == TypeKind.struct_type or ty.kind == TypeKind.tagged_union_type or ty.kind == TypeKind.union_type) {
            if (ty.name_id != @intCast(u32, 0)) {
                var cname = getCTypeName(reg, emitter.mangler, tid);
                var dedup_key: u32 = @intCast(u32, 0);
                var h_ci: usize = @intCast(usize, 0);
                while (h_ci < cname.len) : (h_ci += 1) {
                    dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
                }
                if (hash_mod.u32ToU32MapGet(&emitter.fwd_decl_set, dedup_key) == null) {
                    var pre_s: []const u8 = "typedef "; bufferedWriterWrite(&emitter.writer, pre_s);
                    var pre_kw = aggregateKeyword(ty.kind); bufferedWriterWrite(&emitter.writer, pre_kw);
                    bufferedWriterWrite(&emitter.writer, cname);
                    var pre_s2: []const u8 = " "; bufferedWriterWrite(&emitter.writer, pre_s2);
                    bufferedWriterWrite(&emitter.writer, cname);
                    var pre_s3: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, pre_s3);
                    hash_mod.u32ToU32MapPut(&emitter.fwd_decl_set, dedup_key, @intCast(u32, 1));
                }
            }
        }
    }
    // Sub-pass 2a: emit pointer-only types first
    // (fields all through pointers/slices/wrappers — forward decls sufficient)
    tsi = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) == null) continue;
        var ty = reg.types_items[@intCast(usize, tid)];
        var e2m: []const u8 = "E2A:t"; pal.markerWrite(e2m); var e2b: [10]u8 = undefined; var e2l = itoa_mod.itoa(tid, e2b[0..]); var e2s: usize = @intCast(usize, 9) - @intCast(usize, e2l); pal.markerWrite(e2b[e2s..@intCast(usize, 9)]); var e2k: []const u8 = "k"; pal.markerWrite(e2k); var e2kb: [10]u8 = undefined; var e2kl2 = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), e2kb[0..]); var e2ks: usize = @intCast(usize, 9) - @intCast(usize, e2kl2); pal.markerWrite(e2kb[e2ks..@intCast(usize, 9)]); var e2nl2: []const u8 = "\n"; pal.markerWrite(e2nl2);
        if (ty.kind == TypeKind.void_type) { var vfs_m: []const u8 = "VFLOW:spv\n"; pal.markerWrite(vfs_m); continue; }
        if (ty.kind == TypeKind.bool_type) continue;
        if (ty.kind == TypeKind.noreturn_type) continue;
        if (ty.kind == TypeKind.null_type) continue;
        if (ty.kind == TypeKind.undefined_type) continue;
        if (ty.kind == TypeKind.integer_literal_type) continue;
        if (ty.kind == TypeKind.type_type) continue;
        if (ty.kind == TypeKind.module_type) continue;
        if (ty.name_id == @intCast(u32, 0)) {
            if (ty.kind != TypeKind.slice_type and
                ty.kind != TypeKind.optional_type and
                ty.kind != TypeKind.error_union_type and
                ty.kind != TypeKind.error_set_type and
                ty.kind != TypeKind.tagged_union_type and
                ty.kind != TypeKind.union_type and
                ty.kind != TypeKind.array_type and
                ty.kind != TypeKind.fn_type)
            {
                var est_m: []const u8 = "ESTA:t"; pal.markerWrite(est_m); var est_b: [10]u8 = undefined; var est_l = itoa_mod.itoa(tid, est_b[0..]); var est_s: usize = @intCast(usize, 9) - @intCast(usize, est_l); pal.markerWrite(est_b[est_s..@intCast(usize, 9)]); var est_km: []const u8 = "k"; pal.markerWrite(est_km); var est_kb: [10]u8 = undefined; var est_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), est_kb[0..]); var est_ks: usize = @intCast(usize, 9) - @intCast(usize, est_kl); pal.markerWrite(est_kb[est_ks..@intCast(usize, 9)]); var est_nm: []const u8 = "n"; pal.markerWrite(est_nm); var est_nb: [10]u8 = undefined; var est_nl2 = itoa_mod.itoa(ty.name_id, est_nb[0..]); var est_ns: usize = @intCast(usize, 9) - @intCast(usize, est_nl2); pal.markerWrite(est_nb[est_ns..@intCast(usize, 9)]); var est_nl: []const u8 = "\n"; pal.markerWrite(est_nl);
                continue;
            }
        }
        var cname = getCTypeName(reg, emitter.mangler, tid);
        var dedup_key: u32 = @intCast(u32, 0);
        var h_ci: usize = @intCast(usize, 0);
        while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
            dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
        }
        if (hash_mod.u32ToU32MapGet(&emitter.emitted_type_set, dedup_key)) |_| continue;
        hash_mod.u32ToU32MapPut(&emitter.emitted_type_set, dedup_key, @intCast(u32, 1));
        emitTypeDefinition(emitter, tid);
    }

    // Sub-pass 2b: emit value-embedding types
    // (types that embed field types by value — need dependents defined first)
    tsi = @intCast(usize, 0);
    while (tsi < reg.types_len) : (tsi += 1) {
        var tid = sorted[tsi];
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) != null) continue;
        var ty = reg.types_items[@intCast(usize, tid)];
        var e2m: []const u8 = "E2B:t"; pal.markerWrite(e2m); var e2b: [10]u8 = undefined; var e2l = itoa_mod.itoa(tid, e2b[0..]); var e2s: usize = @intCast(usize, 9) - @intCast(usize, e2l); pal.markerWrite(e2b[e2s..@intCast(usize, 9)]); var e2k: []const u8 = "k"; pal.markerWrite(e2k); var e2kb: [10]u8 = undefined; var e2kl2 = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), e2kb[0..]); var e2ks: usize = @intCast(usize, 9) - @intCast(usize, e2kl2); pal.markerWrite(e2kb[e2ks..@intCast(usize, 9)]); var e2nm: []const u8 = "n"; pal.markerWrite(e2nm); var e2nb: [10]u8 = undefined; var e2nl3 = itoa_mod.itoa(ty.name_id, e2nb[0..]); var e2ns: usize = @intCast(usize, 9) - @intCast(usize, e2nl3); pal.markerWrite(e2nb[e2ns..@intCast(usize, 9)]); var e2nl2: []const u8 = "\n"; pal.markerWrite(e2nl2);
        if (ty.kind == TypeKind.tagged_union_type) {
            var d2m: []const u8 = "D2:t"; pal.measureMarkerWrite(d2m);
            var d2b: [20]u8 = undefined; var d2l = itoa_mod.itoa(tid, d2b[0..]); var d2s: usize = @intCast(usize, 19) - @intCast(usize, d2l); pal.measureMarkerWrite(d2b[d2s..@intCast(usize, 19)]);
            var d2nn: []const u8 = "n"; pal.measureMarkerWrite(d2nn);
            var d2nb: [20]u8 = undefined; var d2nl = itoa_mod.itoa(ty.name_id, d2nb[0..]); var d2ns: usize = @intCast(usize, 19) - @intCast(usize, d2nl); pal.measureMarkerWrite(d2nb[d2ns..@intCast(usize, 19)]);
            var d2mm: []const u8 = "m"; pal.measureMarkerWrite(d2mm);
            var d2mb: [20]u8 = undefined; var d2ml = itoa_mod.itoa(ty.module_id, d2mb[0..]); var d2ms: usize = @intCast(usize, 19) - @intCast(usize, d2ml); pal.measureMarkerWrite(d2mb[d2ms..@intCast(usize, 19)]);
            var d2nl2: []const u8 = "\n"; pal.measureMarkerWrite(d2nl2);
        }
        if (ty.kind == TypeKind.void_type) { var vfs_m: []const u8 = "VFLOW:spv\n"; pal.markerWrite(vfs_m); continue; }
        if (ty.kind == TypeKind.bool_type) continue;
        if (ty.kind == TypeKind.noreturn_type) continue;
        if (ty.kind == TypeKind.null_type) continue;
        if (ty.kind == TypeKind.undefined_type) continue;
        if (ty.kind == TypeKind.integer_literal_type) continue;
        if (ty.kind == TypeKind.type_type) continue;
        if (ty.kind == TypeKind.module_type) continue;
        if (ty.name_id == @intCast(u32, 0)) {
            if (ty.kind != TypeKind.slice_type and
                ty.kind != TypeKind.optional_type and
                ty.kind != TypeKind.error_union_type and
                ty.kind != TypeKind.error_set_type and
                ty.kind != TypeKind.tagged_union_type and
                ty.kind != TypeKind.union_type and
                ty.kind != TypeKind.array_type and
                ty.kind != TypeKind.fn_type)
            {
                var est_m: []const u8 = "ESTB:t"; pal.markerWrite(est_m); var est_b: [10]u8 = undefined; var est_l = itoa_mod.itoa(tid, est_b[0..]); var est_s: usize = @intCast(usize, 9) - @intCast(usize, est_l); pal.markerWrite(est_b[est_s..@intCast(usize, 9)]); var est_km: []const u8 = "k"; pal.markerWrite(est_km); var est_kb: [10]u8 = undefined; var est_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), est_kb[0..]); var est_ks: usize = @intCast(usize, 9) - @intCast(usize, est_kl); pal.markerWrite(est_kb[est_ks..@intCast(usize, 9)]); var est_nm: []const u8 = "n"; pal.markerWrite(est_nm); var est_nb: [10]u8 = undefined; var est_nl2 = itoa_mod.itoa(ty.name_id, est_nb[0..]); var est_ns: usize = @intCast(usize, 9) - @intCast(usize, est_nl2); pal.markerWrite(est_nb[est_ns..@intCast(usize, 9)]); var est_nl: []const u8 = "\n"; pal.markerWrite(est_nl);
                continue;
            }
        }
        var cname = getCTypeName(reg, emitter.mangler, tid);
        var dedup_key: u32 = @intCast(u32, 0);
        var h_ci: usize = @intCast(usize, 0);
        while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
            dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
        }
        if (hash_mod.u32ToU32MapGet(&emitter.emitted_type_set, dedup_key)) |_| continue;
        hash_mod.u32ToU32MapPut(&emitter.emitted_type_set, dedup_key, @intCast(u32, 1));
        emitTypeDefinition(emitter, tid);
    }
}

fn emitTaggedUnionType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var tp = reg.tu_items[@intCast(usize, ty.payload_idx)];
    var base_mid = nameManglerMangle(emitter.mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    var base_str = interner_mod.stringInternerGet(emitter.interner, base_mid);
    var tag_ty = reg.types_items[@intCast(usize, tp.tag_type)];
    var fstart: usize = @intCast(usize, tp.fields_start);
    var fcount: usize = @intCast(usize, tp.fields_count);
    if (tag_ty.kind == TypeKind.enum_type) {
    var tag_ep = reg.en_items[@intCast(usize, tag_ty.payload_idx)];
    var name_buf: [64]u8 = undefined;
    var np: usize = @intCast(usize, 0);
    var pref_tu: []const u8 = "TU_";
    var tui: usize = @intCast(usize, 0);
    while (tui < pref_tu.len and np < @intCast(usize, 63)) : (tui += @intCast(usize, 1)) {
        name_buf[np] = pref_tu[tui]; np += @intCast(usize, 1);
    }
    var bsi: usize = @intCast(usize, 0);
    while (bsi < base_str.len and np < @intCast(usize, 63)) : (bsi += @intCast(usize, 1)) {
        name_buf[np] = base_str[bsi]; np += @intCast(usize, 1);
    }
    if (np > @intCast(usize, 63)) np = @intCast(usize, 63);
    var struct_nid = interner_mod.stringInternerIntern(emitter.interner, name_buf[0..np]);
    var struct_mid = nameManglerMangle(emitter.mangler, struct_nid, @intCast(u8, 2), @intCast(u32, 0));
    var struct_name = interner_mod.stringInternerGet(emitter.interner, struct_mid);
    var tag_pref_buf: [64]u8 = undefined;
    var tp_pos: usize = @intCast(usize, 0);
    var pref_tag: []const u8 = "zTU_";
    var tgi: usize = @intCast(usize, 0);
    while (tgi < pref_tag.len and tp_pos < @intCast(usize, 63)) : (tgi += @intCast(usize, 1)) {
        tag_pref_buf[tp_pos] = pref_tag[tgi]; tp_pos += @intCast(usize, 1);
    }
    var bgsi: usize = @intCast(usize, 0);
    while (bgsi < base_str.len and tp_pos < @intCast(usize, 63)) : (bgsi += @intCast(usize, 1)) {
        tag_pref_buf[tp_pos] = base_str[bgsi]; tp_pos += @intCast(usize, 1);
    }
    if (tp_pos > @intCast(usize, 63)) tp_pos = @intCast(usize, 63);
    var em_start: usize = @intCast(usize, tag_ep.members_start);
    var em_count: usize = @intCast(usize, tag_ep.members_count);
    var emi: usize = @intCast(usize, 0);
    var sa: []const u8 = "/* Tag constants */\n";
    bufferedWriterWrite(&emitter.writer, sa);
    while (emi < em_count) : (emi += @intCast(usize, 1)) {
        var member = reg.em_items[em_start + emi];
        var mem_buf: [64]u8 = undefined;
        var mp: usize = @intCast(usize, 0);
        var tpi: usize = @intCast(usize, 0);
        while (tpi < tp_pos and mp < @intCast(usize, 63)) : (tpi += @intCast(usize, 1)) {
            mem_buf[mp] = tag_pref_buf[tpi]; mp += @intCast(usize, 1);
        }
        if (mp < @intCast(usize, 63)) { mem_buf[mp] = @intCast(u8, '_'); mp += @intCast(usize, 1); }
        var mem_name = interner_mod.stringInternerGet(emitter.interner, member.name_id);
        var mni: usize = @intCast(usize, 0);
        while (mni < mem_name.len and mp < @intCast(usize, 63)) : (mni += @intCast(usize, 1)) {
            mem_buf[mp] = mem_name[mni]; mp += @intCast(usize, 1);
        }
        if (mp > @intCast(usize, 63)) mp = @intCast(usize, 63);
        var macro_nid = interner_mod.stringInternerIntern(emitter.interner, mem_buf[0..mp]);
        var macro_str = interner_mod.stringInternerGet(emitter.interner, macro_nid);
        var val_itoa: [16]u8 = undefined;
        var val_len = itoa_mod.itoa(@intCast(u32, @intCast(i64, member.value)), val_itoa[0..]);
        var sb: []const u8 = "#define ";
        bufferedWriterWrite(&emitter.writer, sb);
        bufferedWriterWrite(&emitter.writer, macro_str);
        var sc: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, sc);
         var val_start: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, val_len);
         var val_end: usize = val_start + @intCast(usize, val_len);
         bufferedWriterWrite(&emitter.writer, val_itoa[val_start..val_end]);
        var sd: []const u8 = "\n";
        bufferedWriterWrite(&emitter.writer, sd);
    }
    var t0a: []const u8 = "struct "; bufferedWriterWrite(&emitter.writer, t0a);
    bufferedWriterWrite(&emitter.writer, base_str);
    var t0: []const u8 = " {\n"; bufferedWriterWrite(&emitter.writer, t0);
    var t1: []const u8 = "\t"; bufferedWriterWrite(&emitter.writer, t1);
    var tag_ctype = getCTypeName(reg, emitter.mangler, tp.tag_type);
    bufferedWriterWrite(&emitter.writer, tag_ctype);
    var t2: []const u8 = " tag;\n"; bufferedWriterWrite(&emitter.writer, t2);
    var t3: []const u8 = "\tunion {\n"; bufferedWriterWrite(&emitter.writer, t3);
    var t4: []const u8 = "\t\tchar _dummy;\n"; bufferedWriterWrite(&emitter.writer, t4);
    } else {
    var fefi: usize = @intCast(usize, 0);
    while (fefi < fcount) : (fefi += @intCast(usize, 1)) {
        var fe = reg.fe_items[fstart + fefi];
        var fname = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
        var def_buf: [128]u8 = undefined;
        var dp: usize = @intCast(usize, 0);
        var da: []const u8 = "#define "; var dai: usize = 0;
        while (dai < da.len and dp < 127) : (dai += 1) { def_buf[dp] = da[dai]; dp += 1; }
        var dbi: usize = 0;
        while (dbi < base_str.len and dp < 127) : (dbi += 1) { def_buf[dp] = base_str[dbi]; dp += 1; }
        if (dp < 127) { def_buf[dp] = '_'; dp += 1; }
        var dni: usize = 0;
        while (dni < fname.len and dp < 127) : (dni += 1) { def_buf[dp] = fname[dni]; dp += 1; }
        if (dp < 127) { def_buf[dp] = ' '; dp += 1; }
         var fi_val: [16]u8 = undefined;
         var fi_len = itoa_mod.itoa(@intCast(u32, @intCast(u64, fefi)), fi_val[0..]);
         var fi_start: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, fi_len);
         var fii: usize = fi_start;
         while (fii < fi_start + @intCast(usize, fi_len) and dp < 127) : (fii += @intCast(usize, 1)) { def_buf[dp] = fi_val[fii]; dp += @intCast(usize, 1); }
        if (dp < 127) { def_buf[dp] = '\n'; dp += 1; }
        bufferedWriterWrite(&emitter.writer, def_buf[0..dp]);
    }
    var t5a: []const u8 = "struct "; bufferedWriterWrite(&emitter.writer, t5a);
    bufferedWriterWrite(&emitter.writer, base_str);
    var t5: []const u8 = " {\n"; bufferedWriterWrite(&emitter.writer, t5);
    var t6: []const u8 = "\tunsigned int tag;\n"; bufferedWriterWrite(&emitter.writer, t6);
    var t7: []const u8 = "\tunion {\n"; bufferedWriterWrite(&emitter.writer, t7);
    var t8: []const u8 = "\t\tchar _dummy;\n"; bufferedWriterWrite(&emitter.writer, t8);
    }
    var fi: usize = @intCast(usize, 0);
    while (fi < fcount) : (fi += @intCast(usize, 1)) {
        var fe = reg.fe_items[fstart + fi];
        var ft = reg.types_items[@intCast(usize, fe.type_id)];
        if (ft.kind != TypeKind.void_type) {
            var fe_name = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
            var si1: []const u8 = "\t\tstruct { ";
            bufferedWriterWrite(&emitter.writer, si1);
            var fi_type = getCTypeName(reg, emitter.mangler, fe.type_id);
            bufferedWriterWrite(&emitter.writer, fi_type);
            var si2: []const u8 = " _0; } ";
            bufferedWriterWrite(&emitter.writer, si2);
            bufferedWriterWrite(&emitter.writer, fe_name);
            var si3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, si3);
        }
    }
    var sp1: []const u8 = "\t} payload;\n"; bufferedWriterWrite(&emitter.writer, sp1);
    var sp2: []const u8 = "};\n"; bufferedWriterWrite(&emitter.writer, sp2);
}

fn emitStructType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var mangled_id = nameManglerMangle(emitter.mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    var mangled_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    var sp = reg.st_items[@intCast(usize, ty.payload_idx)];
    var fstart: usize = @intCast(usize, sp.fields_start);
    var fcount: usize = @intCast(usize, sp.fields_count);
    var es0a: []const u8 = "struct "; bufferedWriterWrite(&emitter.writer, es0a);
    bufferedWriterWrite(&emitter.writer, mangled_name);
    var es0: []const u8 = " {\n"; bufferedWriterWrite(&emitter.writer, es0);
    var i: usize = @intCast(usize, 0);
    while (i < fcount) : (i += @intCast(usize, 1)) {
        var fe = reg.fe_items[fstart + i];
        var fe_m: []const u8 = "FE:"; pal.measureMarkerWrite(fe_m);
        var fe_nb: [10]u8 = undefined; var fe_nl = itoa_mod.itoa(fe.name_id, fe_nb[0..]); var fe_ns: usize = @intCast(usize, 9) - @intCast(usize, fe_nl); pal.measureMarkerWrite(fe_nb[fe_ns..@intCast(usize, 9)]);
        var fe_c: []const u8 = ":"; pal.measureMarkerWrite(fe_c);
        var fe_tb: [10]u8 = undefined; var fe_tl = itoa_mod.itoa(fe.type_id, fe_tb[0..]); var fe_ts: usize = @intCast(usize, 9) - @intCast(usize, fe_tl); pal.measureMarkerWrite(fe_tb[fe_ts..@intCast(usize, 9)]);
        var fe_nl2: []const u8 = "\n"; pal.measureMarkerWrite(fe_nl2);
        var fname = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
        var ftype = getCTypeName(reg, emitter.mangler, fe.type_id);
        if (fe.type_id != type_mod.TYPE_VOID) {
            var es1: []const u8 = "\t"; bufferedWriterWrite(&emitter.writer, es1);
            bufferedWriterWrite(&emitter.writer, ftype);
            var es2: []const u8 = " "; bufferedWriterWrite(&emitter.writer, es2);
            bufferedWriterWrite(&emitter.writer, fname);
            var es3: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, es3);
        }
    }
    var es4: []const u8 = "};\n"; bufferedWriterWrite(&emitter.writer, es4);
    var es_m: []const u8 = "ES:n"; pal.markerWriteInt(es_m, mangled_id);
}

fn emitUnionType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var mangled_id = nameManglerMangle(emitter.mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    var mangled_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    var up = reg.un_items[@intCast(usize, ty.payload_idx)];
    var fstart: usize = @intCast(usize, up.fields_start);
    var fcount: usize = @intCast(usize, up.fields_count);
    var es0a = aggregateKeyword(ty.kind); bufferedWriterWrite(&emitter.writer, es0a);
    bufferedWriterWrite(&emitter.writer, mangled_name);
    var es0: []const u8 = " {\n"; bufferedWriterWrite(&emitter.writer, es0);
    var i: usize = @intCast(usize, 0);
    while (i < fcount) : (i += 1) {
        var fe = reg.fe_items[fstart + i];
        if (fe.type_id != type_mod.TYPE_VOID) {
            var fname = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
            var ftype = getCTypeName(reg, emitter.mangler, fe.type_id);
            var es1: []const u8 = "\t"; bufferedWriterWrite(&emitter.writer, es1);
            bufferedWriterWrite(&emitter.writer, ftype);
            var es2: []const u8 = " "; bufferedWriterWrite(&emitter.writer, es2);
            bufferedWriterWrite(&emitter.writer, fname);
            var es3: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, es3);
        }
    }
    var es4: []const u8 = "};\n"; bufferedWriterWrite(&emitter.writer, es4);
}

fn emitArrayType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var ap = reg.array_items[@intCast(usize, ty.payload_idx)];
    var ename = getCTypeName(reg, emitter.mangler, ap.elem);
    var lbuf2: [16]u8 = undefined;
    var ll2 = itoa_mod.itoa(ap.length, lbuf2[0..]);
    var lst2: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, ll2);
    var nam_buf: [128]u8 = undefined;
    var nam_p: usize = 0;
    var pfx: []const u8 = "Arr_"; var px: usize = 0;
    while (px < pfx.len and nam_p < 127) : (px += 1) { nam_buf[nam_p] = pfx[px]; nam_p += 1; }
    var ex: usize = 0;
    while (ex < ename.len and nam_p < 127) : (ex += 1) { var c = ename[ex]; if (c == 32) { c = '_'; } else if (c == 42) { c = '_'; } nam_buf[nam_p] = c; nam_p += 1; }
    if (nam_p < 127) { nam_buf[nam_p] = '_'; nam_p += 1; }
    var lx: usize = lst2;
    while (lx < @intCast(usize, 16) - @intCast(usize, 1) and nam_p < 127) : (lx += 1) { nam_buf[nam_p] = lbuf2[lx]; nam_p += 1; }
    var anid = interner_mod.stringInternerIntern(emitter.interner, nam_buf[0..nam_p]);
    var amid = nameManglerMangle(emitter.mangler, anid, @intCast(u8, 2), @intCast(u32, 0));
    var aname = interner_mod.stringInternerGet(emitter.interner, amid);
    var a0: []const u8 = "typedef "; bufferedWriterWrite(&emitter.writer, a0);
    bufferedWriterWrite(&emitter.writer, ename);
    var a1: []const u8 = " "; bufferedWriterWrite(&emitter.writer, a1);
    bufferedWriterWrite(&emitter.writer, aname);
    var a2: []const u8 = "["; bufferedWriterWrite(&emitter.writer, a2);
    var buf: [16]u8 = undefined;
    var decl_len = if (ap.length == @intCast(u32, 0)) @intCast(u32, 1) else ap.length;
    var al = itoa_mod.itoa(decl_len, buf[0..]);
    var astart: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, al);
    bufferedWriterWrite(&emitter.writer, buf[astart..@intCast(usize, 16) - @intCast(usize, 1)]);
    var a3: []const u8 = "];\n"; bufferedWriterWrite(&emitter.writer, a3);
}

fn emitTypeDefinition(emitter: *C89Emitter, tid: u32) void {
    var ty = emitter.registry.types_items[@intCast(usize, tid)];
    var et_k: [20]u8 = undefined;
    var et_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ty.kind)), et_k[0..]);
    var et_ks: usize = @intCast(usize, 19) - @intCast(usize, et_kl);
    var etm: []const u8 = "ET:t"; pal.markerWrite(etm);
    var et_t: [20]u8 = undefined;
    var et_tl = itoa_mod.itoa(tid, et_t[0..]);
    var et_ts: usize = @intCast(usize, 19) - @intCast(usize, et_tl);
    pal.markerWrite(et_t[et_ts..@intCast(usize, 19)]);
    var etk: []const u8 = "k"; pal.markerWrite(etk); pal.markerWrite(et_k[et_ks..@intCast(usize, 19)]);
    var etnl: []const u8 = "\n"; pal.markerWrite(etnl);
    if (ty.kind == TypeKind.slice_type) { emitSliceType(emitter, tid); return; }
    if (ty.kind == TypeKind.optional_type) { var vfo1_m: []const u8 = "VFLOW:oTV\n"; pal.markerWrite(vfo1_m); emitOptionalType(emitter, tid); return; }
    if (ty.kind == TypeKind.error_union_type) { emitErrorUnionType(emitter, tid); return; }
    if (ty.kind == TypeKind.error_set_type) { emitErrorSetType(emitter, tid); return; }
    if (ty.kind == TypeKind.tagged_union_type) { emitTaggedUnionType(emitter, tid); return; }
    if (ty.kind == TypeKind.enum_type) { emitEnumType(emitter, tid); return; }
    if (ty.kind == TypeKind.struct_type) { emitStructType(emitter, tid); return; }
    if (ty.kind == TypeKind.union_type) { emitUnionType(emitter, tid); return; }
    if (ty.kind == TypeKind.array_type) { emitArrayType(emitter, tid); return; }
    if (ty.kind == TypeKind.i64_type) { emitInt64Type(emitter, tid); return; }
    if (ty.kind == TypeKind.u64_type) { emitUint64Type(emitter, tid); return; }
    if (ty.kind == TypeKind.fn_type) {
        if ((ty.flags & @intCast(u8, 1)) != @intCast(u8, 0)) { emitFnPtrType(emitter, tid); }
        return;
    }
}

fn emitFnPtrType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var fp = reg.fn_items[@intCast(usize, ty.payload_idx)];
    var s_td: []const u8 = "typedef "; bufferedWriterWrite(&emitter.writer, s_td);
    var ret_c = getCTypeName(reg, emitter.mangler, fp.return_type);
    bufferedWriterWrite(&emitter.writer, ret_c);
    var s_op: []const u8 = " (*"; bufferedWriterWrite(&emitter.writer, s_op);
    var name_c = getCTypeName(reg, emitter.mangler, tid);
    bufferedWriterWrite(&emitter.writer, name_c);
    var s_cp: []const u8 = ")("; bufferedWriterWrite(&emitter.writer, s_cp);
    var fpc: u16 = fp.params_count;
    var fpend: usize = @intCast(usize, fp.params_start) + @intCast(usize, fpc);
    if (fpc == @intCast(u16, 0) or fpend > reg.xt_len) {
        var s_v: []const u8 = "void"; bufferedWriterWrite(&emitter.writer, s_v);
    } else {
        var pi: usize = @intCast(usize, fp.params_start);
        var firstp: u8 = @intCast(u8, 1);
        while (pi < fpend) : (pi += @intCast(usize, 1)) {
            if (firstp == @intCast(u8, 0)) {
                var s_cm: []const u8 = ", "; bufferedWriterWrite(&emitter.writer, s_cm);
            }
            firstp = @intCast(u8, 0);
            var ptid = reg.xt_items[pi];
            var pcn = getCTypeName(reg, emitter.mangler, ptid);
            bufferedWriterWrite(&emitter.writer, pcn);
        }
    }
    var s_end: []const u8 = ");\n"; bufferedWriterWrite(&emitter.writer, s_end);
}

fn emitErrorSetType(emitter: *C89Emitter, tid: u32) void {
    var ty = emitter.registry.types_items[@intCast(usize, tid)];
    var cname = getCTypeName(emitter.registry, emitter.mangler, tid);
    var td: []const u8 = "typedef int "; bufferedWriterWrite(&emitter.writer, td);
    bufferedWriterWrite(&emitter.writer, cname);
    var sc: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, sc);
    if (@intCast(usize, ty.payload_idx) < emitter.registry.es_len) {
        var esp = emitter.registry.es_items[@intCast(usize, ty.payload_idx)];
        var ei: usize = @intCast(usize, 0);
        while (ei < @intCast(usize, esp.tags_count)) : (ei += @intCast(usize, 1)) {
            var mname_id = emitter.registry.xn_items[@intCast(usize, esp.tags_start) + ei];
            var mname = interner_mod.stringInternerGet(emitter.interner, mname_id);
            var reg_code = hash_mod.u32ToU32MapGetOrAddDense(emitter.error_code_registry, mname_id);
            var def: []const u8 = "#define "; bufferedWriterWrite(&emitter.writer, def);
            bufferedWriterWrite(&emitter.writer, cname);
            var us: []const u8 = "_"; bufferedWriterWrite(&emitter.writer, us);
            bufferedWriterWrite(&emitter.writer, mname);
            var sp: []const u8 = " "; bufferedWriterWrite(&emitter.writer, sp);
            var val_itoa: [16]u8 = undefined;
            var val_len = itoa_mod.itoa(reg_code, val_itoa[0..]);
            var val_start: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, val_len);
            var val_end: usize = val_start + @intCast(usize, val_len);
            bufferedWriterWrite(&emitter.writer, val_itoa[val_start..val_end]);
            var nl: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, nl);
        }
    }
    var nl2: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, nl2);
}

fn emitErrorCodePrologue(emitter: *C89Emitter) void {
    if (emitter.error_code_registry.count == @intCast(usize, 0)) return;
    var tag_hdr: []const u8 = "/* Error tags */\n";
    bufferedWriterWrite(&emitter.writer, tag_hdr);
    var cap: usize = emitter.error_code_registry.capacity;
    var i: usize = @intCast(usize, 0);
    while (i < cap) : (i += @intCast(usize, 1)) {
        if (emitter.error_code_registry.occupied[i] != @intCast(u8, 0)) {
            var name_id = emitter.error_code_registry.keys[i];
            var code = emitter.error_code_registry.values[i];
            var name = interner_mod.stringInternerGet(emitter.interner, name_id);
            var def: []const u8 = "#define ERROR_"; bufferedWriterWrite(&emitter.writer, def);
            bufferedWriterWrite(&emitter.writer, name);
            var sp: []const u8 = " "; bufferedWriterWrite(&emitter.writer, sp);
            var val_itoa: [16]u8 = undefined;
            var val_len = itoa_mod.itoa(code, val_itoa[0..]);
            var val_start: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, val_len);
            var val_end: usize = val_start + @intCast(usize, val_len);
            bufferedWriterWrite(&emitter.writer, val_itoa[val_start..val_end]);
            var nl: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, nl);
        }
    }
    var nl2: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, nl2);
}


fn emitEnumType(emitter: *C89Emitter, tid: u32) void {
    var ty = emitter.registry.types_items[@intCast(usize, tid)];
    var mangled_id = nameManglerMangle(emitter.mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    var mangled_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    var ep = emitter.registry.en_items[@intCast(usize, ty.payload_idx)];
    var ctype = getCTypeName(emitter.registry, emitter.mangler, ep.backing_type);
    var td: []const u8 = "typedef "; bufferedWriterWrite(&emitter.writer, td);
    bufferedWriterWrite(&emitter.writer, ctype);
    var sp: []const u8 = " "; bufferedWriterWrite(&emitter.writer, sp);
    bufferedWriterWrite(&emitter.writer, mangled_name);
    var sc: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, sc);
    var mi: u16 = @intCast(u16, 0);
    while (mi < ep.members_count) : (mi += @intCast(u16, 1)) {
        var member = emitter.registry.em_items[@intCast(usize, ep.members_start) + @intCast(usize, mi)];
        var def: []const u8 = "#define "; bufferedWriterWrite(&emitter.writer, def);
        bufferedWriterWrite(&emitter.writer, mangled_name);
        var us: []const u8 = "_"; bufferedWriterWrite(&emitter.writer, us);
        var mname = interner_mod.stringInternerGet(emitter.interner, member.name_id);
        bufferedWriterWrite(&emitter.writer, mname);
        var eq: []const u8 = " "; bufferedWriterWrite(&emitter.writer, eq);
        var val_itoa: [16]u8 = undefined;
        var val_len = itoa_mod.itoa(@intCast(u32, @intCast(i64, member.value)), val_itoa[0..]);
        var val_start: usize = @intCast(usize, 16) - @intCast(usize, 1) - @intCast(usize, val_len);
        var val_end: usize = val_start + @intCast(usize, val_len);
        bufferedWriterWrite(&emitter.writer, val_itoa[val_start..val_end]);
        var nl2: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, nl2);
    }
    var nl: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, nl);
}

fn emitInt64Type(emitter: *C89Emitter, tid: u32) void {
    var ty = emitter.registry.types_items[@intCast(usize, tid)];
    var mangled_id = nameManglerMangle(emitter.mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    var mangled_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    var td: []const u8 = "typedef long long "; bufferedWriterWrite(&emitter.writer, td);
    bufferedWriterWrite(&emitter.writer, mangled_name);
    var sc: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, sc);
}

fn emitUint64Type(emitter: *C89Emitter, tid: u32) void {
    var ty = emitter.registry.types_items[@intCast(usize, tid)];
    var mangled_id = nameManglerMangle(emitter.mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    var mangled_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    var td: []const u8 = "typedef unsigned long long "; bufferedWriterWrite(&emitter.writer, td);
    bufferedWriterWrite(&emitter.writer, mangled_name);
    var sc: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, sc);
}

fn emitSliceType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var sp = reg.slice_items[@intCast(usize, ty.payload_idx)];
    var elem_c_name = getCTypeName(reg, emitter.mangler, sp.elem);
    var elem_ty = reg.types_items[@intCast(usize, sp.elem)];
    var elem_mid = nameManglerMangle(emitter.mangler, elem_ty.name_id, @intCast(u8, 2), @intCast(u32, 0));
    var elem_mangled = interner_mod.stringInternerGet(emitter.interner, elem_mid);
    var buf: [64]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    var sl: []const u8 = "Slice_";
    var si: usize = @intCast(usize, 0);
    while (si < sl.len and p < @intCast(usize, 63)) : (si += @intCast(usize, 1)) {
        buf[p] = sl[si]; p += @intCast(usize, 1);
    }
    var ei: usize = @intCast(usize, 0);
    while (ei < elem_mangled.len and p < @intCast(usize, 63)) : (ei += @intCast(usize, 1)) {
        buf[p] = elem_mangled[ei]; p += @intCast(usize, 1);
    }
    if (p > @intCast(usize, 63)) p = @intCast(usize, 63);
    var slice_nid = interner_mod.stringInternerIntern(emitter.interner, buf[0..p]);
    var mangled_id = nameManglerMangle(emitter.mangler, slice_nid, @intCast(u8, 2), @intCast(u32, 0));
    var mangled_c_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    var pa: []const u8 = "typedef struct { ";
    bufferedWriterWrite(&emitter.writer, pa);
    bufferedWriterWrite(&emitter.writer, elem_c_name);
    var pb: []const u8 = "* ptr; unsigned int len; } ";
    bufferedWriterWrite(&emitter.writer, pb);
    bufferedWriterWrite(&emitter.writer, mangled_c_name);
    var pc: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, pc);
}
fn emitOptionalType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var op = reg.opt_items[@intCast(usize, ty.payload_idx)];
    var insta_ot_m: []const u8 = "INSTA:optt"; pal.markerWrite(insta_ot_m);
    var insta_ot_b: [10]u8 = undefined; var insta_ot_l = itoa_mod.itoa(op.payload, insta_ot_b[0..]); var insta_ot_s: usize = @intCast(usize, 9) - @intCast(usize, insta_ot_l); pal.markerWrite(insta_ot_b[insta_ot_s..@intCast(usize, 9)]);
    var insta_ot_n: []const u8 = "\n"; pal.markerWrite(insta_ot_n);
    var pay_ty = reg.types_items[@intCast(usize, op.payload)];
    var buf: [64]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    var pref: []const u8 = "Opt_";
    var pi: usize = @intCast(usize, 0);
    while (pi < pref.len and p < @intCast(usize, 63)) : (pi += @intCast(usize, 1)) {
        buf[p] = pref[pi]; p += @intCast(usize, 1);
    }
    var ps_b: [10]u8 = undefined;
    var ps_len = itoa_mod.itoa(op.payload, ps_b[0..]);
    var ps_s: usize = @intCast(usize, 9) - @intCast(usize, ps_len);
    var wi: usize = @intCast(usize, 0);
    while (wi < @intCast(usize, ps_len) and p < @intCast(usize, 63)) : (wi += @intCast(usize, 1)) { buf[p] = ps_b[ps_s + wi]; p += @intCast(usize, 1); }
    if (p > @intCast(usize, 63)) p = @intCast(usize, 63);
    var opt_nid = interner_mod.stringInternerIntern(emitter.interner, buf[0..p]);
    var mangled_id = nameManglerMangle(emitter.mangler, opt_nid, @intCast(u8, 2), @intCast(u32, 0));
    var mangled_c_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
    if (pay_ty.kind == type_mod.TypeKind.void_type) {
        var vfov_m: []const u8 = "VFLOW:opV\n"; pal.markerWrite(vfov_m);
        var s1: []const u8 = "typedef struct { int has_value; } ";
        bufferedWriterWrite(&emitter.writer, s1);
        bufferedWriterWrite(&emitter.writer, mangled_c_name);
        var s2: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, s2);
        return;
    }
    var pay_c_name = getCTypeName(reg, emitter.mangler, op.payload);
    var s1: []const u8 = "typedef struct { ";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, pay_c_name);
    var s2: []const u8 = " value; int has_value; } ";
    bufferedWriterWrite(&emitter.writer, s2);
    bufferedWriterWrite(&emitter.writer, mangled_c_name);
    var s3: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, s3);
}

fn emitErrorUnionType(emitter: *C89Emitter, tid: u32) void {
    var reg = emitter.registry;
    var ty = reg.types_items[@intCast(usize, tid)];
    var ep = reg.eu_items[@intCast(usize, ty.payload_idx)];
    var pay_ty = reg.types_items[@intCast(usize, ep.payload)];
    var pay_c_name = getCTypeName(reg, emitter.mangler, ep.payload);
    var mangled_c_name = getCTypeName(reg, emitter.mangler, tid);
    if (pay_ty.kind == TypeKind.void_type) {
        var s1: []const u8 = "typedef struct { int err; int is_error; } ";
        bufferedWriterWrite(&emitter.writer, s1);
        bufferedWriterWrite(&emitter.writer, mangled_c_name);
        var s3: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, s3);
    } else {
        var s1: []const u8 = "typedef struct { union { ";
        bufferedWriterWrite(&emitter.writer, s1);
        bufferedWriterWrite(&emitter.writer, pay_c_name);
        var s2: []const u8 = " payload; int err; } data; int is_error; } ";
        bufferedWriterWrite(&emitter.writer, s2);
        bufferedWriterWrite(&emitter.writer, mangled_c_name);
        var s3: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, s3);
    }
    reg.types_items[@intCast(usize, tid)].c_name_id = interner_mod.stringInternerIntern(emitter.interner, mangled_c_name);
}

fn mangleLocalName(mangler: *NameMangler, interner: *StringInterner, name_id: u32) []const u8 {
    var name = interner_mod.stringInternerGet(interner, name_id);
    if (hash_mod.u32ToU32MapGet(&mangler.keyword_set, name_id)) |_| {
        var buf: [64]u8 = undefined;
        buf[0] = @intCast(u8, 'z');
        buf[1] = @intCast(u8, '_');
        var i: usize = @intCast(usize, 0);
        while (i < name.len and i + @intCast(usize, 2) < @intCast(usize, 64)) : (i += @intCast(usize, 1)) {
            buf[i + @intCast(usize, 2)] = name[i];
        }
        var mid = interner_mod.stringInternerIntern(interner, buf[0 .. i + @intCast(usize, 2)]);
        return interner_mod.stringInternerGet(interner, mid);
    }
    return name;
}

pub fn emitFunctionSignature(emitter: *C89Emitter, lir_fn: *LirFunction) void {
    var orig = interner_mod.stringInternerGet(emitter.interner, lir_fn.name_id);
    var is_main: u8 = @intCast(u8, 0);
    if (orig.len == @intCast(usize, 4)) {
        if (orig[0] == 'm' and orig[1] == 'a' and orig[2] == 'i' and orig[3] == 'n') is_main = @intCast(u8, 1);
    }
     var fwdm: []const u8 = "FWD:n="; pal.measureMarkerWrite(fwdm); var fwdnb: [10]u8 = undefined; var fwdnl = itoa_mod.itoa(lir_fn.name_id, fwdnb[0..]); var fwdns: usize = @intCast(usize, 9) - @intCast(usize, fwdnl); pal.measureMarkerWrite(fwdnb[fwdns..@intCast(usize, 9)]); var fwdmm: []const u8 = " m="; pal.measureMarkerWrite(fwdmm); var fwdmb: [10]u8 = undefined; var fwdml = itoa_mod.itoa(lir_fn.module_id, fwdmb[0..]); var fwdms: usize = @intCast(usize, 9) - @intCast(usize, fwdml); pal.measureMarkerWrite(fwdmb[fwdms..@intCast(usize, 9)]); var fwdnl2: []const u8 = "\n"; pal.measureMarkerWrite(fwdnl2);
    var fn_mid = nameManglerMangle(emitter.mangler, lir_fn.name_id, @intCast(u8, 0), lir_fn.module_id);
    var fn_name = interner_mod.stringInternerGet(emitter.interner, fn_mid);
     if (lir_fn.is_extern == @intCast(u8, 1)) { fn_name = orig; }

    var sc: []const u8 = "/* ";
    bufferedWriterWrite(&emitter.writer, sc);
    bufferedWriterWrite(&emitter.writer, orig);
    var sd: []const u8 = " */\n";
    bufferedWriterWrite(&emitter.writer, sd);

    var ret_c = getCTypeName(emitter.registry, emitter.mangler, lir_fn.return_type);
    bufferedWriterWrite(&emitter.writer, ret_c);
    var sp: []const u8 = " ";
    bufferedWriterWrite(&emitter.writer, sp);

    bufferedWriterWrite(&emitter.writer, fn_name);

    var op: []const u8 = "(";
    bufferedWriterWrite(&emitter.writer, op);

    if (lir_fn.params.len == @intCast(usize, 0)) {
        if (lir_fn.is_variadic != @intCast(u8, 0)) {
            var vd: []const u8 = "...";
            bufferedWriterWrite(&emitter.writer, vd);
        } else {
            var vd: []const u8 = "void";
            bufferedWriterWrite(&emitter.writer, vd);
        }
    } else {
        var pi: usize = @intCast(usize, 0);
        while (pi < lir_fn.params.len) : (pi += @intCast(usize, 1)) {
            if (pi > @intCast(usize, 0)) {
                var cm: []const u8 = ", ";
                bufferedWriterWrite(&emitter.writer, cm);
            }
            var param = lir_fn.params.items[pi];
            var pt_c = getCTypeName(emitter.registry, emitter.mangler, param.type_id);
            bufferedWriterWrite(&emitter.writer, pt_c);
            var sp2: []const u8 = " ";
            bufferedWriterWrite(&emitter.writer, sp2);
            var pn = mangleLocalName(emitter.mangler, emitter.interner, param.name_id);
            bufferedWriterWrite(&emitter.writer, pn);
        }
        if (lir_fn.is_variadic != @intCast(u8, 0)) {
            if (lir_fn.params.len > @intCast(usize, 0)) {
                var cm: []const u8 = ", ";
                bufferedWriterWrite(&emitter.writer, cm);
            }
            var vd: []const u8 = "...";
            bufferedWriterWrite(&emitter.writer, vd);
        }
    }

    var cl: []const u8 = ") {\n";
    bufferedWriterWrite(&emitter.writer, cl);
    emitter.indent += @intCast(u32, 1);
}

fn emitFunctionForwardDecl(emitter: *C89Emitter, lir_fn: LirFunction) void {
    var ret_c = getCTypeName(emitter.registry, emitter.mangler, lir_fn.return_type);
    bufferedWriterWrite(&emitter.writer, ret_c);
    var sp: []const u8 = " ";
    bufferedWriterWrite(&emitter.writer, sp);
    var fn_mid = nameManglerMangle(emitter.mangler, lir_fn.name_id, @intCast(u8, 0), lir_fn.module_id);
    var fn_name = interner_mod.stringInternerGet(emitter.interner, fn_mid);
    if (lir_fn.is_extern == @intCast(u8, 1)) {
        var orig_c = interner_mod.stringInternerGet(emitter.interner, lir_fn.name_id);
        fn_name = orig_c;
    }
    bufferedWriterWrite(&emitter.writer, fn_name);
    var op: []const u8 = "(";
    bufferedWriterWrite(&emitter.writer, op);
    if (lir_fn.params.len == @intCast(usize, 0)) {
        if (lir_fn.is_variadic != @intCast(u8, 0)) {
            var vd: []const u8 = "...";
            bufferedWriterWrite(&emitter.writer, vd);
        } else {
            var vd: []const u8 = "void";
            bufferedWriterWrite(&emitter.writer, vd);
        }
    } else {
        var pi: usize = @intCast(usize, 0);
        while (pi < lir_fn.params.len) : (pi += @intCast(usize, 1)) {
            if (pi > @intCast(usize, 0)) {
                var cm: []const u8 = ", ";
                bufferedWriterWrite(&emitter.writer, cm);
            }
            var param = lir_fn.params.items[pi];
            var pt_c = getCTypeName(emitter.registry, emitter.mangler, param.type_id);
            bufferedWriterWrite(&emitter.writer, pt_c);
        }
        if (lir_fn.is_variadic != @intCast(u8, 0)) {
            var cm: []const u8 = ", ";
            bufferedWriterWrite(&emitter.writer, cm);
            var vd: []const u8 = "...";
            bufferedWriterWrite(&emitter.writer, vd);
        }
    }
    var rp: []const u8 = ");\n";
    bufferedWriterWrite(&emitter.writer, rp);
}

fn faultIn(emitter: *C89Emitter, idx: usize) LirFunction {
    return lir_stream_mod.lirStreamReadFunction(emitter.spill, emitter.fn_slots[emitter.fn_slots_start + idx], emitter.spill_arena);
}

fn moduleHasVaInsts(emitter: *C89Emitter) u8 {
    var vi: usize = @intCast(usize, 0);
    while (vi < emitter.fn_slots_len) : (vi += @intCast(usize, 1)) {
        var vf = faultIn(emitter, vi);
        var vbi: usize = @intCast(usize, 0);
        while (vbi < vf.blocks.len) : (vbi += @intCast(usize, 1)) {
            var vbb = &vf.blocks.items[vbi];
            var vii: usize = @intCast(usize, 0);
            while (vii < vbb.insts.len) : (vii += @intCast(usize, 1)) {
                switch (vbb.insts.items[vii]) {
                    .va_start => return @intCast(u8, 1),
                    .va_arg => return @intCast(u8, 1),
                    .va_end => return @intCast(u8, 1),
                    else => {},
                }
            }
        }
    }
    return @intCast(u8, 0);
}

fn emitStdargInclude(emitter: *C89Emitter) void {
    if (moduleHasVaInsts(emitter) != @intCast(u8, 0)) {
        var va_inc: []const u8 = "#include <stdarg.h>\n";
        bufferedWriterWrite(&emitter.writer, va_inc);
    }
}

fn moduleHasStdioBuiltin(emitter: *C89Emitter) u8 {
    var vi: usize = @intCast(usize, 0);
    while (vi < emitter.fn_slots_len) : (vi += @intCast(usize, 1)) {
        var vf = faultIn(emitter, vi);
        var vbi: usize = @intCast(usize, 0);
        while (vbi < vf.blocks.len) : (vbi += @intCast(usize, 1)) {
            var vbb = &vf.blocks.items[vbi];
            var vii: usize = @intCast(usize, 0);
            while (vii < vbb.insts.len) : (vii += @intCast(usize, 1)) {
                switch (vbb.insts.items[vii]) {
                    .builtin_put_char => return @intCast(u8, 1),
                    .builtin_stdout_write => return @intCast(u8, 1),
                    .builtin_stderr_write => return @intCast(u8, 1),
                    .builtin_get_char => return @intCast(u8, 1),
                    else => {},
                }
            }
        }
    }
    return @intCast(u8, 0);
}

fn moduleHasExitBuiltin(emitter: *C89Emitter) u8 {
    var vi: usize = @intCast(usize, 0);
    while (vi < emitter.fn_slots_len) : (vi += @intCast(usize, 1)) {
        var vf = faultIn(emitter, vi);
        var vbi: usize = @intCast(usize, 0);
        while (vbi < vf.blocks.len) : (vbi += @intCast(usize, 1)) {
            var vbb = &vf.blocks.items[vbi];
            var vii: usize = @intCast(usize, 0);
            while (vii < vbb.insts.len) : (vii += @intCast(usize, 1)) {
                switch (vbb.insts.items[vii]) {
                    .builtin_exit => return @intCast(u8, 1),
                    else => {},
                }
            }
        }
    }
    return @intCast(u8, 0);
}

fn moduleHasSleepBuiltin(emitter: *C89Emitter) u8 {
    var vi: usize = @intCast(usize, 0);
    while (vi < emitter.fn_slots_len) : (vi += @intCast(usize, 1)) {
        var vf = faultIn(emitter, vi);
        var vbi: usize = @intCast(usize, 0);
        while (vbi < vf.blocks.len) : (vbi += @intCast(usize, 1)) {
            var vbb = &vf.blocks.items[vbi];
            var vii: usize = @intCast(usize, 0);
            while (vii < vbb.insts.len) : (vii += @intCast(usize, 1)) {
                switch (vbb.insts.items[vii]) {
                    .builtin_sleep_ms => return @intCast(u8, 1),
                    else => {},
                }
            }
        }
    }
    return @intCast(u8, 0);
}

fn moduleHasConsoleBuiltin(emitter: *C89Emitter) u8 {
    var vi: usize = @intCast(usize, 0);
    while (vi < emitter.fn_slots_len) : (vi += @intCast(usize, 1)) {
        var vf = faultIn(emitter, vi);
        var vbi: usize = @intCast(usize, 0);
        while (vbi < vf.blocks.len) : (vbi += @intCast(usize, 1)) {
            var vbb = &vf.blocks.items[vbi];
            var vii: usize = @intCast(usize, 0);
            while (vii < vbb.insts.len) : (vii += @intCast(usize, 1)) {
                switch (vbb.insts.items[vii]) {
                    .builtin_console_clear => return @intCast(u8, 1),
                    .builtin_console_gotoxy => return @intCast(u8, 1),
                    .builtin_console_set_color => return @intCast(u8, 1),
                    else => {},
                }
            }
        }
    }
    return @intCast(u8, 0);
}

fn moduleHasNetBuiltin(emitter: *C89Emitter) u8 {
    var vi: usize = @intCast(usize, 0);
    while (vi < emitter.fn_slots_len) : (vi += @intCast(usize, 1)) {
        var vf = faultIn(emitter, vi);
        var vbi: usize = @intCast(usize, 0);
        while (vbi < vf.blocks.len) : (vbi += @intCast(usize, 1)) {
            var vbb = &vf.blocks.items[vbi];
            var vii: usize = @intCast(usize, 0);
            while (vii < vbb.insts.len) : (vii += @intCast(usize, 1)) {
                switch (vbb.insts.items[vii]) {
                    .builtin_socket_create => return @intCast(u8, 1),
                    .builtin_socket_bind_listen => return @intCast(u8, 1),
                    .builtin_socket_accept => return @intCast(u8, 1),
                    .builtin_socket_connect => return @intCast(u8, 1),
                    .builtin_socket_send => return @intCast(u8, 1),
                    .builtin_socket_recv => return @intCast(u8, 1),
                    .builtin_socket_select => return @intCast(u8, 1),
                    .builtin_socket_fd_zero => return @intCast(u8, 1),
                    .builtin_socket_fd_set => return @intCast(u8, 1),
                    .builtin_socket_fd_isset => return @intCast(u8, 1),
                    .builtin_socket_close => return @intCast(u8, 1),
                    else => {},
                }
            }
        }
    }
    return @intCast(u8, 0);
}

fn emitBuiltinIncludes(emitter: *C89Emitter) void {
    if (moduleHasStdioBuiltin(emitter) != @intCast(u8, 0)) {
        var stdio_inc: []const u8 = "#include <stdio.h>\n";
        bufferedWriterWrite(&emitter.writer, stdio_inc);
    }
    if (moduleHasExitBuiltin(emitter) != @intCast(u8, 0)) {
        var stdlib_inc: []const u8 = "#include <stdlib.h>\n";
        bufferedWriterWrite(&emitter.writer, stdlib_inc);
    }
    if (moduleHasSleepBuiltin(emitter) != @intCast(u8, 0)) {
        var swin: []const u8 = "#ifdef _WIN32\n#include <windows.h>\n#else\n#include <unistd.h>\n#endif\n";
        bufferedWriterWrite(&emitter.writer, swin);
    }
    if (moduleHasConsoleBuiltin(emitter) != @intCast(u8, 0)) {
        var cwin: []const u8 = "#ifdef _WIN32\n#define WINVER 0x0410\n#define _WIN32_WINDOWS 0x0410\n#define _WIN32_WINNT 0x0400\n#define NTDDI_VERSION 0x04000000\n#define WIN32_LEAN_AND_MEAN\n#include <windows.h>\n#else\n#include <stdio.h>\n#endif\nextern void std_print_len(const char* s, unsigned int len);\n";
        bufferedWriterWrite(&emitter.writer, cwin);
    }
    if (moduleHasNetBuiltin(emitter) != @intCast(u8, 0)) {
        var swin: []const u8 = "#ifdef _WIN32\n#define WIN32_LEAN_AND_MEAN\n#include <windows.h>\n#include <winsock.h>\n#pragma comment(lib, \"wsock32.lib\")\n#else\n#include <sys/socket.h>\n#include <netinet/in.h>\n#include <arpa/inet.h>\n#include <sys/select.h>\n#include <unistd.h>\n#include <fcntl.h>\n#endif\n#include <string.h>\n";
        bufferedWriterWrite(&emitter.writer, swin);
    }
}

fn emitModuleHeader(emitter: *C89Emitter, name: []const u8, c_includes: []u32) void {
    var s1: []const u8 = "/* Module: ";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, name);
    var s2: []const u8 = " */\n#include \"zig_compat.h\"\n#include \"zig_special_types.h\"\n";
    bufferedWriterWrite(&emitter.writer, s2);
    emitStdargInclude(emitter);
    emitBuiltinIncludes(emitter);
    var ci: usize = @intCast(usize, 0);
    while (ci < c_includes.len) : (ci += @intCast(usize, 1)) {
        var inc_id = c_includes[ci];
        var inc_str = interner_mod.stringInternerGet(emitter.interner, inc_id);
        var is1: []const u8 = "#include ";
        bufferedWriterWrite(&emitter.writer, is1);
        if (inc_str.len > @intCast(usize, 0)) {
            if (inc_str.ptr[0] == @intCast(u8, '<')) {
                bufferedWriterWrite(&emitter.writer, inc_str);
            } else {
                var qs: []const u8 = "\"";
                bufferedWriterWrite(&emitter.writer, qs);
                bufferedWriterWrite(&emitter.writer, inc_str);
                bufferedWriterWrite(&emitter.writer, qs);
            }
        }
        var inl: []const u8 = "\n";
        bufferedWriterWrite(&emitter.writer, inl);
    }
    var s3: []const u8 = "\n/* Forward declarations */\n";
    bufferedWriterWrite(&emitter.writer, s3);
    var i: usize = @intCast(usize, 0);
    while (i < emitter.fn_slots_len) : (i += @intCast(usize, 1)) {
        var f = faultIn(emitter, i);
        if (f.is_extern == @intCast(u8, 0) or f.is_variadic != @intCast(u8, 0)) {
            emitFunctionForwardDecl(emitter, f);
        }
    }
    var nl: []const u8 = "\n";
    bufferedWriterWrite(&emitter.writer, nl);
}

fn emitModuleFooter(emitter: *C89Emitter) void {
    var s: []const u8 = "/* EOF */\n";
    bufferedWriterWrite(&emitter.writer, s);
}

pub fn moduleQualifiedName(emitter: *C89Emitter, module_id: u32) []const u8 {
    var mods = mr_mod.moduleRegistryGetModules(emitter.module_reg);
    var path_str = interner_mod.stringInternerGet(emitter.interner, mods[@intCast(usize, module_id)].path_id);
    var last_slash: usize = @intCast(usize, 0);
    var has_slash: u8 = @intCast(u8, 0);
    var ps_i: usize = @intCast(usize, 0);
    while (ps_i < path_str.len) : (ps_i += @intCast(usize, 1)) {
        if (path_str[ps_i] == @intCast(u8, '/')) { last_slash = ps_i; has_slash = @intCast(u8, 1); }
    }
    var base: []const u8 = undefined;
    if (has_slash != @intCast(u8, 0)) {
        var dbl_start: usize = last_slash + @intCast(usize, 1);
        base = path_str[dbl_start..path_str.len];
    } else {
        base = path_str;
    }
    var bl = base.len;
    if (bl >= @intCast(usize, 4) and base[bl - @intCast(usize, 4)] == @intCast(u8, '.') and base[bl - @intCast(usize, 3)] == @intCast(u8, 'z') and base[bl - @intCast(usize, 2)] == @intCast(u8, 'i') and base[bl - @intCast(usize, 1)] == @intCast(u8, 'g')) {
        var bl4: usize = bl - @intCast(usize, 4);
        base = base[0..bl4];
    } else if (bl >= @intCast(usize, 4) and base[bl - @intCast(usize, 4)] == @intCast(u8, '.') and base[bl - @intCast(usize, 3)] == @intCast(u8, 'z') and base[bl - @intCast(usize, 2)] == @intCast(u8, '9') and base[bl - @intCast(usize, 1)] == @intCast(u8, '8')) {
        var bl4: usize = bl - @intCast(usize, 4);
        base = base[0..bl4];
    }
    bl = base.len;
    if (bl > @intCast(usize, 64)) {
        base = base[0..@intCast(usize, 64)];
    }
    var hash = hash_mod.fnv1a(path_str);
    var buf: [96]u8 = undefined;
    var pos: usize = @intCast(usize, 0);
    var bi: usize = @intCast(usize, 0);
    while (bi < base.len) : (bi += @intCast(usize, 1)) {
        buf[pos] = base[bi];
        pos += @intCast(usize, 1);
    }
    buf[pos] = @intCast(u8, '_');
    pos += @intCast(usize, 1);
    writeHex(buf[0..], &pos, hash);
    var qid = interner_mod.stringInternerIntern(emitter.interner, buf[0..pos]);
    return interner_mod.stringInternerGet(emitter.interner, qid);
}

pub fn emitModuleHeaderFile(emitter: *C89Emitter, module_id: u32, mod_name: []const u8, c_includes: []u32, dep_mod_ids: []u32, sorted: [*]u32) void {
    var gname: [128]u8 = undefined;
    var gn: usize = @intCast(usize, 0);
    var g_i: usize = @intCast(usize, 0);
    while (g_i < mod_name.len and gn < @intCast(usize, 127)) : (g_i += @intCast(usize, 1)) {
        var c = mod_name[g_i];
        if (c >= @intCast(u8, 'a') and c <= @intCast(u8, 'z')) {
            gname[gn] = c - @intCast(u8, 'a') + @intCast(u8, 'A');
        } else if ((c >= @intCast(u8, 'A') and c <= @intCast(u8, 'Z')) or (c >= @intCast(u8, '0') and c <= @intCast(u8, '9'))) {
            gname[gn] = c;
        } else {
            gname[gn] = @intCast(u8, '_');
        }
        gn += @intCast(usize, 1);
    }
    var m0: []const u8 = "#ifndef ZIG_MODULE_"; bufferedWriterWrite(&emitter.writer, m0);
    bufferedWriterWrite(&emitter.writer, gname[0..gn]);
    var m1: []const u8 = "_H\n#define ZIG_MODULE_"; bufferedWriterWrite(&emitter.writer, m1);
    bufferedWriterWrite(&emitter.writer, gname[0..gn]);
    var m2: []const u8 = "_H\n\n"; bufferedWriterWrite(&emitter.writer, m2);
    var h0: []const u8 = "#include \"zig_compat.h\"\n#include \"zig_special_types.h\"\n";
    bufferedWriterWrite(&emitter.writer, h0);
    emitStdargInclude(emitter);
    var ci: usize = @intCast(usize, 0);
    while (ci < c_includes.len) : (ci += @intCast(usize, 1)) {
        var inc_id = c_includes[ci];
        var inc_str = interner_mod.stringInternerGet(emitter.interner, inc_id);
        var is1: []const u8 = "#include ";
        bufferedWriterWrite(&emitter.writer, is1);
        if (inc_str.len > @intCast(usize, 0)) {
            if (inc_str.ptr[0] == @intCast(u8, '<')) {
                bufferedWriterWrite(&emitter.writer, inc_str);
            } else {
                var qs: []const u8 = "\"";
                bufferedWriterWrite(&emitter.writer, qs);
                bufferedWriterWrite(&emitter.writer, inc_str);
                bufferedWriterWrite(&emitter.writer, qs);
            }
        }
        var inl: []const u8 = "\n";
        bufferedWriterWrite(&emitter.writer, inl);
    }
    var di: usize = @intCast(usize, 0);
    while (di < dep_mod_ids.len) : (di += @intCast(usize, 1)) {
        var d = dep_mod_ids[di];
        if (d == module_id) continue;
        var dstem = moduleQualifiedName(emitter, d);
        var ic0: []const u8 = "#include \"";
        bufferedWriterWrite(&emitter.writer, ic0);
        bufferedWriterWrite(&emitter.writer, dstem);
        var ic1: []const u8 = ".h\"\n";
        bufferedWriterWrite(&emitter.writer, ic1);
    }
    var dn: []const u8 = "\n";
    bufferedWriterWrite(&emitter.writer, dn);
    var tsi: usize = @intCast(usize, 0);
    while (tsi < emitter.registry.types_len) : (tsi += @intCast(usize, 1)) {
        var tid = sorted[tsi];
        var ty = emitter.registry.types_items[@intCast(usize, tid)];
        if (ty.name_id == @intCast(u32, 0)) continue;
        if (ty.module_id != module_id) continue;
        if (ty.kind != TypeKind.struct_type and ty.kind != TypeKind.tagged_union_type and ty.kind != TypeKind.union_type and ty.kind != TypeKind.enum_type and ty.kind != TypeKind.error_set_type) continue;
        if (hash_mod.u32ToU32MapGet(&emitter.pointer_only_map, tid) == null) continue;
        if (hash_mod.u32ToU32MapGet(&emitter.shared_set, tid) != null) continue;
        var cname = getCTypeName(emitter.registry, emitter.mangler, tid);
        var dedup_key: u32 = @intCast(u32, 0);
        var h_ci: usize = @intCast(usize, 0);
        while (h_ci < cname.len) : (h_ci += @intCast(usize, 1)) {
            dedup_key = dedup_key * @intCast(u32, 31) + @intCast(u32, cname[h_ci]);
        }
        if (hash_mod.u32ToU32MapGet(&emitter.emitted_type_set, dedup_key)) |_| continue;
        hash_mod.u32ToU32MapPut(&emitter.emitted_type_set, dedup_key, @intCast(u32, 1));
        var g0: []const u8 = "#ifndef "; bufferedWriterWrite(&emitter.writer, g0);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g1: []const u8 = "\n#define "; bufferedWriterWrite(&emitter.writer, g1);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g2: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, g2);
        emitTypeDefinition(emitter, tid);
        var g3: []const u8 = "#endif /* "; bufferedWriterWrite(&emitter.writer, g3);
        ctypeGuardWrite(&emitter.writer, ty.kind);
        bufferedWriterWrite(&emitter.writer, cname);
        var g4: []const u8 = " */\n"; bufferedWriterWrite(&emitter.writer, g4);
    }
    var tn: []const u8 = "\n";
    bufferedWriterWrite(&emitter.writer, tn);
    var fwd0: []const u8 = "/* Forward declarations */\n";
    bufferedWriterWrite(&emitter.writer, fwd0);
    var fi: usize = @intCast(usize, 0);
    while (fi < emitter.fn_slots_len) : (fi += @intCast(usize, 1)) {
        var f = faultIn(emitter, fi);
        if (f.is_extern == @intCast(u8, 0) or f.is_variadic != @intCast(u8, 0)) {
            emitFunctionForwardDecl(emitter, f);
        }
    }
    var gd0: []const u8 = "/* Storage globals (extern decls) */\n";
    bufferedWriterWrite(&emitter.writer, gd0);
    var gg_set = hash_mod.u32ToU32MapInit(emitter.alloc);
    var ggi: u32 = @intCast(u32, 0);
    while (ggi < emitter.global_decls_len) : (ggi += @intCast(u32, 1)) {
        var ggl = emitter.global_decls[@intCast(usize, ggi)];
        var ggl_is_ts: u8 = @intCast(u8, 0);
        if (ggl.type_id < @intCast(u32, emitter.registry.types_len)) {
            var ggl_ty = emitter.registry.types_items[@intCast(usize, ggl.type_id)];
            if (ggl_ty.name_id != @intCast(u32, 0) and ggl_ty.name_id == ggl.name_id) ggl_is_ts = @intCast(u8, 1);
        }
        if (ggl_is_ts == @intCast(u8, 0)) {
            if (ggl.module_id != module_id) continue;
        } else {
            var ggl_ty = emitter.registry.types_items[@intCast(usize, ggl.type_id)];
            if (ggl_ty.module_id != module_id) continue;
        }
        var gg_mid = nameManglerMangleGlobal(emitter.mangler, emitter.registry, ggl.name_id, ggl.module_id, ggl.type_id);
        if (hash_mod.u32ToU32MapGet(&gg_set, gg_mid) != null) continue;
        hash_mod.u32ToU32MapPut(&gg_set, gg_mid, @intCast(u32, 1));
        var gg_name = interner_mod.stringInternerGet(emitter.interner, gg_mid);
        var gg_type = getCTypeName(emitter.registry, emitter.mangler, ggl.type_id);
        bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 0));
        var gg_x: []const u8 = "extern ";
        bufferedWriterWrite(&emitter.writer, gg_x);
        bufferedWriterWrite(&emitter.writer, gg_type);
        var gg_sp: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, gg_sp);
        bufferedWriterWrite(&emitter.writer, gg_name);
        var gg_sc: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, gg_sc);
    }
    var tsi2: u32 = @intCast(u32, 0);
    while (@intCast(usize, tsi2) < emitter.registry.types_len) : (tsi2 += @intCast(u32, 1)) {
        if (hash_mod.u32ToU32MapGet(&emitter.ts_ref_set, tsi2) == null) continue;
        var tsty = emitter.registry.types_items[@intCast(usize, tsi2)];
        if (tsty.name_id == @intCast(u32, 0)) continue;
        if (tsty.module_id != module_id) continue;
        var tsgmid = nameManglerMangleGlobal(emitter.mangler, emitter.registry, tsty.name_id, tsty.module_id, tsi2);
        if (hash_mod.u32ToU32MapGet(&gg_set, tsgmid) != null) continue;
        hash_mod.u32ToU32MapPut(&gg_set, tsgmid, @intCast(u32, 1));
        var tsgname = interner_mod.stringInternerGet(emitter.interner, tsgmid);
        var tsgtype = getCTypeName(emitter.registry, emitter.mangler, tsi2);
        bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 0));
        var tsgx: []const u8 = "extern ";
        bufferedWriterWrite(&emitter.writer, tsgx);
        bufferedWriterWrite(&emitter.writer, tsgtype);
        var tsg_sp: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, tsg_sp);
        bufferedWriterWrite(&emitter.writer, tsgname);
        var tsg_sc: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, tsg_sc);
    }
    var fnl: []const u8 = "\n";
    bufferedWriterWrite(&emitter.writer, fnl);
    var e0: []const u8 = "#endif /* ZIG_MODULE_";
    bufferedWriterWrite(&emitter.writer, e0);
    bufferedWriterWrite(&emitter.writer, gname[0..gn]);
    var e1: []const u8 = "_H */\n";
    bufferedWriterWrite(&emitter.writer, e1);
}

pub fn emitModule(emitter: *C89Emitter, name: []const u8, c_includes: []u32, ptr_only_ids: [*]u32, ptr_only_len: u32) void {
    var poi: u32 = @intCast(u32, 0);
    while (poi < ptr_only_len) : (poi += 1) {
        hash_mod.u32ToU32MapPut(&emitter.pointer_only_map, ptr_only_ids[@intCast(usize, poi)], @intCast(u32, 1));
    }
    var sorted: [*]u32 = tstTopologicalSort(emitter.registry, emitter.alloc);
    emitErrorCodePrologue(emitter);
    emitSpecialTypes(emitter, emitter.registry, sorted);
    emitModuleHeader(emitter, name, c_includes);
    emitGlobalDecls(emitter, @intCast(u32, 0), @intCast(u8, 1));
    var i: usize = @intCast(usize, 0);
    while (i < emitter.fn_slots_len) : (i += @intCast(usize, 1)) {
        var func = faultIn(emitter, i);
        emitter.switch_cases = &func.switch_cases;
        if (func.is_extern == @intCast(u8, 0)) {
            emitFunctionSignature(emitter, &func);
            emitHoistedDecls(emitter, &func);
            var ft = emitter.registry.types_items[@intCast(usize, func.return_type)];
            if (ft.kind == type_mod.TypeKind.slice_type) {
                var rm: []const u8 = "R:"; pal.markerWrite(rm);
                var rnb: [10]u8 = undefined; var rnl = itoa_mod.itoa(func.name_id, rnb[0..]); var rns: usize = @intCast(usize, 9) - @intCast(usize, rnl); pal.markerWrite(rnb[rns..@intCast(usize, 9)]);
                var rd2: []const u8 = "\n"; pal.markerWrite(rd2);
            }
            emitter.dl_hoisted = @intCast(u8, 0);
            emitFunctionBody(emitter, &func);
        }
            if (func.is_pub == @intCast(u8, 1)) {
                var wr_name = interner_mod.stringInternerGet(emitter.interner, func.name_id);
                if (wr_name.len == @intCast(usize, 4) and wr_name[0] == 'm' and wr_name[1] == 'a' and wr_name[2] == 'i' and wr_name[3] == 'n') {
                    emitMainWrapper(emitter, func);
                }
            }
    }
    emitModuleFooter(emitter);
}

fn emitMainWrapper(emitter: *C89Emitter, func: LirFunction) void {
    var wur_name = interner_mod.stringInternerGet(emitter.interner, func.name_id);
    if (wur_name.len == @intCast(usize, 4) and wur_name[0] == 'm' and wur_name[1] == 'a' and wur_name[2] == 'i' and wur_name[3] == 'n') {
        var wfn_mid = nameManglerMangle(emitter.mangler, func.name_id, @intCast(u8, 0), func.module_id);
        var wfn_name = interner_mod.stringInternerGet(emitter.interner, wfn_mid);
        var wrty = emitter.registry.types_items[@intCast(usize, func.return_type)];
        var wsig0: []const u8 = "int main(void) {\n";
        var wsig1: []const u8 = "int main(int argc, char** argv) {\n";
        var wcall0: []const u8 = "();\n";
        var wsig: []const u8 = wsig0;
        var wcall: []const u8 = wcall0;
        var w_argv_cast: []const u8 = "argv";
        if (func.params.len > @intCast(usize, 0)) {
            wsig = wsig1;
            if (func.params.len > @intCast(usize, 1) and func.params.items[@intCast(usize, 1)].type_id != @intCast(u32, 0)) {
                var wac = getCTypeName(emitter.registry, emitter.mangler, func.params.items[@intCast(usize, 1)].type_id);
                var wc_buf: [128]u8 = undefined;
                var wci: usize = @intCast(usize, 0);
                wc_buf[0] = @intCast(u8, '(');
                wci += @intCast(usize, 1);
                var wcj: usize = @intCast(usize, 0);
                while (wcj < wac.len and wci + @intCast(usize, 1) < @intCast(usize, 126)) : (wcj += @intCast(usize, 1)) { wc_buf[wci] = wac[wcj]; wci += @intCast(usize, 1); }
                wc_buf[wci] = @intCast(u8, ')'); wci += @intCast(usize, 1);
                wc_buf[wci] = @intCast(u8, 'a'); wci += @intCast(usize, 1);
                wc_buf[wci] = @intCast(u8, 'r'); wci += @intCast(usize, 1);
                wc_buf[wci] = @intCast(u8, 'g'); wci += @intCast(usize, 1);
                wc_buf[wci] = @intCast(u8, 'v'); wci += @intCast(usize, 1);
                var wc_mid = interner_mod.stringInternerIntern(emitter.interner, wc_buf[0..wci]);
                w_argv_cast = interner_mod.stringInternerGet(emitter.interner, wc_mid);
            }
            var wc1_buf: [256]u8 = undefined;
            var wc1i: usize = @intCast(usize, 0);
            var wc1pre: [7]u8 = [7]u8{ '(', 'a', 'r', 'g', 'c', ',', ' ' };
            while (wc1i < @intCast(usize, 7)) : (wc1i += @intCast(usize, 1)) { wc1_buf[wc1i] = wc1pre[wc1i]; }
            var wc1j: usize = @intCast(usize, 0);
            while (wc1j < w_argv_cast.len and wc1i + @intCast(usize, 1) < @intCast(usize, 250)) : (wc1j += @intCast(usize, 1)) { wc1_buf[wc1i] = w_argv_cast[wc1j]; wc1i += @intCast(usize, 1); }
            wc1_buf[wc1i] = @intCast(u8, ')'); wc1i += @intCast(usize, 1);
            wc1_buf[wc1i] = @intCast(u8, ';'); wc1i += @intCast(usize, 1);
            wc1_buf[wc1i] = @intCast(u8, '\n'); wc1i += @intCast(usize, 1);
            var wc1_mid = interner_mod.stringInternerIntern(emitter.interner, wc1_buf[0..wc1i]);
            var wcall1: []const u8 = interner_mod.stringInternerGet(emitter.interner, wc1_mid);
            wcall = wcall1;
        }
        bufferedWriterWrite(&emitter.writer, wsig);
        emitModuleInitCalls(emitter);
        if (wrty.kind == type_mod.TypeKind.void_type) {
            bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 1));
            bufferedWriterWrite(&emitter.writer, wfn_name);
            bufferedWriterWrite(&emitter.writer, wcall);
            bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 1));
            var wv2: []const u8 = "return 0;\n"; bufferedWriterWrite(&emitter.writer, wv2);
        } else if (wrty.kind == type_mod.TypeKind.error_union_type) {
            var weu_c = getCTypeName(emitter.registry, emitter.mangler, func.return_type);
            var wep = emitter.registry.eu_items[@intCast(usize, wrty.payload_idx)];
            var wpay = emitter.registry.types_items[@intCast(usize, wep.payload)];
            bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 1));
            bufferedWriterWrite(&emitter.writer, weu_c);
            var we1: []const u8 = " zT_main_result;\n"; bufferedWriterWrite(&emitter.writer, we1);
            bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 1));
            var we2: []const u8 = "zT_main_result = "; bufferedWriterWrite(&emitter.writer, we2);
            bufferedWriterWrite(&emitter.writer, wfn_name);
            bufferedWriterWrite(&emitter.writer, wcall);
            bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 1));
            if (wpay.kind == type_mod.TypeKind.void_type) {
                var we4: []const u8 = "return zT_main_result.is_error ? zT_main_result.err : 0;\n"; bufferedWriterWrite(&emitter.writer, we4);
            } else {
                var we5: []const u8 = "return zT_main_result.is_error ? zT_main_result.data.err : (int)zT_main_result.data.payload;\n"; bufferedWriterWrite(&emitter.writer, we5);
            }
        } else {
            bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 1));
            var wi1: []const u8 = "return (int)"; bufferedWriterWrite(&emitter.writer, wi1);
            bufferedWriterWrite(&emitter.writer, wfn_name);
            bufferedWriterWrite(&emitter.writer, wcall);
        }
        var ws4: []const u8 = "}\n\n"; bufferedWriterWrite(&emitter.writer, ws4);
        var wm: []const u8 = "WRAP:main\n"; pal.markerWrite(wm);
    }
}

fn emitGlobalDecls(emitter: *C89Emitter, module_id: u32, all: u8) void {
    var gd_set = hash_mod.u32ToU32MapInit(emitter.alloc);
    var gi: u32 = @intCast(u32, 0);
    while (gi < emitter.global_decls_len) : (gi += @intCast(u32, 1)) {
        var g = emitter.global_decls[@intCast(usize, gi)];
        var is_ts: u8 = @intCast(u8, 0);
        if (g.type_id < @intCast(u32, emitter.registry.types_len)) {
            var gty = emitter.registry.types_items[@intCast(usize, g.type_id)];
            if (gty.name_id != @intCast(u32, 0) and gty.name_id == g.name_id) is_ts = @intCast(u8, 1);
        }
        if (is_ts == @intCast(u8, 1)) {
            if (all == @intCast(u8, 0)) {
                var owner_mid = emitter.registry.types_items[@intCast(usize, g.type_id)].module_id;
                if (module_id != owner_mid) continue;
            }
        } else {
            if (all == @intCast(u8, 0) and g.module_id != module_id) continue;
        }
        var gmid = nameManglerMangleGlobal(emitter.mangler, emitter.registry, g.name_id, g.module_id, g.type_id);
        if (hash_mod.u32ToU32MapGet(&gd_set, gmid) != null) continue;
        hash_mod.u32ToU32MapPut(&gd_set, gmid, @intCast(u32, 1));
        var gname = interner_mod.stringInternerGet(emitter.interner, gmid);
        var gtype = getCTypeName(emitter.registry, emitter.mangler, g.type_id);
        bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 0));
        bufferedWriterWrite(&emitter.writer, gtype);
        var sp: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, sp);
        bufferedWriterWrite(&emitter.writer, gname);
        var sc: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, sc);
    }
    var tsgi: u32 = @intCast(u32, 0);
    while (@intCast(usize, tsgi) < emitter.registry.types_len) : (tsgi += @intCast(u32, 1)) {
        if (hash_mod.u32ToU32MapGet(&emitter.ts_ref_set, tsgi) == null) continue;
        var tsty = emitter.registry.types_items[@intCast(usize, tsgi)];
        if (tsty.name_id == @intCast(u32, 0)) continue;
        if (all == @intCast(u8, 0)) {
            if (module_id != tsty.module_id) continue;
        }
        var tsgmid = nameManglerMangleGlobal(emitter.mangler, emitter.registry, tsty.name_id, tsty.module_id, tsgi);
        if (hash_mod.u32ToU32MapGet(&gd_set, tsgmid) != null) continue;
        hash_mod.u32ToU32MapPut(&gd_set, tsgmid, @intCast(u32, 1));
        var tsgname = interner_mod.stringInternerGet(emitter.interner, tsgmid);
        var tsgtype = getCTypeName(emitter.registry, emitter.mangler, tsgi);
        bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 0));
        bufferedWriterWrite(&emitter.writer, tsgtype);
        var tssp: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, tssp);
        bufferedWriterWrite(&emitter.writer, tsgname);
        var tssc: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, tssc);
    }
}

fn moduleHasRuntimeInit(emitter: *C89Emitter, module_id: u32) bool {
    var gi: u32 = @intCast(u32, 0);
    while (gi < emitter.global_decls_len) : (gi += @intCast(u32, 1)) {
        var g = emitter.global_decls[@intCast(usize, gi)];
        if (g.module_id == module_id and g.has_runtime_init != @intCast(u8, 0)) return true;
    }
    return false;
}

fn emitModuleInitCalls(emitter: *C89Emitter) void {
    var mm = mr_mod.moduleRegistryGetModules(emitter.module_reg);
    var mi2: usize = @intCast(usize, 0);
    while (mi2 < mm.len) : (mi2 += @intCast(usize, 1)) {
        if (moduleHasRuntimeInit(emitter, mm[mi2].id)) {
            var mi_s: []const u8 = "__module_init";
            var mi_id = interner_mod.stringInternerIntern(emitter.interner, mi_s);
            var mi_mid = nameManglerMangle(emitter.mangler, mi_id, @intCast(u8, 0), mm[mi2].id);
            var mi_name = interner_mod.stringInternerGet(emitter.interner, mi_mid);
            bufferedWriterWriteIndent(&emitter.writer, @intCast(u32, 1));
            bufferedWriterWrite(&emitter.writer, mi_name);
            var mi_cc: []const u8 = "();\n";
            bufferedWriterWrite(&emitter.writer, mi_cc);
        }
    }
}

pub fn emitModuleFile(emitter: *C89Emitter, module_id: u32, mod_name: []const u8) void {
    var h0: []const u8 = "#include \"";
    bufferedWriterWrite(&emitter.writer, h0);
    bufferedWriterWrite(&emitter.writer, mod_name);
    var h1: []const u8 = ".h\"\n";
    bufferedWriterWrite(&emitter.writer, h1);
    emitStdargInclude(emitter);
    emitBuiltinIncludes(emitter);
    emitGlobalDecls(emitter, module_id, @intCast(u8, 0));
    var i: usize = @intCast(usize, 0);
    while (i < emitter.fn_slots_len) : (i += @intCast(usize, 1)) {
        var f = faultIn(emitter, i);
        if (f.is_extern != @intCast(u8, 0)) continue;
        emitter.switch_cases = &f.switch_cases;
        emitFunctionSignature(emitter, &f);
        emitHoistedDecls(emitter, &f);
        emitter.dl_hoisted = @intCast(u8, 0);
        emitFunctionBody(emitter, &f);
        if (module_id == @intCast(u32, 0) and f.is_pub == @intCast(u8, 1)) {
            var wmn = interner_mod.stringInternerGet(emitter.interner, f.name_id);
            if (wmn.len == @intCast(usize, 4) and wmn[0] == 'm' and wmn[1] == 'a' and wmn[2] == 'i' and wmn[3] == 'n') {
                emitMainWrapper(emitter, f);
            }
        }
    }
    emitModuleFooter(emitter);
}

fn mangleTempName(interner: *StringInterner, temp_id: u32) []const u8 {
    var buf: [20]u8 = undefined;
    buf[0] = @intCast(u8, 'z');
    buf[1] = @intCast(u8, 'T');
    buf[2] = @intCast(u8, '_');
    var len = itoa_mod.itoa(temp_id, buf[3..]);
    var dig_start: usize = @intCast(usize, 19) - @intCast(usize, len);
    var di: usize = @intCast(usize, 3);
    var i: usize = @intCast(usize, 0);
    while (i < @intCast(usize, len)) : (i += @intCast(usize, 1)) {
        buf[di + i] = buf[dig_start + i];
    }
    var end: usize = di + @intCast(usize, len);
    var mid = interner_mod.stringInternerIntern(interner, buf[0..end]);
    return interner_mod.stringInternerGet(interner, mid);
}

pub fn emitHoistedDecls(emitter: *C89Emitter, lir_fn: *LirFunction) void {
    var max_temp: u32 = @intCast(u32, 256);
    var hti: usize = @intCast(usize, 0);
    while (hti < lir_fn.hoisted_temps.len) : (hti += @intCast(usize, 1)) {
        var htd = lir_fn.hoisted_temps.items[hti];
        if (htd.temp_id >= max_temp) { max_temp = htd.temp_id + @intCast(u32, 1); }
    }
    var raw_t2p = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 4) * max_temp, @intCast(usize, 4)) catch unreachable;
    var raw_wt = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 4) * max_temp, @intCast(usize, 4)) catch unreachable;
    var raw_wf = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 1) * max_temp, @intCast(usize, 1)) catch unreachable;
    var raw_rc = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 4) * max_temp, @intCast(usize, 4)) catch unreachable;
    var raw_dd = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 1) * max_temp, @intCast(usize, 1)) catch unreachable;
    var raw_lp = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 1) * max_temp, @intCast(usize, 1)) catch unreachable;
    var raw_pp = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 1) * max_temp, @intCast(usize, 1)) catch unreachable;
    var raw_nd = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 1) * max_temp, @intCast(usize, 1)) catch unreachable;
    var raw_wa = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 1) * max_temp, @intCast(usize, 1)) catch unreachable;
    var tid_to_pos = @ptrCast([*]u32, raw_t2p);
    var written_type = @ptrCast([*]u32, raw_wt);
    var written_flag = @ptrCast([*]u8, raw_wf);
    var read_count = @ptrCast([*]u32, raw_rc);
    var dead_arr = @ptrCast([*]u8, raw_dd);
    var local_arr = @ptrCast([*]u8, raw_lp);
    var protected_arr = @ptrCast([*]u8, raw_pp);
    var no_decl_arr = @ptrCast([*]u8, raw_nd);
    var written_arr = @ptrCast([*]u8, raw_wa);
    var tp: u32 = 0;
    while (tp < max_temp) : (tp += @intCast(u32, 1)) {
        tid_to_pos[@intCast(usize, tp)] = @intCast(u32, 0xFFFFFFFF);
        written_type[@intCast(usize, tp)] = @intCast(u32, 0xFFFFFFFF);
        written_flag[@intCast(usize, tp)] = @intCast(u8, 0);
        read_count[@intCast(usize, tp)] = @intCast(u32, 0);
        dead_arr[@intCast(usize, tp)] = @intCast(u8, 0);
        local_arr[@intCast(usize, tp)] = @intCast(u8, 0);
        protected_arr[@intCast(usize, tp)] = @intCast(u8, 0);
        no_decl_arr[@intCast(usize, tp)] = @intCast(u8, 0);
        written_arr[@intCast(usize, tp)] = @intCast(u8, 0);
    }
    hti = @intCast(usize, 0);
    while (hti < lir_fn.hoisted_temps.len) : (hti += @intCast(usize, 1)) {
        var htd = lir_fn.hoisted_temps.items[hti];
        var htt_m: []const u8 = "HTT:t"; pal.markerWrite(htt_m);
        var htt_tb: [10]u8 = undefined; var htt_tl = itoa_mod.itoa(htd.temp_id, htt_tb[0..]); var htt_ts: usize = @intCast(usize, 9) - @intCast(usize, htt_tl); pal.markerWrite(htt_tb[htt_ts..@intCast(usize, 9)]);
        var htt_ym: []const u8 = "Y"; pal.markerWrite(htt_ym);
        var htt_yb: [10]u8 = undefined; var htt_yl = itoa_mod.itoa(htd.type_id, htt_yb[0..]); var htt_ys: usize = @intCast(usize, 9) - @intCast(usize, htt_yl); pal.markerWrite(htt_yb[htt_ys..@intCast(usize, 9)]);
        var htt_nl: []const u8 = "\n"; pal.markerWrite(htt_nl);
        if (htd.temp_id < max_temp) {
            tid_to_pos[@intCast(usize, htd.temp_id)] = @intCast(u32, hti);
        }
    }
    emitter.d4_wtype = written_type;
    emitter.d4_wflag = written_flag;
    emitter.d4_t2p = tid_to_pos;
    var local_name_ids = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 128) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
    var local_types = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, 128) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
    var local_cap: u32 = @intCast(u32, 128);
    var local_count: u32 = @intCast(u32, 0);
    var pi: usize = @intCast(usize, 0);
    while (pi < lir_fn.params.len) : (pi += @intCast(usize, 1)) {
        if (local_count >= local_cap) {
            var n_cap: u32 = local_cap * @intCast(u32, 2);
            var n_ni = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
            var n_nt = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
            var n_ft = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
            var n_fn = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
            var gi: u32 = @intCast(u32, 0);
            while (gi < local_count) : (gi += @intCast(u32, 1)) {
                n_ni[@intCast(usize, gi)] = local_name_ids[@intCast(usize, gi)];
                n_nt[@intCast(usize, gi)] = local_types[@intCast(usize, gi)];
                n_ft[@intCast(usize, gi)] = emitter.fl_temps[@intCast(usize, gi)];
                n_fn[@intCast(usize, gi)] = emitter.fl_name_ids[@intCast(usize, gi)];
            }
            local_name_ids = n_ni;
            local_types = n_nt;
            emitter.fl_temps = n_ft;
            emitter.fl_name_ids = n_fn;
            local_cap = n_cap;
        }
        var p = lir_fn.params.items[pi];
        local_name_ids[@intCast(usize, local_count)] = p.name_id;
        local_types[@intCast(usize, local_count)] = p.type_id;
        emitter.fl_temps[@intCast(usize, local_count)] = p.temp_id;
        emitter.fl_name_ids[@intCast(usize, local_count)] = p.name_id;
        local_count += @intCast(u32, 1);
    }
    emitter.fl_count = local_count;
    var p0m: []const u8 = "P0:lc="; pal.measureMarkerWrite(p0m);
    var p0mb: [10]u8 = undefined; var p0ml = itoa_mod.itoa(local_count, p0mb[0..]); var p0ms: usize = @intCast(usize, 9) - @intCast(usize, p0ml); pal.measureMarkerWrite(p0mb[p0ms..@intCast(usize, 9)]);
    var p0nl: []const u8 = "\n"; pal.measureMarkerWrite(p0nl);
    var dbi: usize = @intCast(usize, 0);
    while (dbi < lir_fn.blocks.len) : (dbi += @intCast(usize, 1)) {
        var dbb = &lir_fn.blocks.items[dbi];
        var dii: usize = @intCast(usize, 0);
        while (dii < dbb.insts.len) : (dii += @intCast(usize, 1)) {
            var dinst = dbb.insts.items[dii];
            switch (dinst) {
                .decl_local => |dl| {
                    if (local_count >= local_cap) {
                        var n_cap: u32 = local_cap * @intCast(u32, 2);
                        var n_ni = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
                        var n_nt = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
                        var n_ft = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
                        var n_fn = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, n_cap) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
                        var gi: u32 = @intCast(u32, 0);
                        while (gi < local_count) : (gi += @intCast(u32, 1)) {
                            n_ni[@intCast(usize, gi)] = local_name_ids[@intCast(usize, gi)];
                            n_nt[@intCast(usize, gi)] = local_types[@intCast(usize, gi)];
                            n_ft[@intCast(usize, gi)] = emitter.fl_temps[@intCast(usize, gi)];
                            n_fn[@intCast(usize, gi)] = emitter.fl_name_ids[@intCast(usize, gi)];
                        }
                        local_name_ids = n_ni;
                        local_types = n_nt;
                        emitter.fl_temps = n_ft;
                        emitter.fl_name_ids = n_fn;
                        local_cap = n_cap;
                    }
                     var p1m: []const u8 = "P1:t"; pal.markerWrite(p1m);
                     var p1tb: [20]u8 = undefined; var p1tl = itoa_mod.itoa(dl.temp, p1tb[0..]); var p1ts: usize = @intCast(usize, 19) - @intCast(usize, p1tl); pal.markerWrite(p1tb[p1ts..@intCast(usize, 19)]);
                     var p1tn: []const u8 = "T"; pal.markerWrite(p1tn);
                     var p1db: [20]u8 = undefined; var p1dl = itoa_mod.itoa(dl.type_id, p1db[0..]); var p1ds: usize = @intCast(usize, 19) - @intCast(usize, p1dl); pal.markerWrite(p1db[p1ds..@intCast(usize, 19)]);
                     var p1nn: []const u8 = "N"; pal.markerWrite(p1nn);
                     var p1nb: [20]u8 = undefined; var p1nl2 = itoa_mod.itoa(dl.name_id, p1nb[0..]); var p1ns: usize = @intCast(usize, 19) - @intCast(usize, p1nl2); pal.markerWrite(p1nb[p1ns..@intCast(usize, 19)]);
                     var p1nl: []const u8 = "\n"; pal.markerWrite(p1nl);
                    local_name_ids[@intCast(usize, local_count)] = dl.name_id;
                    local_types[@intCast(usize, local_count)] = dl.type_id;
                    emitter.fl_temps[@intCast(usize, local_count)] = dl.temp;
                    emitter.fl_name_ids[@intCast(usize, local_count)] = dl.name_id;
                    emitter.fl_count = local_count + @intCast(u32, 1);
                    local_count += @intCast(u32, 1);
                },

                .tail_call => {},
                .va_start => {},
                .va_arg => {},
                .va_end => {},
                else => {},
            }
        }
    }
    var d2c: []const u8 = "P2:lc="; pal.markerWrite(d2c);
    var d2cb: [10]u8 = undefined; var d2cl = itoa_mod.itoa(local_count, d2cb[0..]); var d2cs: usize = @intCast(usize, 9) - @intCast(usize, d2cl); pal.markerWrite(d2cb[d2cs..@intCast(usize, 9)]);
    var d2cn: []const u8 = "\n"; pal.markerWrite(d2cn);
    var bb_idx: usize = @intCast(usize, 0);
    while (bb_idx < lir_fn.blocks.len) : (bb_idx += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bb_idx];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            switch (inst) {
                .assign => |a| {
                    if (a.src < max_temp) {
                        var src_p = tid_to_pos[@intCast(usize, a.src)];
                        if (src_p != @intCast(u32, 0xFFFFFFFF) and a.dst < max_temp) {
                            var dst_p = tid_to_pos[@intCast(usize, a.dst)];
                            if (dst_p != @intCast(u32, 0xFFFFFFFF)) {
                                var src_ty: u32 = undefined;
                                var swf = written_flag[@intCast(usize, src_p)];
                                if (swf != @intCast(u8, 0)) {
                                    src_ty = written_type[@intCast(usize, src_p)];
                                } else {
                                    src_ty = lir_fn.hoisted_temps.items[@intCast(usize, src_p)].type_id;
                                }
                                written_type[@intCast(usize, dst_p)] = src_ty;
                                var p3m: []const u8 = "P3:d"; pal.markerWrite(p3m);
                                var p3db: [10]u8 = undefined; var p3dl = itoa_mod.itoa(a.dst, p3db[0..]); var p3ds: usize = @intCast(usize, 9) - @intCast(usize, p3dl); pal.markerWrite(p3db[p3ds..@intCast(usize, 9)]);
                                var p3sm: []const u8 = "s"; pal.markerWrite(p3sm);
                                var p3sb: [10]u8 = undefined; var p3sl = itoa_mod.itoa(a.src, p3sb[0..]); var p3ss: usize = @intCast(usize, 9) - @intCast(usize, p3sl); pal.markerWrite(p3sb[p3ss..@intCast(usize, 9)]);
                                var p3tm: []const u8 = "t"; pal.markerWrite(p3tm);
                                var p3tb: [10]u8 = undefined; var p3tl = itoa_mod.itoa(src_ty, p3tb[0..]); var p3ts: usize = @intCast(usize, 9) - @intCast(usize, p3tl); pal.markerWrite(p3tb[p3ts..@intCast(usize, 9)]);
                                var p3hm: []const u8 = "h"; pal.markerWrite(p3hm);
                                var p3hb: [10]u8 = undefined; var p3hl = itoa_mod.itoa(lir_fn.hoisted_temps.items[@intCast(usize, dst_p)].type_id, p3hb[0..]); var p3hs: usize = @intCast(usize, 9) - @intCast(usize, p3hl); pal.markerWrite(p3hb[p3hs..@intCast(usize, 9)]);
                                var p3im: []const u8 = "i"; pal.markerWrite(p3im);
                                var p3ib: [10]u8 = undefined; var p3il = itoa_mod.itoa(@intCast(u32, (bb_idx << @intCast(usize, 16)) | ii), p3ib[0..]); var p3is: usize = @intCast(usize, 9) - @intCast(usize, p3il); pal.markerWrite(p3ib[p3is..@intCast(usize, 9)]);
                                var p3nl: []const u8 = "\n"; pal.markerWrite(p3nl);
                                written_flag[@intCast(usize, dst_p)] = @intCast(u8, 1);
                            }
                        }
                    }
                },
                .float_const => |fc| {
                    if (fc.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, fc.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_F64;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .int_const => |ic| {
                    if (ic.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, ic.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = intConstTypeForValue(emitter.registry, ic.value, lir_fn.hoisted_temps.items[@intCast(usize, dp)].type_id);
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .enum_const => |ec| {
                    if (ec.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, ec.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = ec.type_id;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .string_const => |sc| {
                    if (sc.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, sc.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = lir_fn.hoisted_temps.items[@intCast(usize, dp)].type_id;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .bool_const => |bc| {
                    if (bc.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, bc.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_BOOL;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .binary => |b| {
                    if (b.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, b.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            var lhs_p = tid_to_pos[@intCast(usize, b.lhs)];
                            if (lhs_p != @intCast(u32, 0xFFFFFFFF)) {
                                var lhs_ty: u32 = undefined;
                                var lwf = written_flag[@intCast(usize, lhs_p)];
                                if (lwf != @intCast(u8, 0)) {
                                    lhs_ty = written_type[@intCast(usize, lhs_p)];
                                } else {
                                    lhs_ty = lir_fn.hoisted_temps.items[@intCast(usize, lhs_p)].type_id;
                                }
                                var lt = emitter.registry.types_items[@intCast(usize, lhs_ty)];
                                if (lt.kind == TypeKind.array_type) {
                                    var ap = emitter.registry.array_items[@intCast(usize, lt.payload_idx)];
                                    lhs_ty = type_mod.typeRegistryGetOrCreatePtr(emitter.registry, ap.elem, false);
                                }
                                written_type[@intCast(usize, dp)] = lhs_ty;
                                written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                            }
                        }
                    }
                },
                .call_direct => |cd_slot| {
                    var cd = lir_mod.lirSideGetCallDirect(lir_fn, cd_slot);
                    if (cd.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, cd.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            if (cd.return_type != type_mod.TYPE_UNDEFINED) {
                                written_type[@intCast(usize, dp)] = cd.return_type;
                            } else {
                                written_type[@intCast(usize, dp)] = type_mod.TYPE_UNDEFINED;
                            }
                            var p3m: []const u8 = "P3:r"; pal.markerWrite(p3m);
                            var p3rb: [20]u8 = undefined; var p3rl = itoa_mod.itoa(cd.result, p3rb[0..]); var p3rs: usize = @intCast(usize, 19) - @intCast(usize, p3rl); pal.markerWrite(p3rb[p3rs..@intCast(usize, 19)]);
                            var p3tn: []const u8 = "T"; pal.markerWrite(p3tn);
                            var p3tb: [20]u8 = undefined; var p3tl = itoa_mod.itoa(cd.return_type, p3tb[0..]); var p3ts: usize = @intCast(usize, 19) - @intCast(usize, p3tl); pal.markerWrite(p3tb[p3ts..@intCast(usize, 19)]);
                            var p3wn: []const u8 = "W"; pal.markerWrite(p3wn);
                            var p3wb: [20]u8 = undefined; var p3wl = itoa_mod.itoa(written_type[@intCast(usize, dp)], p3wb[0..]); var p3ws: usize = @intCast(usize, 19) - @intCast(usize, p3wl); pal.markerWrite(p3wb[p3ws..@intCast(usize, 19)]);
                            var p3nl: []const u8 = "\n"; pal.markerWrite(p3nl);
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 2);
                        }
                    }
                },
                .tail_call => |tc_slot| {
                    var tc = lir_mod.lirSideGetTailCall(lir_fn, tc_slot);
                    if (tc.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, tc.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            if (tc.return_type != type_mod.TYPE_UNDEFINED) {
                                written_type[@intCast(usize, dp)] = tc.return_type;
                            } else {
                                written_type[@intCast(usize, dp)] = type_mod.TYPE_UNDEFINED;
                            }
                            var p3m: []const u8 = "P3:r"; pal.markerWrite(p3m);
                            var p3rb: [20]u8 = undefined; var p3rl = itoa_mod.itoa(tc.result, p3rb[0..]); var p3rs: usize = @intCast(usize, 19) - @intCast(usize, p3rl); pal.markerWrite(p3rb[p3rs..@intCast(usize, 19)]);
                            var p3tn: []const u8 = "T"; pal.markerWrite(p3tn);
                            var p3tb: [20]u8 = undefined; var p3tl = itoa_mod.itoa(tc.return_type, p3tb[0..]); var p3ts: usize = @intCast(usize, 19) - @intCast(usize, p3tl); pal.markerWrite(p3tb[p3ts..@intCast(usize, 19)]);
                            var p3wn: []const u8 = "W"; pal.markerWrite(p3wn);
                            var p3wb: [20]u8 = undefined; var p3wl = itoa_mod.itoa(written_type[@intCast(usize, dp)], p3wb[0..]); var p3ws: usize = @intCast(usize, 19) - @intCast(usize, p3wl); pal.markerWrite(p3wb[p3ws..@intCast(usize, 19)]);
                            var p3nl: []const u8 = "\n"; pal.markerWrite(p3nl);
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 2);
                        }
                    }
                },
                .call => |cl| {
                    if (cl.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, cl.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_UNDEFINED;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 2);
                        }
                    }
                },
                .int_cast => |ic| {
                    if (ic.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, ic.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = ic.target;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .int_to_float => |itf| {
                    if (itf.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, itf.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = itf.target;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .float_cast => |fc| {
                    if (fc.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, fc.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = fc.target;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .load_index => |li| {
                    if (li.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, li.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = lir_fn.hoisted_temps.items[@intCast(usize, dp)].type_id;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .unary => |u| {
                    if (u.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, u.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            var op_p = tid_to_pos[@intCast(usize, u.operand)];
                            if (op_p != @intCast(u32, 0xFFFFFFFF)) {
                                var op_ty: u32 = undefined;
                                var owf = written_flag[@intCast(usize, op_p)];
                                if (owf != @intCast(u8, 0)) {
                                    op_ty = written_type[@intCast(usize, op_p)];
                                } else {
                                    op_ty = lir_fn.hoisted_temps.items[@intCast(usize, op_p)].type_id;
                                }
                                written_type[@intCast(usize, dp)] = op_ty;
                                written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                            }
                        }
                    }
                },
                .load => |l| {
                    if (l.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, l.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_U8;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .addr_of => |ao| {
                    if (ao.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, ao.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_U32;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .addr_of_field => |aof| {
                    if (aof.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, aof.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_U32;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .make_slice => |ms| {
                    if (ms.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, ms.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = ms.type_id;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .load_global => |lg2| {
                    if (lg2.result < max_temp) {
                        var lg2_dp = tid_to_pos[@intCast(usize, lg2.result)];
                        if (lg2_dp != @intCast(u32, 0xFFFFFFFF)) {
                            var lg2_ht = lir_fn.hoisted_temps.items[@intCast(usize, lg2_dp)];
                            if (isLargeModuleVarArrayType(emitter, lg2_ht.type_id)) {
                                written_flag[@intCast(usize, lg2_dp)] = @intCast(u8, 3);
                            }
                        }
                    }
                },
                .load_field => |lf| {
                    if (lf.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, lf.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = lir_fn.hoisted_temps.items[@intCast(usize, dp)].type_id;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .ptr_cast => |pc| {
                    if (pc.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, pc.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = pc.target;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .int_to_ptr => |itp| {
                    if (itp.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, itp.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = itp.target;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .ptr_to_int => |pti| {
                    if (pti.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, pti.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_USIZE;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .load_local => |ll| {
                    if (ll.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, ll.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            var li: u32 = @intCast(u32, 0);
                            var found_p: u8 = @intCast(u8, 0);
                            while (li < local_count) : (li += @intCast(u32, 1)) {
                                if (local_name_ids[@intCast(usize, li)] == ll.name_id) {
                                    written_type[@intCast(usize, dp)] = local_types[@intCast(usize, li)];
                                    written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                                    found_p = @intCast(u8, 1);
                                    break;
                                }
                            }
                            var lls: []const u8 = "LLd:"; pal.markerWrite(lls);
                            var lln = ll.result; dbgPrintU32(lln);
                            var lls2: []const u8 = "="; pal.markerWrite(lls2);
                            if (found_p != @intCast(u8, 0)) {
                                var llty = written_type[@intCast(usize, dp)];
                                dbgPrintU32(llty);
                            } else {
                                var llmiss: []const u8 = "MISS"; pal.markerWrite(llmiss);
                            }
                            var lls3: []const u8 = " "; pal.markerWrite(lls3);
                        }
                    }
                },
                .store_local => |sl| {
                    if (sl.value < max_temp) {
                        var li2: u32 = @intCast(u32, 0);
                        while (li2 < local_count) : (li2 += @intCast(u32, 1)) {
                            if (local_name_ids[@intCast(usize, li2)] == sl.name_id) {
                                var src_p = tid_to_pos[@intCast(usize, sl.value)];
                                if (src_p != @intCast(u32, 0xFFFFFFFF)) {
                                    var ss_ty: u32 = undefined;
                                    var swf = written_flag[@intCast(usize, src_p)];
                                    if (swf != @intCast(u8, 0)) {
                                        ss_ty = written_type[@intCast(usize, src_p)];
                                    } else {
                                        ss_ty = lir_fn.hoisted_temps.items[@intCast(usize, src_p)].type_id;
                                    }
                                    local_types[@intCast(usize, li2)] = ss_ty;
                                }
                                break;
                            }
                        }
                    }
                },
                .va_arg => |va| {
                    if (va.result < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, va.result)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = va.type_id;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .va_start => |vs| {
                    if (vs.va_list_temp < max_temp) {
                        var dp = tid_to_pos[@intCast(usize, vs.va_list_temp)];
                        if (dp != @intCast(u32, 0xFFFFFFFF)) {
                            written_type[@intCast(usize, dp)] = type_mod.TYPE_VA_LIST;
                            written_flag[@intCast(usize, dp)] = @intCast(u8, 1);
                        }
                    }
                },
                .va_end => {},
                else => {},
            }
        }
    }
    var lbi: u32 = @intCast(u32, 0);
    while (lbi < emitter.fl_count) : (lbi += @intCast(u32, 1)) {
        var lt = emitter.fl_temps[@intCast(usize, lbi)];
        if (lt < max_temp) {
            var lp = tid_to_pos[@intCast(usize, lt)];
            if (lp != @intCast(u32, 0xFFFFFFFF)) {
                local_arr[@intCast(usize, lp)] = @intCast(u8, 1);
            }
        }
    }
    dceMarkAllReads(lir_fn, max_temp, tid_to_pos, read_count, protected_arr, no_decl_arr, emitter.registry);
    var raw_lr = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, local_count) * @intCast(usize, 1), @intCast(usize, 1)) catch unreachable;
    var local_read_arr = @ptrCast([*]u8, raw_lr);
    var lrz: u32 = @intCast(u32, 0);
    while (lrz < local_count) : (lrz += @intCast(u32, 1)) { local_read_arr[@intCast(usize, lrz)] = @intCast(u8, 0); }
    var lrp: u32 = @intCast(u32, 0);
    while (lrp < local_count) : (lrp += @intCast(u32, 1)) {
        var lrt = emitter.fl_temps[@intCast(usize, lrp)];
        if (lrt < max_temp) {
            var lrpos = tid_to_pos[@intCast(usize, lrt)];
            if (lrpos != @intCast(u32, 0xFFFFFFFF) and lrpos < @intCast(u32, lir_fn.hoisted_temps.len)) {
                if (read_count[@intCast(usize, lrpos)] > @intCast(u32, 0)) { local_read_arr[@intCast(usize, lrp)] = @intCast(u8, 1); }
            }
        }
    }
    var lrb_idx: usize = @intCast(usize, 0);
    while (lrb_idx < lir_fn.blocks.len) : (lrb_idx += @intCast(usize, 1)) {
        var lrbb = &lir_fn.blocks.items[lrb_idx];
        var lrii: usize = @intCast(usize, 0);
        while (lrii < lrbb.insts.len) : (lrii += @intCast(usize, 1)) {
            var lrinst = lrbb.insts.items[lrii];
            var lr_nid: u32 = @intCast(u32, 0xFFFFFFFF);
            switch (lrinst) {
                .load_local => |ll| { lr_nid = ll.name_id; },
                .load_field => |lf| { if (lf.name_id != @intCast(u32, 0)) { lr_nid = lf.name_id; } },
                .load_index => |li| { if (li.name_id != @intCast(u32, 0)) { lr_nid = li.name_id; } },
                else => {},
            }
            if (lr_nid != @intCast(u32, 0xFFFFFFFF)) {
                var lrm: u32 = @intCast(u32, 0);
                while (lrm < local_count) : (lrm += @intCast(u32, 1)) {
                    if (emitter.fl_name_ids[@intCast(usize, lrm)] == lr_nid) { local_read_arr[@intCast(usize, lrm)] = @intCast(u8, 1); }
                }
            }
        }
    }
    var dbg_li: u32 = @intCast(u32, 0);
    while (dbg_li < local_count) : (dbg_li += @intCast(u32, 1)) {
        if (local_read_arr[@intCast(usize, dbg_li)] == @intCast(u8, 0) and dbg_li >= @intCast(u32, lir_fn.params.len)) {
            var dbg_nm = mangleLocalName(emitter.mangler, emitter.interner, emitter.fl_name_ids[@intCast(usize, dbg_li)]);
            var dbg_m: []const u8 = "DBGDEAD:"; pal.markerWrite(dbg_m);
            pal.markerWrite(dbg_nm);
            var dbg_t: []const u8 = " t="; pal.markerWrite(dbg_t);
            var dbg_tb: [10]u8 = undefined;
            var dbg_tl = itoa_mod.itoa(emitter.fl_temps[@intCast(usize, dbg_li)], dbg_tb[0..]);
            var dbg_ti = @intCast(u32, 9) - dbg_tl;
            var dbg_ts: usize = @intCast(usize, dbg_ti);
            var dbg_te: usize = @intCast(usize, 9);
            pal.markerWrite(dbg_tb[dbg_ts..dbg_te]);
            var dbg_r: []const u8 = " rc="; pal.markerWrite(dbg_r);
            var dbg_rcb: [10]u8 = undefined;
            var dbg_lt = emitter.fl_temps[@intCast(usize, dbg_li)];
            if (dbg_lt < max_temp) {
                var dbg_lp = tid_to_pos[@intCast(usize, dbg_lt)];
                if (dbg_lp != @intCast(u32, 0xFFFFFFFF) and dbg_lp < @intCast(u32, lir_fn.hoisted_temps.len)) {
                    var dbg_rc = read_count[@intCast(usize, dbg_lp)];
                    var dbg_rcl = itoa_mod.itoa(dbg_rc, dbg_rcb[0..]);
                    var dbg_rci = @intCast(u32, 9) - dbg_rcl;
                    var dbg_rcs: usize = @intCast(usize, dbg_rci);
                    var dbg_rce: usize = @intCast(usize, 9);
                    pal.markerWrite(dbg_rcb[dbg_rcs..dbg_rce]);
                } else {
                    var dbg_m2: []const u8 = "NOTMP"; pal.markerWrite(dbg_m2);
                }
            } else {
                var dbg_m3: []const u8 = "OOR"; pal.markerWrite(dbg_m3);
            }
            var dbg_nl: []const u8 = "\n"; pal.markerWrite(dbg_nl);
        }
    }
    var raw_ld = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, lir_fn.hoisted_temps.len) * @intCast(usize, 1), @intCast(usize, 1)) catch unreachable;
    var ldead_arr = @ptrCast([*]u8, raw_ld);
    var ldz: usize = @intCast(usize, 0);
    while (ldz < lir_fn.hoisted_temps.len) : (ldz += @intCast(usize, 1)) { ldead_arr[ldz] = @intCast(u8, 0); }
    var ldp: u32 = @intCast(u32, 0);
    while (ldp < local_count) : (ldp += @intCast(u32, 1)) {
        if (local_read_arr[@intCast(usize, ldp)] == @intCast(u8, 0) and ldp >= @intCast(u32, lir_fn.params.len)) {
            var ldlt = emitter.fl_temps[@intCast(usize, ldp)];
            if (ldlt < max_temp) {
                var ldpos = tid_to_pos[@intCast(usize, ldlt)];
                if (ldpos != @intCast(u32, 0xFFFFFFFF) and ldpos < @intCast(u32, lir_fn.hoisted_temps.len)) {
                    ldead_arr[ldpos] = @intCast(u8, 1);
                }
            }
        }
    }
    var bb_inst_total: u32 = @intCast(u32, 0);
    var bbb_idx: usize = @intCast(usize, 0);
    while (bbb_idx < lir_fn.blocks.len) : (bbb_idx += @intCast(usize, 1)) {
        bb_inst_total += @intCast(u32, lir_fn.blocks.items[bbb_idx].insts.len);
    }
    var raw_rel = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, bb_inst_total) * @intCast(usize, 1), @intCast(usize, 1)) catch unreachable;
    var rel_arr = @ptrCast([*]u8, raw_rel);
    var rel_z: u32 = @intCast(u32, 0);
    while (rel_z < bb_inst_total) : (rel_z += @intCast(u32, 1)) { rel_arr[@intCast(usize, rel_z)] = @intCast(u8, 0); }
    var dce_changed: u8 = @intCast(u8, 1);
    while (dce_changed == @intCast(u8, 1)) {
        dce_changed = @intCast(u8, 0);
        var bb_idx2: usize = @intCast(usize, 0);
        var rel_base: u32 = @intCast(u32, 0);
        while (bb_idx2 < lir_fn.blocks.len) : (bb_idx2 += @intCast(usize, 1)) {
            var bb2 = &lir_fn.blocks.items[bb_idx2];
            var ii2: usize = @intCast(usize, 0);
            while (ii2 < bb2.insts.len) : (ii2 += @intCast(usize, 1)) {
                var rel_idx = rel_base + @intCast(u32, ii2);
                var inst2 = bb2.insts.items[ii2];
                if (rel_arr[@intCast(usize, rel_idx)] == @intCast(u8, 0)) {
                    var dce_rp = dceResultPos(max_temp, tid_to_pos, inst2);
                    if (dce_rp != @intCast(u32, 0xFFFFFFFF)) {
                        if (local_arr[@intCast(usize, dce_rp)] == @intCast(u8, 0) or ldead_arr[@intCast(usize, dce_rp)] != @intCast(u8, 0)) {
                            if (read_count[@intCast(usize, dce_rp)] == @intCast(u32, 0)) {
                                dead_arr[@intCast(usize, dce_rp)] = @intCast(u8, 1);
                                dceReleaseOperands(max_temp, tid_to_pos, read_count, inst2);
                                rel_arr[@intCast(usize, rel_idx)] = @intCast(u8, 1);
                                dce_changed = @intCast(u8, 1);
                            }
                        }
                    }
                }
            }
            rel_base += @intCast(u32, bb2.insts.len);
        }
    }
    var dd_idx: usize = @intCast(usize, 0);
    while (dd_idx < lir_fn.hoisted_temps.len) : (dd_idx += @intCast(usize, 1)) {
        var dd_td = lir_fn.hoisted_temps.items[dd_idx];
        if (dd_td.temp_id < @intCast(u32, lir_fn.params.len)) { dead_arr[dd_idx] = @intCast(u8, 0); continue; }
        if (local_arr[dd_idx] != @intCast(u8, 0)) {
            if (ldead_arr[dd_idx] != @intCast(u8, 0)) { dead_arr[dd_idx] = @intCast(u8, 1); } else { dead_arr[dd_idx] = @intCast(u8, 0); }
            continue;
        }
        if (protected_arr[dd_idx] != @intCast(u8, 0)) { dead_arr[dd_idx] = @intCast(u8, 0); continue; }
        if (read_count[dd_idx] == @intCast(u32, 0)) {
            dead_arr[dd_idx] = @intCast(u8, 1);
        } else {
            dead_arr[dd_idx] = @intCast(u8, 0);
        }
    }
    emitter.d4_dead = dead_arr;
    emitter.d4_max_temp = max_temp;
    emitter.d4_local = local_arr;
    emitter.d4_nodecl = no_decl_arr;
    emitter.d4_lread = local_read_arr;
    var dbg2_li: usize = @intCast(usize, 0);
    while (dbg2_li < lir_fn.hoisted_temps.len) : (dbg2_li += @intCast(usize, 1)) {
        var dbg2_td = lir_fn.hoisted_temps.items[dbg2_li];
        if (dbg2_td.temp_id == @intCast(u32, 4779)) {
            var dbg2_m: []const u8 = "DBG4779:dead="; pal.markerWrite(dbg2_m);
            var dbg2_b: [10]u8 = undefined;
            var dbg2_l = itoa_mod.itoa(dead_arr[dbg2_li], dbg2_b[0..]);
            var dbg2_i = @intCast(u32, 9) - dbg2_l;
            var dbg2_s: usize = @intCast(usize, dbg2_i);
            var dbg2_e: usize = @intCast(usize, 9);
            pal.markerWrite(dbg2_b[dbg2_s..dbg2_e]);
            var dbg2_r: []const u8 = " rc="; pal.markerWrite(dbg2_r);
            var dbg2_rb: [10]u8 = undefined;
            var dbg2_rl = itoa_mod.itoa(read_count[dbg2_li], dbg2_rb[0..]);
            var dbg2_ri = @intCast(u32, 9) - dbg2_rl;
            var dbg2_rs: usize = @intCast(usize, dbg2_ri);
            var dbg2_re: usize = @intCast(usize, 9);
            pal.markerWrite(dbg2_rb[dbg2_rs..dbg2_re]);
            var dbg2_l2: []const u8 = " local="; pal.markerWrite(dbg2_l2);
            var dbg2_lb: [10]u8 = undefined;
            var dbg2_ll = itoa_mod.itoa(local_arr[dbg2_li], dbg2_lb[0..]);
            var dbg2_li2 = @intCast(u32, 9) - dbg2_ll;
            var dbg2_ls: usize = @intCast(usize, dbg2_li2);
            var dbg2_le: usize = @intCast(usize, 9);
            pal.markerWrite(dbg2_lb[dbg2_ls..dbg2_le]);
            var dbg2_nl: []const u8 = "\n"; pal.markerWrite(dbg2_nl);
        }
    }
    dceMarkAllWritten(lir_fn, max_temp, tid_to_pos, written_arr);
    var d4p: []const u8 = "D4:"; pal.markerWrite(d4p);
    var di: usize = @intCast(usize, 0);
    var had: u8 = 0;
     while (di < lir_fn.hoisted_temps.len) : (di += @intCast(usize, 1)) {
         var td = lir_fn.hoisted_temps.items[di];
         if (td.temp_id < @intCast(u32, lir_fn.params.len)) { continue; }
        var tn = mangleTempName(emitter.interner, td.temp_id);
        var wf = written_flag[@intCast(usize, di)];
        if (wf == @intCast(u8, 0)) {
            if (td.type_id != type_mod.TYPE_UNDEFINED) {
                pal.markerWrite(tn);
                var d4u: []const u8 = "=UNWRITTEN "; pal.markerWrite(d4u);
                had = @intCast(u8, 1);
            }
        } else if (wf == @intCast(u8, 2)) {
            var d9m: []const u8 = "D9:"; pal.markerWrite(d9m);
            pal.markerWrite(tn);
            var d9e: []const u8 = "="; pal.markerWrite(d9e);
            var wt2 = written_type[@intCast(usize, di)];
            var d9tb: [20]u8 = undefined; var d9tl = itoa_mod.itoa(wt2, d9tb[0..]); var d9ts: usize = @intCast(usize, 19) - @intCast(usize, d9tl); pal.markerWrite(d9tb[d9ts..@intCast(usize, 19)]);
            var d9h: []const u8 = " ht="; pal.markerWrite(d9h);
            var ht2 = lir_fn.hoisted_temps.items[@intCast(usize, di)].type_id;
            var d9hb: [20]u8 = undefined; var d9hl = itoa_mod.itoa(ht2, d9hb[0..]); var d9hs: usize = @intCast(usize, 19) - @intCast(usize, d9hl); pal.markerWrite(d9hb[d9hs..@intCast(usize, 19)]);
            var d9nl: []const u8 = "\n"; pal.markerWrite(d9nl);
            had = @intCast(u8, 1);
         } else {
            var wt = written_type[@intCast(usize, di)];
            var d7m: []const u8 = "D7:"; pal.markerWrite(d7m);
            pal.markerWrite(tn);
            var d7t: []const u8 = "="; pal.markerWrite(d7t);
            var d7tb: [20]u8 = undefined; var d7tl = itoa_mod.itoa(wt, d7tb[0..]); var d7ts: usize = @intCast(usize, 19) - @intCast(usize, d7tl); pal.markerWrite(d7tb[d7ts..@intCast(usize, 19)]);
            var d7nl: []const u8 = "\n"; pal.markerWrite(d7nl);
            if (wt != @intCast(u32, 0xFFFFFFFF) and wt != td.type_id) {
                pal.markerWrite(tn);
                var d4d: []const u8 = ":"; pal.markerWrite(d4d);
                var dc = getCTypeName(emitter.registry, emitter.mangler, td.type_id);
                pal.markerWrite(dc);
                var d4a: []const u8 = "->"; pal.markerWrite(d4a);
                var wc = getCTypeName(emitter.registry, emitter.mangler, wt);
                pal.markerWrite(wc);
                var d4m: []const u8 = " MISMATCH "; pal.markerWrite(d4m);
                had = @intCast(u8, 1);
            }
        }
    }
    if (had != @intCast(u8, 0)) {
        var d4n: []const u8 = "\n"; pal.markerWrite(d4n);
    } else {
        var d4ok: []const u8 = "OK\n"; pal.markerWrite(d4ok);
    }

    var i: usize = @intCast(usize, 0);
     while (i < lir_fn.hoisted_temps.len) : (i += @intCast(usize, 1)) {
         var td = lir_fn.hoisted_temps.items[i];
         if (td.temp_id < @intCast(u32, lir_fn.params.len)) { continue; }
         if (written_flag[@intCast(usize, i)] == @intCast(u8, 3)) { continue; }
         if (emitter.d4_dead[@intCast(usize, i)] == @intCast(u8, 1)) { continue; }
         if (emitter.d4_local[@intCast(usize, i)] == @intCast(u8, 1)) { continue; }
         if (emitter.d4_nodecl[@intCast(usize, i)] == @intCast(u8, 1)) { continue; }
        var eff_type: u32 = td.type_id;
        var wf2 = written_flag[@intCast(usize, i)];
         if (td.type_id == type_mod.TYPE_UNDEFINED or td.type_id == type_mod.TYPE_VOID or td.type_id == type_mod.TYPE_INT_LIT) {
                 if (wf2 == @intCast(u8, 1)) {
                     var wt = written_type[@intCast(usize, i)];
                     if (wt != @intCast(u32, 0xFFFFFFFF) and wt != type_mod.TYPE_VOID) {
                         eff_type = wt;
                     }
                 }
              if (eff_type == @intCast(u32, 1)) {
                  var instb_eh_m: []const u8 = "INSTB:ehd\n"; pal.markerWrite(instb_eh_m);
                  var vfeh_m: []const u8 = "VFLOW:ehdv\n"; pal.markerWrite(vfeh_m);
              }
         } else {
             if (wf2 == @intCast(u8, 1)) {
                 var wt2 = written_type[@intCast(usize, i)];
                 if (wt2 != @intCast(u32, 0xFFFFFFFF) and wt2 != type_mod.TYPE_VOID) {
                     var raw_ty = emitter.registry.types_items[@intCast(usize, td.type_id)];
                     if (raw_ty.kind == type_mod.TypeKind.ptr_type or raw_ty.kind == type_mod.TypeKind.many_ptr_type) {
                         var wt2_ty = emitter.registry.types_items[@intCast(usize, wt2)];
                         if (wt2_ty.kind == type_mod.TypeKind.fn_type) {
                             eff_type = wt2;
                             var dbf_m: []const u8 = "DBGFNPTR:t"; pal.markerWrite(dbf_m);
                             var dbf_b: [10]u8 = undefined;
                             var dbf_l = itoa_mod.itoa(td.temp_id, dbf_b[0..]);
                             var dbf_i = @intCast(u32, 9) - dbf_l;
                             var dbf_s: usize = @intCast(usize, dbf_i);
                             var dbf_e: usize = @intCast(usize, 9);
                             pal.markerWrite(dbf_b[dbf_s..dbf_e]);
                             var dbf_nl: []const u8 = "\n"; pal.markerWrite(dbf_nl);
                         } else if (wt2_ty.kind == type_mod.TypeKind.ptr_type or wt2_ty.kind == type_mod.TypeKind.many_ptr_type) {
                             var wt2_pp = emitter.registry.ptr_items[@intCast(usize, wt2_ty.payload_idx)];
                             var wt2_bt = emitter.registry.types_items[@intCast(usize, wt2_pp.base)];
                             if (wt2_bt.kind == type_mod.TypeKind.fn_type) {
                                 eff_type = wt2;
                                 var dbf2_m: []const u8 = "DBGFNPTR2:t"; pal.markerWrite(dbf2_m);
                                 var dbf2_b: [10]u8 = undefined;
                                 var dbf2_l = itoa_mod.itoa(td.temp_id, dbf2_b[0..]);
                                 var dbf2_i = @intCast(u32, 9) - dbf2_l;
                                 var dbf2_s: usize = @intCast(usize, dbf2_i);
                                 var dbf2_e: usize = @intCast(usize, 9);
                                 pal.markerWrite(dbf2_b[dbf2_s..dbf2_e]);
                                 var dbf2_nl: []const u8 = "\n"; pal.markerWrite(dbf2_nl);
                             }
                         }
                     }
                 }
             }
              if (td.type_id == @intCast(u32, 1)) {
                  var instb_eh_m: []const u8 = "INSTB:ehd\n"; pal.markerWrite(instb_eh_m);
                  var vfeh_m: []const u8 = "VFLOW:ehdd\n"; pal.markerWrite(vfeh_m);
              }
         }
        var ty = emitter.registry.types_items[@intCast(usize, eff_type)];
          var c_type = getCTypeName(emitter.registry, emitter.mangler, eff_type);
          var tn = mangleTempName(emitter.interner, td.temp_id);
        var dht: []const u8 = "HT:"; pal.markerWrite(dht);
        pal.markerWrite(tn);
        var dsep3: []const u8 = "("; pal.markerWrite(dsep3);
        var htvb: [10]u8 = undefined; var htvl = itoa_mod.itoa(td.type_id, htvb[0..]); var htvs: usize = @intCast(usize, 9) - @intCast(usize, htvl); pal.markerWrite(htvb[htvs..@intCast(usize, 9)]);
        var htar: []const u8 = "->"; pal.markerWrite(htar);
        var htfb: [10]u8 = undefined; var htfl = itoa_mod.itoa(eff_type, htfb[0..]); var htfs: usize = @intCast(usize, 9) - @intCast(usize, htfl); pal.markerWrite(htfb[htfs..@intCast(usize, 9)]);
        var htwt: []const u8 = ")w"; pal.markerWrite(htwt);
        var htwb: [10]u8 = undefined; var htwl = itoa_mod.itoa(wf2, htwb[0..]); var htws: usize = @intCast(usize, 9) - @intCast(usize, htwl); pal.markerWrite(htwb[htws..@intCast(usize, 9)]);
        var htdc: []const u8 = ":"; pal.markerWrite(htdc);
        pal.markerWrite(tn);
        var dsep: []const u8 = ":"; pal.markerWrite(dsep);
        pal.markerWrite(c_type);
        var dnl: []const u8 = "\n"; pal.markerWrite(dnl);
        if (eff_type != @intCast(u32, 1)) {
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, c_type);
        var sp: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, sp);
         bufferedWriterWrite(&emitter.writer, tn);
         if (written_arr[@intCast(usize, i)] == @intCast(u8, 0)) {
             if (retTypeIsScalarC(emitter.registry, eff_type) == @intCast(u8, 1)) {
                 var sm: []const u8 = " = 0;\n";
                 bufferedWriterWrite(&emitter.writer, sm);
             } else {
                 var sm: []const u8 = " = {0};\n";
                 bufferedWriterWrite(&emitter.writer, sm);
             }
         } else {
             var sm: []const u8 = ";\n";
             bufferedWriterWrite(&emitter.writer, sm);
         }
        } else {
            var mtp_m: []const u8 = "MTP:ti"; pal.markerWrite(mtp_m);
            var mtp_tb: [10]u8 = undefined; var mtp_tl = itoa_mod.itoa(td.temp_id, mtp_tb[0..]); var mtp_ts: usize = @intCast(usize, 9) - @intCast(usize, mtp_tl); pal.markerWrite(mtp_tb[mtp_ts..@intCast(usize, 9)]);
            var mtp_dm: []const u8 = "T"; pal.markerWriteInt(mtp_dm, eff_type);
            var mtp_nl: []const u8 = " "; pal.markerWrite(mtp_nl);
        }
    }
}

fn arrLoopDeclSigned(len: u32) []const u8 {
    if (len == @intCast(u32, 0)) { var s: []const u8 = "    int _i = 0;\n"; return s; }
    var s: []const u8 = "    unsigned int _i = 0;\n"; return s;
}

fn arrLoopDeclSignedK(len: u32) []const u8 {
    if (len == @intCast(u32, 0)) { var s: []const u8 = "    int _k = 0;\n"; return s; }
    var s: []const u8 = "    unsigned int _k = 0;\n"; return s;
}

fn arrLoopDeclOpenSigned(len: u32) []const u8 {
    if (len == @intCast(u32, 0)) { var s: []const u8 = "{\n    int _i = 0;\n    while (_i < "; return s; }
    var s: []const u8 = "{\n    unsigned int _i = 0;\n    while (_i < "; return s;
}

fn getBinOpStr(op: u8) []const u8 {
    if (op == @intCast(u8, 0)) { var s: []const u8 = "+"; return s; }
    else if (op == @intCast(u8, 1)) { var s: []const u8 = "-"; return s; }
    else if (op == @intCast(u8, 2)) { var s: []const u8 = "*"; return s; }
    else if (op == @intCast(u8, 3)) { var s: []const u8 = "/"; return s; }
    else if (op == @intCast(u8, 4)) { var s: []const u8 = "%"; return s; }
    else if (op == @intCast(u8, 5)) { var s: []const u8 = "&"; return s; }
    else if (op == @intCast(u8, 6)) { var s: []const u8 = "|"; return s; }
    else if (op == @intCast(u8, 7)) { var s: []const u8 = "^"; return s; }
    else if (op == @intCast(u8, 8)) { var s: []const u8 = "<<"; return s; }
    else if (op == @intCast(u8, 9)) { var s: []const u8 = ">>"; return s; }
    else if (op == @intCast(u8, 10)) { var s: []const u8 = "=="; return s; }
    else if (op == @intCast(u8, 11)) { var s: []const u8 = "!="; return s; }
    else if (op == @intCast(u8, 12)) { var s: []const u8 = "<"; return s; }
    else if (op == @intCast(u8, 13)) { var s: []const u8 = "<="; return s; }
    else if (op == @intCast(u8, 14)) { var s: []const u8 = ">"; return s; }
    else if (op == @intCast(u8, 15)) { var s: []const u8 = ">="; return s; }
    else if (op == @intCast(u8, 16)) { var s: []const u8 = "+"; return s; }
    else if (op == @intCast(u8, 17)) { var s: []const u8 = "-"; return s; }
    else if (op == @intCast(u8, 18)) { var s: []const u8 = "*"; return s; }
    else { var s: []const u8 = "???"; return s; }
}

fn getUnOpStr(op: u8) []const u8 {
    if (op == @intCast(u8, 0)) { var s: []const u8 = "-"; return s; }
    else if (op == @intCast(u8, 1)) { var s: []const u8 = "!"; return s; }
    else if (op == @intCast(u8, 3)) { var s: []const u8 = "-"; return s; }
    else { var s: []const u8 = "~"; return s; }
}

fn intLitSuffixUns(v: u64) []const u8 {
    if (v <= @intCast(u64, 2147483647)) { var s: []const u8 = ""; return s; }
    if (v <= @intCast(u64, 4294967295)) { var s: []const u8 = "u"; return s; }
    var s: []const u8 = "ULL"; return s;
}

fn intLitSuffixNeg(v: u64) []const u8 {
    if (v <= @intCast(u64, 2147483647)) { var s: []const u8 = ""; return s; }
    var s: []const u8 = "LL"; return s;
}

fn intConstTypeForValue(reg: *TypeRegistry, v: u64, hoisted_tid: u32) u32 {
    var hty = reg.types_items[@intCast(usize, hoisted_tid)];
    if (hty.kind == type_mod.TypeKind.integer_literal_type) {
        if (v <= @intCast(u64, 2147483647)) { return type_mod.TYPE_I32; }
        if (v <= @intCast(u64, 4294967295)) { return type_mod.TYPE_U32; }
        return type_mod.TYPE_U64;
    }
    if (hoisted_tid == type_mod.TYPE_UNDEFINED) { return type_mod.TYPE_USIZE; }
    return hoisted_tid;
}

fn isAtomicCOperand(s: []const u8) bool {
    if (s.len == @intCast(usize, 0)) return false;
    var i: usize = @intCast(usize, 0);
    while (i < s.len) : (i += @intCast(usize, 1)) {
        var c: u8 = s[i];
        var is_id_ch: bool = (c >= @intCast(u8, 'a') and c <= @intCast(u8, 'z')) or
            (c >= @intCast(u8, 'A') and c <= @intCast(u8, 'Z')) or
            (c >= @intCast(u8, '0') and c <= @intCast(u8, '9')) or
            (c == @intCast(u8, '_'));
        if (!is_id_ch) return false;
    }
    return true;
}

fn getUnsignedCTypeName(reg: *TypeRegistry, mangler: *NameMangler, tid: u32) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    if (ty.kind == TypeKind.i8_type or ty.kind == TypeKind.u8_type or ty.kind == TypeKind.c_char_type) { var s: []const u8 = "unsigned char"; return s; }
    if (ty.kind == TypeKind.i16_type or ty.kind == TypeKind.u16_type) { var s: []const u8 = "unsigned short"; return s; }
    if (ty.kind == TypeKind.i32_type or ty.kind == TypeKind.u32_type or
        ty.kind == TypeKind.isize_type or ty.kind == TypeKind.usize_type or
        ty.kind == TypeKind.integer_literal_type) { var s: []const u8 = "unsigned int"; return s; }
    if (ty.kind == TypeKind.i64_type or ty.kind == TypeKind.u64_type) {
        return getCTypeName(reg, mangler, type_mod.TYPE_U64);
    }
    return getCTypeName(reg, mangler, tid);
}

fn classifyIntSignedness(reg: *TypeRegistry, tyid: u32) i8 {
    if (tyid == type_mod.TYPE_VOID) { return @intCast(i8, -1); }
    var ty = reg.types_items[@intCast(usize, tyid)];
    var k = ty.kind;
    if (k == TypeKind.i8_type or k == TypeKind.i16_type or k == TypeKind.i32_type or k == TypeKind.i64_type or k == TypeKind.isize_type or k == TypeKind.c_char_type or k == TypeKind.integer_literal_type or k == TypeKind.bool_type or k == TypeKind.undefined_type or k == TypeKind.null_type) { return @intCast(i8, 1); }
    if (k == TypeKind.u8_type or k == TypeKind.u16_type or k == TypeKind.u32_type or k == TypeKind.u64_type or k == TypeKind.usize_type) { return @intCast(i8, 0); }
    return @intCast(i8, -1);
}

fn typeIsIntKind(reg: *TypeRegistry, tid: u32) u8 {
    if (tid == type_mod.TYPE_VOID) { return @intCast(u8, 0); }
    var ty = reg.types_items[@intCast(usize, tid)];
    var k = ty.kind;
    if (k == TypeKind.i8_type or k == TypeKind.i16_type or k == TypeKind.i32_type or k == TypeKind.i64_type or k == TypeKind.isize_type or k == TypeKind.c_char_type or k == TypeKind.integer_literal_type or k == TypeKind.bool_type or k == TypeKind.u8_type or k == TypeKind.u16_type or k == TypeKind.u32_type or k == TypeKind.u64_type or k == TypeKind.usize_type or k == TypeKind.undefined_type or k == TypeKind.null_type) { return @intCast(u8, 1); }
    return @intCast(u8, 0);
}

fn retTypeIsScalarC(reg: *TypeRegistry, tid: u32) u8 {
    if (tid == type_mod.TYPE_VOID or tid == type_mod.TYPE_UNDEFINED or tid == @intCast(u32, 0)) { return @intCast(u8, 0); }
    var rv_k = reg.types_items[@intCast(usize, tid)].kind;
    if (rv_k == TypeKind.i8_type or rv_k == TypeKind.i16_type or rv_k == TypeKind.i32_type or rv_k == TypeKind.i64_type or
        rv_k == TypeKind.isize_type or rv_k == TypeKind.u8_type or rv_k == TypeKind.u16_type or rv_k == TypeKind.u32_type or
        rv_k == TypeKind.u64_type or rv_k == TypeKind.usize_type or rv_k == TypeKind.c_char_type or
        rv_k == TypeKind.f32_type or rv_k == TypeKind.f64_type or rv_k == TypeKind.bool_type or
        rv_k == TypeKind.enum_type or rv_k == TypeKind.error_set_type or rv_k == TypeKind.ptr_type or
        rv_k == TypeKind.many_ptr_type or rv_k == TypeKind.fn_type or rv_k == TypeKind.null_type or
        rv_k == TypeKind.integer_literal_type) { return @intCast(u8, 1); }
    return @intCast(u8, 0);
}

fn typeIsPtrKind(reg: *TypeRegistry, tid: u32) u8 {
    if (tid == type_mod.TYPE_UNDEFINED or tid == type_mod.TYPE_VOID or tid == @intCast(u32, 0)) { return @intCast(u8, 0); }
    var ty = reg.types_items[@intCast(usize, tid)];
    var k = ty.kind;
    if (k == TypeKind.ptr_type or k == TypeKind.many_ptr_type) { return @intCast(u8, 1); }
    return @intCast(u8, 0);
}

fn isLocalPosUsed(emitter: *C89Emitter, pos: u32) u8 {
    if (pos >= emitter.fl_count) { return @intCast(u8, 1); }
    if (emitter.d4_lread[@intCast(usize, pos)] == @intCast(u8, 0)) { return @intCast(u8, 0); }
    return @intCast(u8, 1);
}

fn isDeadLocalName(emitter: *C89Emitter, name_id: u32) u8 {
    if (name_id == @intCast(u32, 0)) { return @intCast(u8, 0); }
    var li: u32 = @intCast(u32, 0);
    var any_matched: u8 = @intCast(u8, 0);
    while (li < emitter.fl_count) : (li += @intCast(u32, 1)) {
        if (emitter.fl_name_ids[@intCast(usize, li)] == name_id) {
            any_matched = @intCast(u8, 1);
            if (li < @intCast(u32, emitter.current_fn.params.len)) { return @intCast(u8, 0); }
            if (emitter.d4_lread[@intCast(usize, li)] != @intCast(u8, 0)) { return @intCast(u8, 0); }
        }
    }
    if (any_matched != @intCast(u8, 0)) { return @intCast(u8, 1); }
    return @intCast(u8, 0);
}

fn ptrCTypeNameFromElem(reg: *TypeRegistry, mangler: *NameMangler, elem_tid: u32) []const u8 {
    var base_cname = getCTypeName(reg, mangler, elem_tid);
    var pbuf: [128]u8 = undefined;
    var bi: usize = 0;
    while (bi < base_cname.len and bi < @intCast(usize, 126)) : (bi += @intCast(usize, 1)) { pbuf[bi] = base_cname[bi]; }
    pbuf[bi] = '*'; bi += 1;
    pbuf[bi] = 0; bi += 1;
    var ptr_mid = interner_mod.stringInternerIntern(mangler.interner, pbuf[0 .. bi - @intCast(usize, 1)]);
    return interner_mod.stringInternerGet(mangler.interner, ptr_mid);
}

fn getTempEffType(emitter: *C89Emitter, temp_id: u32, out_type: *u32, out_signed: *u8) u8 {
    var i: usize = @intCast(usize, 0);
    while (i < emitter.current_fn.hoisted_temps.len) : (i += @intCast(usize, 1)) {
        var ht = emitter.current_fn.hoisted_temps.items[i];
        if (ht.temp_id == temp_id) {
            var eff: u32 = ht.type_id;
            if (eff == type_mod.TYPE_UNDEFINED) {
                if (temp_id < emitter.d4_max_temp) {
                    var pos = emitter.d4_t2p[@intCast(usize, temp_id)];
                    if (pos != @intCast(u32, 0xFFFFFFFF) and pos < @intCast(u32, emitter.current_fn.hoisted_temps.len)) {
                        if (emitter.d4_wflag[@intCast(usize, pos)] == @intCast(u8, 1)) {
                            var wt = emitter.d4_wtype[@intCast(usize, pos)];
                            if (wt != @intCast(u32, 0xFFFFFFFF) and wt != type_mod.TYPE_VOID) { eff = wt; }
                        }
                    }
                }
            }
            if (eff != @intCast(u32, 0xFFFFFFFF) and eff != type_mod.TYPE_VOID) {
                out_type.* = eff;
                var bty = emitter.registry.types_items[@intCast(usize, eff)];
                if (bty.kind == TypeKind.i8_type or bty.kind == TypeKind.i16_type or bty.kind == TypeKind.i32_type or bty.kind == TypeKind.i64_type or bty.kind == TypeKind.isize_type or bty.kind == TypeKind.undefined_type or bty.kind == TypeKind.null_type) {
                    out_signed.* = @intCast(u8, 1);
                } else {
                    out_signed.* = @intCast(u8, 0);
                }
                return @intCast(u8, 1);
            }
            return @intCast(u8, 0);
        }
    }
    return @intCast(u8, 0);
}

fn getTempTypeInfoResolve(emitter: *C89Emitter, temp_id: u32, out_type: *u32, out_signed: *u8) u8 {
    var i: usize = @intCast(usize, 0);
    while (i < emitter.current_fn.hoisted_temps.len) : (i += @intCast(usize, 1)) {
        var ht = emitter.current_fn.hoisted_temps.items[i];
        if (ht.temp_id == temp_id and ht.type_id != type_mod.TYPE_UNDEFINED) {
            var bty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
            out_type.* = ht.type_id;
            if (bty.kind == TypeKind.i8_type or bty.kind == TypeKind.i16_type or
                bty.kind == TypeKind.i32_type or bty.kind == TypeKind.i64_type or
                bty.kind == TypeKind.isize_type) {
                out_signed.* = @intCast(u8, 1);
            } else {
                out_signed.* = @intCast(u8, 0);
            }
            return @intCast(u8, 1);
        }
    }
    return @intCast(u8, 0);
}

fn getTempTypeInfo(emitter: *C89Emitter, temp_id: u32, fb1: u32, fb2: u32, out_type: *u32, out_signed: *u8) void {
    if (getTempTypeInfoResolve(emitter, temp_id, out_type, out_signed) == @intCast(u8, 1)) return;
    if (fb1 != @intCast(u32, 0)) {
        if (getTempTypeInfoResolve(emitter, fb1, out_type, out_signed) == @intCast(u8, 1)) return;
    }
    if (fb2 != @intCast(u32, 0)) {
        if (getTempTypeInfoResolve(emitter, fb2, out_type, out_signed) == @intCast(u8, 1)) return;
    }
    var tmi_m: []const u8 = "internal: temp type resolution failed in getTempTypeInfo (temp ";
    var tmi_b: [10]u8 = undefined;
    var tmi_l = itoa_mod.itoa(temp_id, tmi_b[0..]);
    var tmi_s: usize = @intCast(usize, 9) - @intCast(usize, tmi_l);
    var tmi_e: []const u8 = ")";
    var parts: [3][]const u8 = [3][]const u8{ tmi_m, tmi_b[tmi_s..@intCast(usize, 9)], tmi_e };
    var msg = diag_mod.diagnosticBuilderMakeMsg(emitter.interner, &parts[0], @intCast(u32, 3));
    diag_mod.diagnosticCollectorAdd(emitter.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
    diag_mod.diagnosticCollectorFlushAndExit(emitter.diag, @intCast(u32, 3));
}

fn satMaxLit(width_bits: u32) []const u8 {
    if (width_bits == @intCast(u32, 8)) { var s: []const u8 = "127"; return s; }
    if (width_bits == @intCast(u32, 16)) { var s: []const u8 = "32767"; return s; }
    if (width_bits == @intCast(u32, 64)) { var s: []const u8 = "9223372036854775807"; return s; }
    { var s: []const u8 = "2147483647"; return s; }
}

fn satMinLit(width_bits: u32) []const u8 {
    if (width_bits == @intCast(u32, 8)) { var s: []const u8 = "(-128)"; return s; }
    if (width_bits == @intCast(u32, 16)) { var s: []const u8 = "(-32768)"; return s; }
    if (width_bits == @intCast(u32, 64)) { var s: []const u8 = "(-9223372036854775807 - 1)"; return s; }
    { var s: []const u8 = "(-2147483647 - 1)"; return s; }
}

fn satMinMagLit(width_bits: u32) []const u8 {
    if (width_bits == @intCast(u32, 8)) { var s: []const u8 = "128"; return s; }
    if (width_bits == @intCast(u32, 16)) { var s: []const u8 = "32768"; return s; }
    if (width_bits == @intCast(u32, 64)) { var s: []const u8 = "9223372036854775808"; return s; }
    { var s: []const u8 = "2147483648"; return s; }
}

fn satMaxULit(width_bits: u32) []const u8 {
    if (width_bits == @intCast(u32, 8)) { var s: []const u8 = "255"; return s; }
    if (width_bits == @intCast(u32, 16)) { var s: []const u8 = "65535"; return s; }
    if (width_bits == @intCast(u32, 64)) { var s: []const u8 = "0xFFFFFFFFFFFFFFFFull"; return s; }
    { var s: []const u8 = "0xFFFFFFFFu"; return s; }
}

fn emitSatBinary(emitter: *C89Emitter, op: u8, lhs: []const u8, rhs: []const u8, result: []const u8, tid: u32, is_signed: u8) void {
    var ty = emitter.registry.types_items[@intCast(usize, tid)];
    var width_bits: u32 = @intCast(u32, ty.size * @intCast(u32, 8));
    var max_lit = satMaxLit(width_bits);
    var min_lit = satMinLit(width_bits);
    var minmag_lit = satMinMagLit(width_bits);
    var maxu_lit = satMaxULit(width_bits);
    var width_lit: [12]u8 = undefined;
    var wl = itoa_mod.itoa(@intCast(u32, width_bits), width_lit[0..]);
    var wls: usize = @intCast(usize, 11) - @intCast(usize, wl);
    var width_s = width_lit[wls..@intCast(usize, 11)];
    var sp: []const u8 = " ";
    var eqs: []const u8 = " = ";
    var lp: []const u8 = "(";
    var rp: []const u8 = ")";
    var gt0: []const u8 = " > 0 && ";
    var lt0: []const u8 = " < 0 && ";
    var gtp: []const u8 = " > (";
    var ltp: []const u8 = " < (";
    var sub: []const u8 = " - ";
    var add: []const u8 = " + ";
    var mul: []const u8 = " * ";
    var div: []const u8 = " / ";
    var shl: []const u8 = " << ";
    var shr: []const u8 = " >> ";
    var ge: []const u8 = " >= ";
    var gt: []const u8 = " > ";
    var ctq: []const u8 = ")) ? ";
    var ot2: []const u8 = " : ((";
    var ot1: []const u8 = " : (";
    var colon: []const u8 = " : ";
    var eq0ll: []const u8 = " == 0) ? 0 : ((((long long)";
    var gtp_ll: []const u8 = ") > ";
    var qm: []const u8 = ") ? ";
    var ltp_ll: []const u8 = ") < ";
    var cl4: []const u8 = ")));";
    var qo2: []const u8 = ") ? ((";
    var lt0q: []const u8 = " < 0) ? ";
    var co3: []const u8 = ") : ((";
    var ge0o2: []const u8 = " >= 0) ? ((";
    var o2c: []const u8 = ")((";
    var o1c: []const u8 = ")(";
    var div0ull: []const u8 = " / (0ull - (unsigned long long)";
    var negll: []const u8 = "(unsigned long long)(-(long long)";
    var nz_and: []const u8 = " != 0 && ";
    var q0c: []const u8 = ") ? 0 : (";
    var nz_q: []const u8 = " != 0) ? ";
    var z0o2: []const u8 = " : 0) : ((";
    var zero_ull: []const u8 = "0ull - (unsigned long long)";
    var qoo: []const u8 = " ? ((";
    var o3: []const u8 = " : ((";
    var gt0q: []const u8 = " > 0) ? ";
    var z0c2: []const u8 = " : 0))";
    var oo2: []const u8 = "((";
    var cgtp2: []const u8 = ") > (";
    var ge0: []const u8 = " >= 0 && ";
    var cl1: []const u8 = ");";
    var sm: []const u8 = ";";
    var cl2: []const u8 = "));";
    var eq0q: []const u8 = " == 0) ? 0 : (";
    var gt0q2: []const u8 = " > 0) ? (";
    var ullb: []const u8 = "(unsigned long long)";
    var clx2: []const u8 = "))";
    var clx3: []const u8 = ")))";
    var clx5: []const u8 = ")))))";
    var nl: []const u8 = "\n";
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, result);
    bufferedWriterWrite(&emitter.writer, eqs);
    if (is_signed != @intCast(u8, 0)) {
        var stype = getCTypeName(emitter.registry, emitter.mangler, tid);
        var utype = getUnsignedCTypeName(emitter.registry, emitter.mangler, tid);
        if (op == @intCast(u8, 19)) {
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, gt0);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, gtp);
            bufferedWriterWrite(&emitter.writer, max_lit);
            bufferedWriterWrite(&emitter.writer, sub);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, max_lit);
            bufferedWriterWrite(&emitter.writer, ot2);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, lt0);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ltp);
            bufferedWriterWrite(&emitter.writer, min_lit);
            bufferedWriterWrite(&emitter.writer, sub);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, min_lit);
            bufferedWriterWrite(&emitter.writer, ot1);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, add);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, cl2);
        } else if (op == @intCast(u8, 20)) {
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, ge0);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ltp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, sub);
            bufferedWriterWrite(&emitter.writer, max_lit);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, max_lit);
            bufferedWriterWrite(&emitter.writer, ot2);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, lt0);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, gtp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, sub);
            bufferedWriterWrite(&emitter.writer, min_lit);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, min_lit);
            bufferedWriterWrite(&emitter.writer, ot1);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, sub);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, cl2);
        } else if (op == @intCast(u8, 21)) {
            if (width_bits == @intCast(u32, 64)) {
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, eq0q);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, gt0q2);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, gtp);
                bufferedWriterWrite(&emitter.writer, max_lit);
                bufferedWriterWrite(&emitter.writer, div);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, ctq);
                bufferedWriterWrite(&emitter.writer, max_lit);
                bufferedWriterWrite(&emitter.writer, ot2);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, ltp);
                bufferedWriterWrite(&emitter.writer, min_lit);
                bufferedWriterWrite(&emitter.writer, div);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, ctq);
                bufferedWriterWrite(&emitter.writer, min_lit);
                bufferedWriterWrite(&emitter.writer, ot1);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, mul);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, clx3);
                bufferedWriterWrite(&emitter.writer, colon);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, lt0q);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, ltp);
                bufferedWriterWrite(&emitter.writer, max_lit);
                bufferedWriterWrite(&emitter.writer, div);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, ctq);
                bufferedWriterWrite(&emitter.writer, max_lit);
                bufferedWriterWrite(&emitter.writer, ot1);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, mul);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, rp);
                bufferedWriterWrite(&emitter.writer, co3);
                bufferedWriterWrite(&emitter.writer, ullb);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, gtp);
                bufferedWriterWrite(&emitter.writer, minmag_lit);
                bufferedWriterWrite(&emitter.writer, div0ull);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, clx2);
                bufferedWriterWrite(&emitter.writer, qm);
                bufferedWriterWrite(&emitter.writer, min_lit);
                bufferedWriterWrite(&emitter.writer, ot1);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, mul);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, clx5);
                bufferedWriterWrite(&emitter.writer, sm);
            } else {
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, eq0ll);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, mul);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, gtp_ll);
                bufferedWriterWrite(&emitter.writer, max_lit);
                bufferedWriterWrite(&emitter.writer, qm);
                bufferedWriterWrite(&emitter.writer, max_lit);
                bufferedWriterWrite(&emitter.writer, colon);
                bufferedWriterWrite(&emitter.writer, lp);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, eq0ll);
                bufferedWriterWrite(&emitter.writer, lhs);

                bufferedWriterWrite(&emitter.writer, mul);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, ltp_ll);
                bufferedWriterWrite(&emitter.writer, min_lit);
                bufferedWriterWrite(&emitter.writer, qm);
                bufferedWriterWrite(&emitter.writer, min_lit);
                bufferedWriterWrite(&emitter.writer, ot1);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, mul);
                bufferedWriterWrite(&emitter.writer, rhs);
                bufferedWriterWrite(&emitter.writer, cl4);
            }
        } else {
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ge);
            bufferedWriterWrite(&emitter.writer, width_s);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, qoo);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, lt0q);
            bufferedWriterWrite(&emitter.writer, min_lit);
            bufferedWriterWrite(&emitter.writer, colon);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, gt0q);
            bufferedWriterWrite(&emitter.writer, max_lit);
            bufferedWriterWrite(&emitter.writer, z0c2);
            bufferedWriterWrite(&emitter.writer, o3);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, lt0q);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, oo2);
            if (width_bits == @intCast(u32, 64)) {
                bufferedWriterWrite(&emitter.writer, zero_ull);
                bufferedWriterWrite(&emitter.writer, lhs);
            } else {
                bufferedWriterWrite(&emitter.writer, negll);
                bufferedWriterWrite(&emitter.writer, lhs);
                bufferedWriterWrite(&emitter.writer, rp);
            }
            bufferedWriterWrite(&emitter.writer, cgtp2);
            bufferedWriterWrite(&emitter.writer, minmag_lit);
            bufferedWriterWrite(&emitter.writer, shr);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, min_lit);
            bufferedWriterWrite(&emitter.writer, colon);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, stype);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, utype);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, shl);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, colon);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, oo2);
            bufferedWriterWrite(&emitter.writer, utype);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, gtp);
            bufferedWriterWrite(&emitter.writer, max_lit);
            bufferedWriterWrite(&emitter.writer, shr);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, max_lit);
            bufferedWriterWrite(&emitter.writer, colon);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, stype);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, utype);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, shl);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, rp);
            bufferedWriterWrite(&emitter.writer, sm);
        }
    } else {
        if (op == @intCast(u8, 19)) {
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, gtp);
            bufferedWriterWrite(&emitter.writer, maxu_lit);
            bufferedWriterWrite(&emitter.writer, sub);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, maxu_lit);
            bufferedWriterWrite(&emitter.writer, ot1);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, add);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, cl1);
        } else if (op == @intCast(u8, 20)) {
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, gt);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, q0c);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, sub);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, cl1);
        } else if (op == @intCast(u8, 21)) {
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, nz_and);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, gtp);
            bufferedWriterWrite(&emitter.writer, maxu_lit);
            bufferedWriterWrite(&emitter.writer, div);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, maxu_lit);
            bufferedWriterWrite(&emitter.writer, ot1);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, mul);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, cl1);
        } else {
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ge);
            bufferedWriterWrite(&emitter.writer, width_s);
            bufferedWriterWrite(&emitter.writer, qo2);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, nz_q);
            bufferedWriterWrite(&emitter.writer, maxu_lit);
            bufferedWriterWrite(&emitter.writer, z0o2);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, gtp);
            bufferedWriterWrite(&emitter.writer, maxu_lit);
            bufferedWriterWrite(&emitter.writer, shr);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, ctq);
            bufferedWriterWrite(&emitter.writer, maxu_lit);
            bufferedWriterWrite(&emitter.writer, ot1);
            bufferedWriterWrite(&emitter.writer, lhs);
            bufferedWriterWrite(&emitter.writer, shl);
            bufferedWriterWrite(&emitter.writer, rhs);
            bufferedWriterWrite(&emitter.writer, cl2);
        }
    }
    bufferedWriterWrite(&emitter.writer, nl);
}

fn getCheckedCastFnName(reg: *TypeRegistry, tid: u32) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    if (ty.kind == TypeKind.i8_type) { var s: []const u8 = "std_checked_cast_i8"; return s; }
    if (ty.kind == TypeKind.i16_type) { var s: []const u8 = "std_checked_cast_i16"; return s; }
    if (ty.kind == TypeKind.i32_type) { var s: []const u8 = "std_checked_cast_i32"; return s; }
    if (ty.kind == TypeKind.i64_type) { var s: []const u8 = "std_checked_cast_i64"; return s; }
    if (ty.kind == TypeKind.u8_type) { var s: []const u8 = "std_checked_cast_u8"; return s; }
    if (ty.kind == TypeKind.c_char_type) { var s: []const u8 = "std_checked_cast_u8"; return s; }
    if (ty.kind == TypeKind.u16_type) { var s: []const u8 = "std_checked_cast_u16"; return s; }
    if (ty.kind == TypeKind.u32_type) { var s: []const u8 = "std_checked_cast_u32"; return s; }
    if (ty.kind == TypeKind.u64_type) { var s: []const u8 = "std_checked_cast_u64"; return s; }
    { var s: []const u8 = "std_checked_cast_u32"; return s; }
}

fn getCastTypeSuffix(reg: *TypeRegistry, tid: u32) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    if (ty.kind == TypeKind.i8_type) { var s: []const u8 = "i8"; return s; }
    if (ty.kind == TypeKind.i16_type) { var s: []const u8 = "i16"; return s; }
    if (ty.kind == TypeKind.i32_type) { var s: []const u8 = "i32"; return s; }
    if (ty.kind == TypeKind.i64_type) { var s: []const u8 = "i64"; return s; }
    if (ty.kind == TypeKind.u8_type) { var s: []const u8 = "u8"; return s; }
    if (ty.kind == TypeKind.u16_type) { var s: []const u8 = "u16"; return s; }
    if (ty.kind == TypeKind.u32_type) { var s: []const u8 = "u32"; return s; }
    if (ty.kind == TypeKind.u64_type) { var s: []const u8 = "u64"; return s; }
    if (ty.kind == TypeKind.isize_type) { var s: []const u8 = "isize"; return s; }
    if (ty.kind == TypeKind.usize_type) { var s: []const u8 = "usize"; return s; }
    if (ty.kind == TypeKind.c_char_type) { var s: []const u8 = "c_char"; return s; }
    if (ty.kind == TypeKind.bool_type) { var s: []const u8 = "bool"; return s; }
    if (ty.kind == TypeKind.f32_type) { var s: []const u8 = "f32"; return s; }
    if (ty.kind == TypeKind.f64_type) { var s: []const u8 = "f64"; return s; }
    { var s: []const u8 = "u32"; return s; }
}

fn isBootstrapHelperDefined(fn_name: []const u8) bool {
    var h1: []const u8 = "__bootstrap_usize_from_i64";
    if (mem_mod.mem_eql(fn_name, h1)) { return true; }
    var h2: []const u8 = "__bootstrap_i32_from_u32";
    if (mem_mod.mem_eql(fn_name, h2)) { return true; }
    var h3: []const u8 = "__bootstrap_u32_from_u64";
    if (mem_mod.mem_eql(fn_name, h3)) { return true; }
    var h4: []const u8 = "__bootstrap_u32_from_i32";
    if (mem_mod.mem_eql(fn_name, h4)) { return true; }
    var h5: []const u8 = "__bootstrap_usize_from_i32";
    if (mem_mod.mem_eql(fn_name, h5)) { return true; }
    var h6: []const u8 = "__bootstrap_i32_from_usize";
    if (mem_mod.mem_eql(fn_name, h6)) { return true; }
    var h7: []const u8 = "__bootstrap_u8_from_usize";
    if (mem_mod.mem_eql(fn_name, h7)) { return true; }
    var h8: []const u8 = "__bootstrap_u8_from_bool";
    if (mem_mod.mem_eql(fn_name, h8)) { return true; }
    var h9: []const u8 = "__bootstrap_f32_from_f64";
    if (mem_mod.mem_eql(fn_name, h9)) { return true; }
    var h10: []const u8 = "__bootstrap_i32_from_u8";
    if (mem_mod.mem_eql(fn_name, h10)) { return true; }
    var h11: []const u8 = "__bootstrap_u8_from_i32";
    if (mem_mod.mem_eql(fn_name, h11)) { return true; }
    var h12: []const u8 = "__bootstrap_u8_from_u32";
    if (mem_mod.mem_eql(fn_name, h12)) { return true; }
    var h13: []const u8 = "__bootstrap_u16_from_i32";
    if (mem_mod.mem_eql(fn_name, h13)) { return true; }
    var h14: []const u8 = "__bootstrap_u32_from_i64";
    if (mem_mod.mem_eql(fn_name, h14)) { return true; }
    var h15: []const u8 = "__bootstrap_u64_from_i64";
    if (mem_mod.mem_eql(fn_name, h15)) { return true; }
    var h16: []const u8 = "__bootstrap_i8_from_i32";
    if (mem_mod.mem_eql(fn_name, h16)) { return true; }
    var h17: []const u8 = "__bootstrap_i16_from_i32";
    if (mem_mod.mem_eql(fn_name, h17)) { return true; }
    var h18: []const u8 = "__bootstrap_i32_from_i64";
    if (mem_mod.mem_eql(fn_name, h18)) { return true; }
    var h19: []const u8 = "__bootstrap_c_char_from_u8";
    if (mem_mod.mem_eql(fn_name, h19)) { return true; }
    return false;
}

fn getPrintFnName(reg: *TypeRegistry, tid: u32, fmt: u8) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    var is_hex: u8 = if (fmt == @intCast(u8, 'x')) @intCast(u8, 1) else @intCast(u8, 0);
    if (ty.kind == TypeKind.u32_type) {
        if (is_hex != @intCast(u8, 0)) { var h: []const u8 = "std_print_hex_u32"; return h; }
        { var s: []const u8 = "std_print_u32"; return s; }
    }
    if (ty.kind == TypeKind.i32_type) {
        if (is_hex != @intCast(u8, 0)) { var h: []const u8 = "std_print_hex_i32"; return h; }
        { var s: []const u8 = "std_print_i32"; return s; }
    }
    if (ty.kind == TypeKind.i64_type) {
        if (is_hex != @intCast(u8, 0)) { var h: []const u8 = "std_print_hex_i64"; return h; }
        { var s: []const u8 = "std_print_i64"; return s; }
    }
    if (ty.kind == TypeKind.u64_type) {
        if (is_hex != @intCast(u8, 0)) { var h: []const u8 = "std_print_hex_u64"; return h; }
        { var s: []const u8 = "std_print_u64"; return s; }
    }
    if (ty.kind == TypeKind.f64_type) { var s: []const u8 = "std_print_f64"; return s; }
    if (ty.kind == TypeKind.bool_type) { var s: []const u8 = "std_print_bool"; return s; }
    if (ty.kind == TypeKind.u8_type) {
        if (fmt == @intCast(u8, 'c')) { var s: []const u8 = "std_print_char"; return s; }
        if (is_hex != @intCast(u8, 0)) { var h: []const u8 = "std_print_hex_u32"; return h; }
        { var s: []const u8 = "std_print_u32"; return s; }
    }
    if (ty.kind == TypeKind.slice_type) { var s: []const u8 = "std_print_str"; return s; }
    { var s: []const u8 = "std_print_i32"; return s; }
}

fn emitCStringLiteral(writer: *BufferedWriter, str: []const u8) void {
    var s: []const u8 = "\"";
    bufferedWriterWrite(writer, s);
    var i: usize = @intCast(usize, 0);
    while (i < str.len) : (i += @intCast(usize, 1)) {
        var c = str[i];
        if (c == @intCast(u8, 10)) { var esc: []const u8 = "\\n"; bufferedWriterWrite(writer, esc); }
        else if (c == @intCast(u8, 9)) { var esc: []const u8 = "\\t"; bufferedWriterWrite(writer, esc); }
        else if (c == @intCast(u8, 13)) { var esc: []const u8 = "\\r"; bufferedWriterWrite(writer, esc); }
        else if (c == @intCast(u8, 92)) { var esc: []const u8 = "\\\\"; bufferedWriterWrite(writer, esc); }
        else if (c == @intCast(u8, 34)) { var esc: []const u8 = "\\\""; bufferedWriterWrite(writer, esc); }
        else if (c >= @intCast(u8, 32)) { bufferedWriterWriteByte(writer, c); }
        else { var esc: []const u8 = "."; bufferedWriterWrite(writer, esc); }
    }
    var se: []const u8 = "\"";
    bufferedWriterWrite(writer, se);
}

 fn resolveTempName(emitter: *C89Emitter, temp_id: u32) []const u8 {
     var rti: u32 = emitter.fl_count;
     while (rti > @intCast(u32, 0)) { rti = rti - @intCast(u32, 1); if (emitter.fl_temps[@intCast(usize, rti)] == temp_id) {
         var rst_m: []const u8 = "RST:t"; pal.markerWrite(rst_m);
         var rst_tb: [10]u8 = undefined; var rst_tl = itoa_mod.itoa(temp_id, rst_tb[0..]); var rst_ts: usize = @intCast(usize, 9) - @intCast(usize, rst_tl); pal.markerWrite(rst_tb[rst_ts..@intCast(usize, 9)]);
         var rst_nm: []const u8 = "N"; pal.markerWrite(rst_nm);
         var rst_nb: [10]u8 = undefined; var rst_nl = itoa_mod.itoa(emitter.fl_name_ids[@intCast(usize, rti)], rst_nb[0..]); var rst_ns: usize = @intCast(usize, 9) - @intCast(usize, rst_nl); pal.markerWrite(rst_nb[rst_ns..@intCast(usize, 9)]);
         var rst_nl2: []const u8 = "\n"; pal.markerWrite(rst_nl2);
         return mangleLocalName(emitter.mangler, emitter.interner, emitter.fl_name_ids[@intCast(usize, rti)]); } }
     var tgn_r = hash_mod.u32ToU32MapGet(&emitter.temp_global_map, temp_id);
     if (tgn_r) |tgi| {
         return interner_mod.stringInternerGet(emitter.interner, tgi);
     }
     var vflow_rnt: []const u8 = "VFLOW:rnt"; pal.markerWriteInt(vflow_rnt, temp_id);
     return mangleTempName(emitter.interner, temp_id);
 }

 fn emitFwriteCall(emitter: *C89Emitter, ptr: u32, len: u32, is_stdout: u8) void {
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var f0: []const u8 = "fwrite(";
    bufferedWriterWrite(&emitter.writer, f0);
    var fp = resolveTempName(emitter, ptr);
    bufferedWriterWrite(&emitter.writer, fp);
    var f1: []const u8 = ", 1, ";
    bufferedWriterWrite(&emitter.writer, f1);
    var fl = resolveTempName(emitter, len);
    bufferedWriterWrite(&emitter.writer, fl);
    var f2: []const u8 = ", ";
    bufferedWriterWrite(&emitter.writer, f2);
    var fs: []const u8 = "stdout";
    if (is_stdout == @intCast(u8, 0)) {
        var fserr: []const u8 = "stderr";
        fs = fserr;
    }
    bufferedWriterWrite(&emitter.writer, fs);
    var f3: []const u8 = ");\n";
    bufferedWriterWrite(&emitter.writer, f3);
 }

 fn emitConsoleClear(emitter: *C89Emitter) void {
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl0: []const u8 = "#ifdef _WIN32\n";
    bufferedWriterWrite(&emitter.writer, ccl0);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl1: []const u8 = "{ HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);\n";
    bufferedWriterWrite(&emitter.writer, ccl1);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl2: []const u8 = "CONSOLE_SCREEN_BUFFER_INFO csbi;\n";
    bufferedWriterWrite(&emitter.writer, ccl2);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl3: []const u8 = "DWORD count;\n";
    bufferedWriterWrite(&emitter.writer, ccl3);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl4: []const u8 = "DWORD cellCount;\n";
    bufferedWriterWrite(&emitter.writer, ccl4);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl5: []const u8 = "COORD homeCoords = { 0, 0 };\n";
    bufferedWriterWrite(&emitter.writer, ccl5);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl6: []const u8 = "if (hOut != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(hOut, &csbi)) {\n";
    bufferedWriterWrite(&emitter.writer, ccl6);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl7: []const u8 = "cellCount = csbi.dwSize.X * csbi.dwSize.Y;\n";
    bufferedWriterWrite(&emitter.writer, ccl7);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl8: []const u8 = "FillConsoleOutputCharacter(hOut, (TCHAR)' ', cellCount, homeCoords, &count);\n";
    bufferedWriterWrite(&emitter.writer, ccl8);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl9: []const u8 = "FillConsoleOutputAttribute(hOut, csbi.wAttributes, cellCount, homeCoords, &count);\n";
    bufferedWriterWrite(&emitter.writer, ccl9);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl10: []const u8 = "SetConsoleCursorPosition(hOut, homeCoords);\n";
    bufferedWriterWrite(&emitter.writer, ccl10);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl11: []const u8 = "} }\n";
    bufferedWriterWrite(&emitter.writer, ccl11);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl12: []const u8 = "#elif defined(__WATCOMC__)\n";
    bufferedWriterWrite(&emitter.writer, ccl12);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl13: []const u8 = "std_print_len(\"\\x1b[2J\\x1b[H\", 7);\n";
    bufferedWriterWrite(&emitter.writer, ccl13);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl14: []const u8 = "#else\n";
    bufferedWriterWrite(&emitter.writer, ccl14);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, ccl13);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var ccl15: []const u8 = "#endif\n";
    bufferedWriterWrite(&emitter.writer, ccl15);
 }

 fn emitConsoleGotoxy(emitter: *C89Emitter, x: u32, y: u32) void {
    var cx = resolveTempName(emitter, x);
    var cy = resolveTempName(emitter, y);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cg0: []const u8 = "#ifdef _WIN32\n";
    bufferedWriterWrite(&emitter.writer, cg0);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cg1: []const u8 = "{ COORD c;\n";
    bufferedWriterWrite(&emitter.writer, cg1);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cg2: []const u8 = "c.X = (SHORT)(int)(";
    bufferedWriterWrite(&emitter.writer, cg2);
    bufferedWriterWrite(&emitter.writer, cx);
    var cg3: []const u8 = "); c.Y = (SHORT)(int)(";
    bufferedWriterWrite(&emitter.writer, cg3);
    bufferedWriterWrite(&emitter.writer, cy);
    var cg4: []const u8 = "); SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), c); }\n";
    bufferedWriterWrite(&emitter.writer, cg4);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cg5: []const u8 = "#elif defined(__WATCOMC__)\n";
    bufferedWriterWrite(&emitter.writer, cg5);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cg6: []const u8 = "{ char buf[32]; int len = sprintf(buf, \"\\x1b[%d;%dH\", (int)(";
    bufferedWriterWrite(&emitter.writer, cg6);
    bufferedWriterWrite(&emitter.writer, cy);
    var cg7: []const u8 = ") + 1, (int)(";
    bufferedWriterWrite(&emitter.writer, cg7);
    bufferedWriterWrite(&emitter.writer, cx);
    var cg8: []const u8 = ") + 1); std_print_len(buf, (unsigned int)len); }\n";
    bufferedWriterWrite(&emitter.writer, cg8);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cg9: []const u8 = "#else\n";
    bufferedWriterWrite(&emitter.writer, cg9);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, cg6);
    bufferedWriterWrite(&emitter.writer, cy);
    bufferedWriterWrite(&emitter.writer, cg7);
    bufferedWriterWrite(&emitter.writer, cx);
    bufferedWriterWrite(&emitter.writer, cg8);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cg10: []const u8 = "#endif\n";
    bufferedWriterWrite(&emitter.writer, cg10);
 }

 fn emitConsoleSetColor(emitter: *C89Emitter, fg: u32, bg: u32) void {
    var cf = resolveTempName(emitter, fg);
    var cb = resolveTempName(emitter, bg);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc0: []const u8 = "#ifdef _WIN32\n";
    bufferedWriterWrite(&emitter.writer, cc0);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc1: []const u8 = "SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), (WORD)(((int)(";
    bufferedWriterWrite(&emitter.writer, cc1);
    bufferedWriterWrite(&emitter.writer, cf);
    var cc2: []const u8 = ") & 0x0F) | (((int)(";
    bufferedWriterWrite(&emitter.writer, cc2);
    bufferedWriterWrite(&emitter.writer, cb);
    var cc3: []const u8 = ") & 0x0F) << 4)));\n";
    bufferedWriterWrite(&emitter.writer, cc3);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc4: []const u8 = "#elif defined(__WATCOMC__)\n";
    bufferedWriterWrite(&emitter.writer, cc4);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc5: []const u8 = "{ static const char* fg_ansi[] = {\"30\",\"34\",\"32\",\"36\",\"31\",\"35\",\"33\",\"37\",\"90\",\"94\",\"92\",\"96\",\"91\",\"95\",\"93\",\"97\"};\n";
    bufferedWriterWrite(&emitter.writer, cc5);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc6: []const u8 = "static const char* bg_ansi[] = {\"40\",\"44\",\"42\",\"46\",\"41\",\"45\",\"43\",\"47\",\"100\",\"104\",\"102\",\"106\",\"101\",\"105\",\"103\",\"107\"};\n";
    bufferedWriterWrite(&emitter.writer, cc6);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc7: []const u8 = "char buf[64];\n";
    bufferedWriterWrite(&emitter.writer, cc7);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc8: []const u8 = "int len = sprintf(buf, \"\\x1b[%s;%sm\", fg_ansi[(int)(";
    bufferedWriterWrite(&emitter.writer, cc8);
    bufferedWriterWrite(&emitter.writer, cf);
    var cc9: []const u8 = ") & 0x0F], bg_ansi[(int)(";
    bufferedWriterWrite(&emitter.writer, cc9);
    bufferedWriterWrite(&emitter.writer, cb);
    var cc10: []const u8 = ") & 0x0F]); std_print_len(buf, (unsigned int)len); }\n";
    bufferedWriterWrite(&emitter.writer, cc10);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc11: []const u8 = "#else\n";
    bufferedWriterWrite(&emitter.writer, cc11);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, cc5);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, cc6);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, cc7);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, cc8);
    bufferedWriterWrite(&emitter.writer, cf);
    bufferedWriterWrite(&emitter.writer, cc9);
    bufferedWriterWrite(&emitter.writer, cb);
    bufferedWriterWrite(&emitter.writer, cc10);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    var cc12: []const u8 = "#endif\n";
    bufferedWriterWrite(&emitter.writer, cc12);
 }

 fn emitSocketWrite(emitter: *C89Emitter, s: []const u8) void {
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, s);
 }

 fn emitSocketOptPtrValue(emitter: *C89Emitter, tid: u32) void {
    var name = resolveTempName(emitter, tid);
    var is_opt = false;
    var t = getTempTypeByIndex(emitter, tid);
    if (t != @intCast(u32, 0xFFFFFFFF)) {
        var ty = emitter.registry.types_items[@intCast(usize, t)];
        if (ty.kind == type_mod.TypeKind.optional_type) {
            is_opt = true;
        }
    }
    if (is_opt) {
        var open: []const u8 = "(";
        emitSocketWrite(emitter, open);
        emitSocketWrite(emitter, name);
        var has: []const u8 = ".has_value ? ";
        emitSocketWrite(emitter, has);
        emitSocketWrite(emitter, name);
        var no: []const u8 = ".value : NULL)";
        emitSocketWrite(emitter, no);
    } else {
        emitSocketWrite(emitter, name);
    }
 }

 fn emitSocketCreate(emitter: *C89Emitter, port: u32, result: u32) void {
    var r = resolveTempName(emitter, result);
    var p = resolveTempName(emitter, port);
    var a: []const u8 = "#ifdef _WIN32\n{ SOCKET s = socket(AF_INET, SOCK_STREAM, 0);\nstruct sockaddr_in addr;\n";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, r);
    var b: []const u8 = " = -1;\nif (s != INVALID_SOCKET) {\nmemset(&addr, 0, sizeof(addr));\naddr.sin_family = AF_INET;\naddr.sin_port = htons(";
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, p);
    var c: []const u8 = ");\naddr.sin_addr.s_addr = htonl(INADDR_ANY);\nif (bind(s, (struct sockaddr*)&addr, sizeof(addr)) != SOCKET_ERROR) {\n";
    emitSocketWrite(emitter, c);
    emitSocketWrite(emitter, r);
    var d: []const u8 = " = (int)s;\n} else {\nclosesocket(s);\n} } }\n#else\n{ int s;\nint opt = 1;\nstruct sockaddr_in addr;\ns = socket(AF_INET, SOCK_STREAM, 0);\n";
    emitSocketWrite(emitter, d);
    emitSocketWrite(emitter, r);
    var e: []const u8 = " = -1;\nif (s >= 0) {\nsetsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));\nmemset(&addr, 0, sizeof(addr));\naddr.sin_family = AF_INET;\naddr.sin_port = htons(";
    emitSocketWrite(emitter, e);
    emitSocketWrite(emitter, p);
    var f: []const u8 = ");\naddr.sin_addr.s_addr = htonl(INADDR_ANY);\nif (bind(s, (struct sockaddr*)&addr, sizeof(addr)) >= 0) {\n";
    emitSocketWrite(emitter, f);
    emitSocketWrite(emitter, r);
    var g: []const u8 = " = s;\n} else {\nclose(s);\n} } }\n#endif\n";
    emitSocketWrite(emitter, g);
 }

 fn emitSocketBindListen(emitter: *C89Emitter, sock: u32, backlog: u32, result: u32) void {
    var r = resolveTempName(emitter, result);
    var s = resolveTempName(emitter, sock);
    var b = resolveTempName(emitter, backlog);
    var a: []const u8 = "#ifdef _WIN32\n";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, r);
    var c: []const u8 = " = (listen((SOCKET)";
    emitSocketWrite(emitter, c);
    emitSocketWrite(emitter, s);
    var d: []const u8 = ", ";
    emitSocketWrite(emitter, d);
    emitSocketWrite(emitter, b);
    var e: []const u8 = ") == SOCKET_ERROR) ? -1 : 0;\n#else\n";
    emitSocketWrite(emitter, e);
    emitSocketWrite(emitter, r);
    var f: []const u8 = " = (listen(";
    emitSocketWrite(emitter, f);
    emitSocketWrite(emitter, s);
    emitSocketWrite(emitter, d);
    emitSocketWrite(emitter, b);
    var g: []const u8 = ") < 0) ? -1 : 0;\n#endif\n";
    emitSocketWrite(emitter, g);
 }

 fn emitSocketAccept(emitter: *C89Emitter, sock: u32, result: u32) void {
    var r = resolveTempName(emitter, result);
    var s = resolveTempName(emitter, sock);
    var a: []const u8 = "#ifdef _WIN32\n{ SOCKET client = accept((SOCKET)";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, s);
    var b: []const u8 = ", NULL, NULL);\n";
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, r);
    var c: []const u8 = " = (client == INVALID_SOCKET) ? -1 : (int)client; }\n#else\n";
    emitSocketWrite(emitter, c);
    emitSocketWrite(emitter, r);
    var d: []const u8 = " = accept(";
    emitSocketWrite(emitter, d);
    emitSocketWrite(emitter, s);
    var e: []const u8 = ", NULL, NULL);\n#endif\n";
    emitSocketWrite(emitter, e);
 }

 fn emitSocketConnect(emitter: *C89Emitter, sock: u32, port: u32, result: u32) void {
    var r = resolveTempName(emitter, result);
    var s = resolveTempName(emitter, sock);
    var p = resolveTempName(emitter, port);
    var a: []const u8 = "#ifdef _WIN32\n{ struct sockaddr_in addr;\nmemset(&addr, 0, sizeof(addr));\naddr.sin_family = AF_INET;\naddr.sin_port = htons(";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, p);
    var b: []const u8 = ");\naddr.sin_addr.s_addr = htonl(INADDR_ANY);\n";
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, r);
    var c: []const u8 = " = (connect((SOCKET)";
    emitSocketWrite(emitter, c);
    emitSocketWrite(emitter, s);
    var d: []const u8 = ", (struct sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR) ? -1 : 0; }\n#else\n{ struct sockaddr_in addr;\nmemset(&addr, 0, sizeof(addr));\naddr.sin_family = AF_INET;\naddr.sin_port = htons(";
    emitSocketWrite(emitter, d);
    emitSocketWrite(emitter, p);
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, r);
    var e: []const u8 = " = (connect(";
    emitSocketWrite(emitter, e);
    emitSocketWrite(emitter, s);
    var f: []const u8 = ", (struct sockaddr*)&addr, sizeof(addr)) < 0) ? -1 : 0; }\n#endif\n";
    emitSocketWrite(emitter, f);
 }

 fn emitSocketSendRecv(emitter: *C89Emitter, sock: u32, buf: u32, len: u32, result: u32, is_recv: u8) void {
    var r = resolveTempName(emitter, result);
    var s = resolveTempName(emitter, sock);
    var b = resolveTempName(emitter, buf);
    var l = resolveTempName(emitter, len);
    var fn_call: []const u8 = "send";
    var cnst: []const u8 = "const ";
    if (is_recv != @intCast(u8, 0)) {
        var fnr: []const u8 = "recv";
        fn_call = fnr;
        var cnr: []const u8 = "";
        cnst = cnr;
    }
    var a: []const u8 = "#ifdef _WIN32\n";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, r);
    var b0: []const u8 = " = ";
    emitSocketWrite(emitter, b0);
    emitSocketWrite(emitter, fn_call);
    var c: []const u8 = "((SOCKET)";
    emitSocketWrite(emitter, c);
    emitSocketWrite(emitter, s);
    var d: []const u8 = ", (";
    emitSocketWrite(emitter, d);
    emitSocketWrite(emitter, cnst);
    var e: []const u8 = "char*)";
    emitSocketWrite(emitter, e);
    emitSocketWrite(emitter, b);
    var f: []const u8 = ", ";
    emitSocketWrite(emitter, f);
    emitSocketWrite(emitter, l);
    var g: []const u8 = ", 0);\n#else\n";
    emitSocketWrite(emitter, g);
    emitSocketWrite(emitter, r);
    emitSocketWrite(emitter, b0);
    emitSocketWrite(emitter, fn_call);
    var h: []const u8 = "(";
    emitSocketWrite(emitter, h);
    emitSocketWrite(emitter, s);
    emitSocketWrite(emitter, d);
    emitSocketWrite(emitter, cnst);
    emitSocketWrite(emitter, e);
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, f);
    emitSocketWrite(emitter, l);
    var i: []const u8 = ", 0);\n#endif\n";
    emitSocketWrite(emitter, i);
 }

 fn emitSocketSelect(emitter: *C89Emitter, nfds: u32, readfds: u32, writefds: u32, exceptfds: u32, timeout_ms: u32, result: u32) void {
    var r = resolveTempName(emitter, result);
    var n = resolveTempName(emitter, nfds);
    var t = resolveTempName(emitter, timeout_ms);
    var a: []const u8 = "{ struct timeval tv;\nstruct timeval* p_tv = NULL;\nif (";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, t);
    var b: []const u8 = " >= 0) {\ntv.tv_sec = ";
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, t);
    var c: []const u8 = " / 1000;\ntv.tv_usec = (";
    emitSocketWrite(emitter, c);
    emitSocketWrite(emitter, t);
    var d: []const u8 = " % 1000) * 1000;\np_tv = &tv;\n}\n";
    emitSocketWrite(emitter, d);
    var w: []const u8 = "#ifdef _WIN32\n";
    emitSocketWrite(emitter, w);
    emitSocketWrite(emitter, r);
    var e: []const u8 = " = select(";
    emitSocketWrite(emitter, e);
    emitSocketWrite(emitter, n);
    var f: []const u8 = ", (fd_set*)";
    emitSocketWrite(emitter, f);
    emitSocketOptPtrValue(emitter, readfds);
    emitSocketWrite(emitter, f);
    emitSocketOptPtrValue(emitter, writefds);
    emitSocketWrite(emitter, f);
    emitSocketOptPtrValue(emitter, exceptfds);
    var g: []const u8 = ", p_tv);\n#else\n";
    emitSocketWrite(emitter, g);
    emitSocketWrite(emitter, r);
    emitSocketWrite(emitter, e);
    emitSocketWrite(emitter, n);
    emitSocketWrite(emitter, f);
    emitSocketOptPtrValue(emitter, readfds);
    emitSocketWrite(emitter, f);
    emitSocketOptPtrValue(emitter, writefds);
    emitSocketWrite(emitter, f);
    emitSocketOptPtrValue(emitter, exceptfds);
    var h: []const u8 = ", p_tv);\n#endif\n}\n";
    emitSocketWrite(emitter, h);
 }

 fn emitSocketFdSet(emitter: *C89Emitter, fd: u32, set: u32, is_isset: u8, result: u32) void {
    var f = resolveTempName(emitter, fd);
    var s = resolveTempName(emitter, set);
    var a: []const u8 = "#ifdef _WIN32\n";
    emitSocketWrite(emitter, a);
    if (is_isset != @intCast(u8, 0)) {
        var r = resolveTempName(emitter, result);
        emitSocketWrite(emitter, r);
        var b: []const u8 = " = (FD_ISSET((SOCKET)";
        emitSocketWrite(emitter, b);
        emitSocketWrite(emitter, f);
        var c: []const u8 = ", (fd_set*)";
        emitSocketWrite(emitter, c);
        emitSocketWrite(emitter, s);
        var d: []const u8 = ") != 0);\n#else\n";
        emitSocketWrite(emitter, d);
        emitSocketWrite(emitter, r);
        var e: []const u8 = " = (FD_ISSET(";
        emitSocketWrite(emitter, e);
        emitSocketWrite(emitter, f);
        emitSocketWrite(emitter, c);
        emitSocketWrite(emitter, s);
        var g: []const u8 = ") != 0);\n#endif\n";
        emitSocketWrite(emitter, g);
    } else {
        var h: []const u8 = "FD_SET((SOCKET)";
        emitSocketWrite(emitter, h);
        emitSocketWrite(emitter, f);
        var i: []const u8 = ", (fd_set*)";
        emitSocketWrite(emitter, i);
        emitSocketWrite(emitter, s);
        var j: []const u8 = ");\n#else\nFD_SET(";
        emitSocketWrite(emitter, j);
        emitSocketWrite(emitter, f);
        emitSocketWrite(emitter, i);
        emitSocketWrite(emitter, s);
        var k: []const u8 = ");\n#endif\n";
        emitSocketWrite(emitter, k);
    }
 }

 fn emitSocketFdZero(emitter: *C89Emitter, set: u32) void {
    var s = resolveTempName(emitter, set);
    var a: []const u8 = "#ifdef _WIN32\nFD_ZERO((fd_set*)";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, s);
    var b: []const u8 = ");\n#else\nFD_ZERO((fd_set*)";
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, s);
    var c: []const u8 = ");\n#endif\n";
    emitSocketWrite(emitter, c);
 }

 fn emitSocketClose(emitter: *C89Emitter, sock: u32) void {
    var s = resolveTempName(emitter, sock);
    var a: []const u8 = "#ifdef _WIN32\nclosesocket((SOCKET)";
    emitSocketWrite(emitter, a);
    emitSocketWrite(emitter, s);
    var b: []const u8 = ");\n#else\nclose(";
    emitSocketWrite(emitter, b);
    emitSocketWrite(emitter, s);
    var c: []const u8 = ");\n#endif\n";
    emitSocketWrite(emitter, c);
 }


 fn emitInst(emitter: *C89Emitter, inst: LirInst) void {
    var ins: []const u8 = "I\n"; pal.markerWrite(ins);
    switch (inst) {
        .nop => {},
        .ret_void => {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var rv_rt = emitter.current_fn.return_type;
            if (rv_rt == type_mod.TYPE_VOID or rv_rt == type_mod.TYPE_UNDEFINED or rv_rt == @intCast(u32, 0)) {
                var s: []const u8 = "return;\n";
                bufferedWriterWrite(&emitter.writer, s);
            } else if (retTypeIsScalarC(emitter.registry, rv_rt) == @intCast(u8, 1)) {
                var s: []const u8 = "return 0;\n";
                bufferedWriterWrite(&emitter.writer, s);
            } else {
                var s0: []const u8 = "return (";
                bufferedWriterWrite(&emitter.writer, s0);
                var rv_cn = getCTypeName(emitter.registry, emitter.mangler, rv_rt);
                bufferedWriterWrite(&emitter.writer, rv_cn);
                var s1: []const u8 = "){0};\n";
                bufferedWriterWrite(&emitter.writer, s1);
            }
        },
        .loop_header => |hdr| {
            if (emitter.bb_used_count > @intCast(u32, 0) and emitter.bb_used[@intCast(usize, 0)] != @intCast(u8, 0)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var label_s: []const u8 = "z_bb_0:\n";
                bufferedWriterWrite(&emitter.writer, label_s);
            }
        },
        .label => {},

         .decl_local => |dl| {},
            .assign => |a| {
             var asx_m: []const u8 = "ASX:d"; pal.markerWrite(asx_m);
             var asx_db: [10]u8 = undefined; var asx_dl = itoa_mod.itoa(a.dst, asx_db[0..]); var asx_ds: usize = @intCast(usize, 9) - @intCast(usize, asx_dl); pal.markerWrite(asx_db[asx_ds..@intCast(usize, 9)]);
             var asx_sb: [10]u8 = undefined; var asx_sl = itoa_mod.itoa(a.src, asx_sb[0..]); var asx_ss: usize = @intCast(usize, 9) - @intCast(usize, asx_sl); pal.markerWrite(asx_sb[asx_ss..@intCast(usize, 9)]);
             var asx_nl: []const u8 = "\n"; pal.markerWrite(asx_nl);
             var as_tj: usize = @intCast(usize, 0);
             while (as_tj < emitter.current_fn.hoisted_temps.len) : (as_tj += @intCast(usize, 1)) {
                 var as_ht = emitter.current_fn.hoisted_temps.items[as_tj];
                 if (as_ht.temp_id == a.dst) {
                     var as_m: []const u8 = "AS:t"; pal.markerWrite(as_m);
                     var as_b: [10]u8 = undefined; var as_l = itoa_mod.itoa(as_ht.type_id, as_b[0..]); var as_s: usize = @intCast(usize, 9) - @intCast(usize, as_l); pal.markerWrite(as_b[as_s..@intCast(usize, 9)]);
                     var as_n: []const u8 = "\n"; pal.markerWrite(as_n);
                     break;
                 }
             }
             if (pal.isMarkersEnabled()) {
             var mkb: []const u8 = "/*==MARKER_ASSIGN dst=";
            bufferedWriterWrite(&emitter.writer, mkb);
            var mkdst = resolveTempName(emitter, a.dst);
            bufferedWriterWrite(&emitter.writer, mkdst);
            var mksep: []const u8 = " src=";
            bufferedWriterWrite(&emitter.writer, mksep);
            var mksrc = resolveTempName(emitter, a.src);
            bufferedWriterWrite(&emitter.writer, mksrc);
            var mkend: []const u8 = "==*/\n";
            bufferedWriterWrite(&emitter.writer, mkend);
            }
            var dst = if (a.name_id != @intCast(u32, 0)) mangleLocalName(emitter.mangler, emitter.interner, a.name_id) else resolveTempName(emitter, a.dst);
            var src = resolveTempName(emitter, a.src);
            var rfli: u32 = emitter.fl_count;
            while (rfli > @intCast(u32, 0)) { rfli = rfli - @intCast(u32, 1); if (emitter.fl_temps[@intCast(usize, rfli)] == a.dst) { dst = mangleLocalName(emitter.mangler, emitter.interner, emitter.fl_name_ids[@intCast(usize, rfli)]); break; } }
            var as_dname: u32 = @intCast(u32, 0);
            if (a.name_id != @intCast(u32, 0)) { as_dname = a.name_id; }
            else if (rfli < emitter.fl_count and emitter.fl_temps[@intCast(usize, rfli)] == a.dst) { as_dname = emitter.fl_name_ids[@intCast(usize, rfli)]; }
            if (as_dname != @intCast(u32, 0) and isDeadLocalName(emitter, as_dname) != @intCast(u8, 0)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var vd: []const u8 = "(void)";
                bufferedWriterWrite(&emitter.writer, vd);
                bufferedWriterWrite(&emitter.writer, src);
                var vd2: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, vd2);
                return;
            }
            var is_arr: u8 = @intCast(u8, 0);
            var arr_len: u32 = @intCast(u32, 0);
            var tj_ca: usize = @intCast(usize, 0);
            while (tj_ca < emitter.current_fn.hoisted_temps.len) : (tj_ca += @intCast(usize, 1)) {
                var ht_ca = emitter.current_fn.hoisted_temps.items[tj_ca];
                if (ht_ca.temp_id == a.dst) {
                    var dty = emitter.registry.types_items[@intCast(usize, ht_ca.type_id)];
                    if (dty.kind == type_mod.TypeKind.array_type) {
                        is_arr = @intCast(u8, 1);
                        var ap = emitter.registry.array_items[@intCast(usize, dty.payload_idx)];
                        arr_len = ap.length;
                    }
                    break;
                }
            }
            if (is_arr == @intCast(u8, 1)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var loop_begin: []const u8 = "{\n";
                bufferedWriterWrite(&emitter.writer, loop_begin);
                var as_zi = arrLoopDeclSigned(arr_len);
                bufferedWriterWrite(&emitter.writer, as_zi);
                var loop_cond: []const u8 = "    while (_i < ";
                bufferedWriterWrite(&emitter.writer, loop_cond);
                var alb: [20]u8 = undefined;
                var all = itoa_mod.itoa(arr_len, alb[0..]);
                var als: usize = @intCast(usize, 19) - @intCast(usize, all);
                bufferedWriterWrite(&emitter.writer, alb[als..@intCast(usize, 19)]);
                var loop_body: []const u8 = ") {\n        ";
                bufferedWriterWrite(&emitter.writer, loop_body);
                bufferedWriterWrite(&emitter.writer, dst);
                var lb: []const u8 = "[_i] = ";
                bufferedWriterWrite(&emitter.writer, lb);
                bufferedWriterWrite(&emitter.writer, src);
                var rb: []const u8 = "[_i];\n        _i++;\n    }\n}\n";
                bufferedWriterWrite(&emitter.writer, rb);
            } else {
                var as_cast: []const u8 = "";
                var as_dty: u32 = @intCast(u32, 0xFFFFFFFF);
                var as_dsg: u8 = @intCast(u8, 0);
                if (getTempEffType(emitter, a.dst, &as_dty, &as_dsg) == @intCast(u8, 1) and typeIsPtrKind(emitter.registry, as_dty) != @intCast(u8, 0)) {
                    var as_sty: u32 = @intCast(u32, 0xFFFFFFFF);
                    var as_ssg: u8 = @intCast(u8, 0);
                    if (getTempEffType(emitter, a.src, &as_sty, &as_ssg) == @intCast(u8, 1) and typeIsIntKind(emitter.registry, as_sty) != @intCast(u8, 0)) {
                        as_cast = getCTypeName(emitter.registry, emitter.mangler, as_dty);
                    }
                }
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var sep: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, sep);
                if (as_cast.len != @intCast(usize, 0)) {
                    var ac0: []const u8 = "("; bufferedWriterWrite(&emitter.writer, ac0);
                    bufferedWriterWrite(&emitter.writer, as_cast);
                    var ac1: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, ac1);
                }
                bufferedWriterWrite(&emitter.writer, src);
                var sep2: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, sep2);
            }
        },
          .assign_field => |a| {
              var base: []const u8 = if (a.name_id != @intCast(u32, 0)) mangleLocalName(emitter.mangler, emitter.interner, a.name_id) else resolveTempName(emitter, a.base);
              var src = resolveTempName(emitter, a.src);
              bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
              if (dceFieldIsArray(emitter.registry, emitter.current_fn, a.base, a.field_id)) {
                  var vp: []const u8 = "(void)";
                  bufferedWriterWrite(&emitter.writer, vp);
              }
              bufferedWriterWrite(&emitter.writer, base);
              emitFieldAssign(&emitter.writer, emitter.indent, emitter.registry, emitter.mangler, emitter.interner, emitter.current_fn, emitter.current_fn.hoisted_temps.items, emitter.current_fn.hoisted_temps.len, base, a.base, a.field_id, src, a.src, emitter);
              var afe_m: []const u8 = "AFE:b"; pal.markerWrite(afe_m);
              var afe_bb: [10]u8 = undefined; var afe_bl = itoa_mod.itoa(a.base, afe_bb[0..]); var afe_bs: usize = @intCast(usize, 9) - @intCast(usize, afe_bl); pal.markerWrite(afe_bb[afe_bs..@intCast(usize, 9)]);
              var afe_fm: []const u8 = "f"; pal.markerWrite(afe_fm);
              var afe_fb: [10]u8 = undefined; var afe_fl = itoa_mod.itoa(a.field_id, afe_fb[0..]); var afe_fs: usize = @intCast(usize, 9) - @intCast(usize, afe_fl); pal.markerWrite(afe_fb[afe_fs..@intCast(usize, 9)]);
              var afe_nl: []const u8 = "\n"; pal.markerWrite(afe_nl);
          },
          .assign_index => |a| {
            var adm2: []const u8 = "AIDX:b"; pal.markerWrite(adm2);
            var adm2b: [10]u8 = undefined; var adm2l = itoa_mod.itoa(a.base, adm2b[0..]); var adm2s: usize = @intCast(usize, 9) - @intCast(usize, adm2l); pal.markerWrite(adm2b[adm2s..@intCast(usize, 9)]);
            var adm2i: []const u8 = "i"; pal.markerWrite(adm2i);
            var adm2ib: [10]u8 = undefined; var adm2il = itoa_mod.itoa(a.index, adm2ib[0..]); var adm2is: usize = @intCast(usize, 9) - @intCast(usize, adm2il); pal.markerWrite(adm2ib[adm2is..@intCast(usize, 9)]);
            var adm2s2: []const u8 = "s"; pal.markerWrite(adm2s2);
            var adm2sb: [10]u8 = undefined; var adm2sl = itoa_mod.itoa(a.src, adm2sb[0..]); var adm2ss: usize = @intCast(usize, 9) - @intCast(usize, adm2sl); pal.markerWrite(adm2sb[adm2ss..@intCast(usize, 9)]);
            var adm2nl2: []const u8 = " "; pal.markerWrite(adm2nl2);
            var base: []const u8 = if (a.name_id != @intCast(u32, 0)) mangleLocalName(emitter.mangler, emitter.interner, a.name_id) else resolveTempName(emitter, a.base);
            var idx = resolveTempName(emitter, a.index);
            var src = resolveTempName(emitter, a.src);
            var src_name = resolveTempName(emitter, a.src);
            emitBaseIdxAccess(emitter, a.base, a.index, src_name, @intCast(u8, 1));
        },
        .jump => |bb| {
            var jxp_m: []const u8 = "JXP\n"; pal.markerWrite(jxp_m);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s: []const u8 = "goto z_bb_";
            bufferedWriterWrite(&emitter.writer, s);
            var nb: [16]u8 = undefined;
            var nl = itoa_mod.itoa(bb, nb[0..]);
            var ns: u32 = @intCast(u32, @intCast(u32, 15) - nl);
            var si: usize = @intCast(usize, ns);
            var ei: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, nb[si..ei]);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .branch => |b| {
            var cond = resolveTempName(emitter, b.cond);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s: []const u8 = "if (";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, cond);
            var s2: []const u8 = ") goto z_bb_";
            bufferedWriterWrite(&emitter.writer, s2);
            var tb: [16]u8 = undefined;
            var tl: u32 = itoa_mod.itoa(b.then_bb, tb[0..]);
            var ts: u32 = @intCast(u32, @intCast(u32, 15) - tl);
            var tsi: usize = @intCast(usize, ts);
            var tei: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, tb[tsi..tei]);
            var s3: []const u8 = "; else goto z_bb_";
            bufferedWriterWrite(&emitter.writer, s3);
            var eb: [16]u8 = undefined;
            var el: u32 = itoa_mod.itoa(b.else_bb, eb[0..]);
            var es: u32 = @intCast(u32, @intCast(u32, 15) - el);
            var esi: usize = @intCast(usize, es);
            var eei: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, eb[esi..eei]);
            var s4: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s4);
        },
        .ret => |v| {
            var val = resolveTempName(emitter, v);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s: []const u8 = "return ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, val);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .load_local => |ll| {
            var result = resolveTempName(emitter, ll.result);
            var name = mangleLocalName(emitter.mangler, emitter.interner, ll.name_id);
            var llm: []const u8 = "LL:n"; pal.markerWrite(llm);
            var llnb: [10]u8 = undefined; var llnl = itoa_mod.itoa(ll.name_id, llnb[0..]); var llns: usize = @intCast(usize, 9) - @intCast(usize, llnl); pal.markerWrite(llnb[llns..@intCast(usize, 9)]);
            var llrm: []const u8 = "r"; pal.markerWrite(llrm);
            var llrb: [10]u8 = undefined; var llrl = itoa_mod.itoa(ll.result, llrb[0..]); var llrs: usize = @intCast(usize, 9) - @intCast(usize, llrl); pal.markerWrite(llrb[llrs..@intCast(usize, 9)]);
            var llnl2: []const u8 = "\n"; pal.markerWrite(llnl2);
            var ll_is_arr: u8 = @intCast(u8, 0);
            var ll_arr_len: u32 = @intCast(u32, 0);
            var ll_tj: usize = @intCast(usize, 0);
            while (ll_tj < emitter.current_fn.hoisted_temps.len) : (ll_tj += @intCast(usize, 1)) {
                var ll_ht = emitter.current_fn.hoisted_temps.items[ll_tj];
                if (ll_ht.temp_id == ll.result) {
                    var ll_dty = emitter.registry.types_items[@intCast(usize, ll_ht.type_id)];
                    if (ll_dty.kind == type_mod.TypeKind.array_type) {
                        ll_is_arr = @intCast(u8, 1);
                        var ll_ap = emitter.registry.array_items[@intCast(usize, ll_dty.payload_idx)];
                        ll_arr_len = ll_ap.length;
                    }
                    break;
                }
            }
            if (ll_is_arr == @intCast(u8, 1)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var ll_zi = arrLoopDeclOpenSigned(ll_arr_len);
                bufferedWriterWrite(&emitter.writer, ll_zi);
                var alb: [20]u8 = undefined;
                var all = itoa_mod.itoa(ll_arr_len, alb[0..]);
                var als: usize = @intCast(usize, 19) - @intCast(usize, all);
                bufferedWriterWrite(&emitter.writer, alb[als..@intCast(usize, 19)]);
                var loop_body: []const u8 = ") {\n        ";
                bufferedWriterWrite(&emitter.writer, loop_body);
                bufferedWriterWrite(&emitter.writer, result);
                var lb: []const u8 = "[_i] = ";
                bufferedWriterWrite(&emitter.writer, lb);
                bufferedWriterWrite(&emitter.writer, name);
                var rb: []const u8 = "[_i];\n        _i++;\n    }\n}\n";
                bufferedWriterWrite(&emitter.writer, rb);
            } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, result);
                var s: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s);
                bufferedWriterWrite(&emitter.writer, name);
                var s2: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, s2);
            }
        },
         .store_local => |sl| {
              var stl_m: []const u8 = "STL:n"; pal.markerWrite(stl_m);
              var stl_nb: [10]u8 = undefined; var stl_nl = itoa_mod.itoa(sl.name_id, stl_nb[0..]); var stl_ns: usize = @intCast(usize, 9) - @intCast(usize, stl_nl); pal.markerWrite(stl_nb[stl_ns..@intCast(usize, 9)]);
              var stl_vm: []const u8 = "v"; pal.markerWrite(stl_vm);
              var stl_vb: [10]u8 = undefined; var stl_vl = itoa_mod.itoa(sl.value, stl_vb[0..]); var stl_vs: usize = @intCast(usize, 9) - @intCast(usize, stl_vl); pal.markerWrite(stl_vb[stl_vs..@intCast(usize, 9)]);
              var stl_nl2: []const u8 = "\n"; pal.markerWrite(stl_nl2);
             var val = resolveTempName(emitter, sl.value);
            var name = mangleLocalName(emitter.mangler, emitter.interner, sl.name_id);
            var stln_m: []const u8 = "STN:"; pal.markerWrite(stln_m);
            pal.markerWrite(name);
            var stln_c: []const u8 = "="; pal.markerWrite(stln_c);
            pal.markerWrite(val);
            var stln_nl: []const u8 = "\n"; pal.markerWrite(stln_nl);
            if ((name.len == @intCast(usize, 1) and name[0] == '_') or isDeadLocalName(emitter, sl.name_id) != @intCast(u8, 0)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var vd: []const u8 = "(void)";
                bufferedWriterWrite(&emitter.writer, vd);
                bufferedWriterWrite(&emitter.writer, val);
                var vd2: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, vd2);
            } else {
                var is_arr: u8 = @intCast(u8, 0);
                var arr_len: u32 = @intCast(u32, 0);
                var tj_ca: usize = @intCast(usize, 0);
                while (tj_ca < emitter.current_fn.hoisted_temps.len) : (tj_ca += @intCast(usize, 1)) {
                    var ht_ca = emitter.current_fn.hoisted_temps.items[tj_ca];
                    if (ht_ca.temp_id == sl.value) {
                        var dty = emitter.registry.types_items[@intCast(usize, ht_ca.type_id)];
                        if (dty.kind == type_mod.TypeKind.array_type) {
                            is_arr = @intCast(u8, 1);
                            var ap = emitter.registry.array_items[@intCast(usize, dty.payload_idx)];
                            arr_len = ap.length;
                        }
                        break;
                    }
                }
                if (is_arr == @intCast(u8, 1)) {
                    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                    var loop_begin: []const u8 = "{\n";
                    bufferedWriterWrite(&emitter.writer, loop_begin);
                    var stl_zi = arrLoopDeclSigned(arr_len);
                    bufferedWriterWrite(&emitter.writer, stl_zi);
                    var loop_cond: []const u8 = "    while (_i < ";
                    bufferedWriterWrite(&emitter.writer, loop_cond);
                    var alb: [20]u8 = undefined;
                    var all = itoa_mod.itoa(arr_len, alb[0..]);
                    var als: usize = @intCast(usize, 19) - @intCast(usize, all);
                    bufferedWriterWrite(&emitter.writer, alb[als..@intCast(usize, 19)]);
                    var loop_body: []const u8 = ") {\n        ";
                    bufferedWriterWrite(&emitter.writer, loop_body);
                    bufferedWriterWrite(&emitter.writer, name);
                    var lb: []const u8 = "[_i] = ";
                    bufferedWriterWrite(&emitter.writer, lb);
                    bufferedWriterWrite(&emitter.writer, val);
                    var rb: []const u8 = "[_i];\n        _i++;\n    }\n}\n";
                    bufferedWriterWrite(&emitter.writer, rb);
                } else {
                    var stl_cast: []const u8 = "";
                    var stl_ltid: u32 = @intCast(u32, 0xFFFFFFFF);
                    var stl_fi: u32 = emitter.fl_count;
                    while (stl_fi > @intCast(u32, 0)) {
                        stl_fi = stl_fi - @intCast(u32, 1);
                        if (emitter.fl_name_ids[@intCast(usize, stl_fi)] == sl.name_id) {
                            stl_ltid = emitter.fl_temps[@intCast(usize, stl_fi)];
                            break;
                        }
                    }
                    if (stl_ltid != @intCast(u32, 0xFFFFFFFF)) {
                        var stl_ty: u32 = @intCast(u32, 0xFFFFFFFF);
                        var stl_sg: u8 = @intCast(u8, 0);
                        if (getTempEffType(emitter, stl_ltid, &stl_ty, &stl_sg) == @intCast(u8, 1) and typeIsPtrKind(emitter.registry, stl_ty) != @intCast(u8, 0)) {
                            var stl_vty: u32 = @intCast(u32, 0xFFFFFFFF);
                            var stl_vsg: u8 = @intCast(u8, 0);
                            if (getTempEffType(emitter, sl.value, &stl_vty, &stl_vsg) == @intCast(u8, 1) and typeIsIntKind(emitter.registry, stl_vty) != @intCast(u8, 0)) {
                                stl_cast = getCTypeName(emitter.registry, emitter.mangler, stl_ty);
                            }
                        }
                    }
                    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                    bufferedWriterWrite(&emitter.writer, name);
                    var s: []const u8 = " = ";
                    bufferedWriterWrite(&emitter.writer, s);
                    if (stl_cast.len != @intCast(usize, 0)) {
                        var stl_c0: []const u8 = "(";
                        bufferedWriterWrite(&emitter.writer, stl_c0);
                        bufferedWriterWrite(&emitter.writer, stl_cast);
                        var stl_c1: []const u8 = ")";
                        bufferedWriterWrite(&emitter.writer, stl_c1);
                    }
                    bufferedWriterWrite(&emitter.writer, val);
                    var s2: []const u8 = ";\n";
                    bufferedWriterWrite(&emitter.writer, s2);
                }
            }
        },
        .load_global => |lg| {
            var lg_tid: u32 = @intCast(u32, 0);
            var lg_tj: usize = @intCast(usize, 0);
            while (lg_tj < emitter.current_fn.hoisted_temps.len) : (lg_tj += @intCast(usize, 1)) {
                var lg_ht = emitter.current_fn.hoisted_temps.items[lg_tj];
                if (lg_ht.temp_id == lg.result) { lg_tid = lg_ht.type_id; break; }
            }
            var gmid = nameManglerMangleGlobal(emitter.mangler, emitter.registry, lg.name_id, lg.module_id, lg_tid);
            hash_mod.u32ToU32MapPut(&emitter.temp_global_map, lg.result, gmid);
        },
        .store_global => |sg| {
            var sg_tid: u32 = @intCast(u32, 0);
            var sg_tj: usize = @intCast(usize, 0);
            while (sg_tj < emitter.current_fn.hoisted_temps.len) : (sg_tj += @intCast(usize, 1)) {
                var sg_ht = emitter.current_fn.hoisted_temps.items[sg_tj];
                if (sg_ht.temp_id == sg.value) { sg_tid = sg_ht.type_id; break; }
            }
            var val = resolveTempName(emitter, sg.value);
            var sgmid = nameManglerMangleGlobal(emitter.mangler, emitter.registry, sg.name_id, sg.module_id, sg_tid);
            var name = interner_mod.stringInternerGet(emitter.interner, sgmid);
            var sg_is_arr: u8 = @intCast(u8, 0);
            var sg_arr_len: u32 = @intCast(u32, 0);
            if (sg_tid < @intCast(u32, emitter.registry.types_len)) {
                var sg_dty = emitter.registry.types_items[@intCast(usize, sg_tid)];
                if (sg_dty.kind == type_mod.TypeKind.array_type) {
                    sg_is_arr = @intCast(u8, 1);
                    var sg_ap = emitter.registry.array_items[@intCast(usize, sg_dty.payload_idx)];
                    sg_arr_len = sg_ap.length;
                }
            }
            if (sg_is_arr == @intCast(u8, 1)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var sg_zi = arrLoopDeclOpenSigned(sg_arr_len);
                bufferedWriterWrite(&emitter.writer, sg_zi);
                var alb: [20]u8 = undefined;
                var all = itoa_mod.itoa(sg_arr_len, alb[0..]);
                var als: usize = @intCast(usize, 19) - @intCast(usize, all);
                bufferedWriterWrite(&emitter.writer, alb[als..@intCast(usize, 19)]);
                var loop_body: []const u8 = ") {\n        ";
                bufferedWriterWrite(&emitter.writer, loop_body);
                bufferedWriterWrite(&emitter.writer, name);
                var lb: []const u8 = "[_i] = ";
                bufferedWriterWrite(&emitter.writer, lb);
                bufferedWriterWrite(&emitter.writer, val);
                var rb: []const u8 = "[_i];\n        _i++;\n    }\n}\n";
                bufferedWriterWrite(&emitter.writer, rb);
            } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, name);
                var s: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s);
                bufferedWriterWrite(&emitter.writer, val);
                var s2: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, s2);
            }
        },
           .load_field => |lf| {
               var base = if (lf.name_id != @intCast(u32, 0) and lf.name_id != @intCast(u32, 0xFFFFFFFF)) mangleLocalName(emitter.mangler, emitter.interner, lf.name_id) else resolveTempName(emitter, lf.base);
               var result = resolveTempName(emitter, lf.result);
               var lfd_m: []const u8 = "LFD:b"; pal.markerWrite(lfd_m);
               var lfd_bb: [10]u8 = undefined; var lfd_bl = itoa_mod.itoa(lf.base, lfd_bb[0..]); var lfd_bs: usize = @intCast(usize, 9) - @intCast(usize, lfd_bl); pal.markerWrite(lfd_bb[lfd_bs..@intCast(usize, 9)]);
               var lfd_rm: []const u8 = "r"; pal.markerWrite(lfd_rm);
               var lfd_rb: [10]u8 = undefined; var lfd_rl = itoa_mod.itoa(lf.result, lfd_rb[0..]); var lfd_rs: usize = @intCast(usize, 9) - @intCast(usize, lfd_rl); pal.markerWrite(lfd_rb[lfd_rs..@intCast(usize, 9)]);
               var lfd_nl: []const u8 = "\n"; pal.markerWrite(lfd_nl);
                var lf_res_void: u8 = @intCast(u8, 0);
                var lf_rvj: usize = @intCast(usize, 0);
                while (lf_rvj < emitter.current_fn.hoisted_temps.len) : (lf_rvj += @intCast(usize, 1)) {
                    var lf_rvht = emitter.current_fn.hoisted_temps.items[lf_rvj];
                    if (lf_rvht.temp_id == lf.result) {
                        if (lf_rvht.type_id == type_mod.TYPE_VOID) { lf_res_void = @intCast(u8, 1); }
                        break;
                    }
                }
                if (lf_res_void == @intCast(u8, 0)) {
             if (pal.isMarkersEnabled()) {
                var lfcm: []const u8 = "/*==LF:f"; bufferedWriterWrite(&emitter.writer, lfcm);
                var lfcfb: [10]u8 = undefined; var lfcfl = itoa_mod.itoa(lf.field_id, lfcfb[0..]); var lfcfs: usize = @intCast(usize, 9) - @intCast(usize, lfcfl); bufferedWriterWrite(&emitter.writer, lfcfb[lfcfs..@intCast(usize, 9)]);
                var lfcm2: []const u8 = " b"; bufferedWriterWrite(&emitter.writer, lfcm2);
                var lfcbb: [10]u8 = undefined; var lfcbl = itoa_mod.itoa(lf.base, lfcbb[0..]); var lfcbs: usize = @intCast(usize, 9) - @intCast(usize, lfcbl); bufferedWriterWrite(&emitter.writer, lfcbb[lfcbs..@intCast(usize, 9)]);
                var lfcm3: []const u8 = "==*/\n"; bufferedWriterWrite(&emitter.writer, lfcm3);
                }
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
              bufferedWriterWrite(&emitter.writer, result);
              var s: []const u8 = " = ";
              bufferedWriterWrite(&emitter.writer, s);
              bufferedWriterWrite(&emitter.writer, base);
              var field_name_resolved: u8 = @intCast(u8, 0);
              var fi: usize = @intCast(usize, 0);
              while (fi < emitter.current_fn.hoisted_temps.len and field_name_resolved == @intCast(u8, 0)) : (fi += @intCast(usize, 1)) {
                  var ht = emitter.current_fn.hoisted_temps.items[fi];
                  if (ht.temp_id == lf.base) {
                      if (ht.type_id != type_mod.TYPE_UNDEFINED) {
                          var bty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
                          if (bty.kind == type_mod.TypeKind.slice_type) {
                              field_name_resolved = @intCast(u8, 1);
                              if (lf.field_id == type_mod.SLICE_FIELD_PTR) { var pn: []const u8 = ".ptr"; bufferedWriterWrite(&emitter.writer, pn); }
                              else if (lf.field_id == type_mod.SLICE_FIELD_LEN) { var pn: []const u8 = ".len"; bufferedWriterWrite(&emitter.writer, pn); }
                              else { var s2: []const u8 = ".f_"; bufferedWriterWrite(&emitter.writer, s2); var fb: [16]u8 = undefined; var fl = itoa_mod.itoa(lf.field_id, fb[0..]); var fn_idx: u32 = @intCast(u32, @intCast(u32, 15) - fl); var fn_start: usize = @intCast(usize, fn_idx); var fn_end: usize = @intCast(usize, 15); bufferedWriterWrite(&emitter.writer, fb[fn_start..fn_end]); }
                             } else if (bty.kind == type_mod.TypeKind.tagged_union_type) {
                                field_name_resolved = @intCast(u8, 1);
                                if (lf.field_id == type_mod.TU_FIELD_TAG) { var pn: []const u8 = ".tag"; bufferedWriterWrite(&emitter.writer, pn); }
                                else {
                                    var res_ty: u32 = @intCast(u32, 0xFFFFFFFF);
                                    var rtj: usize = @intCast(usize, 0);
                                    var vfound: u8 = @intCast(u8, 0);
                                    while (rtj < emitter.current_fn.hoisted_temps.len) : (rtj += @intCast(usize, 1)) {
                                        var rht = emitter.current_fn.hoisted_temps.items[rtj];
                                        if (rht.temp_id == lf.result) { res_ty = rht.type_id; }
                                    }
                                    var insta_lf_m: []const u8 = "INSTA:tulf"; pal.markerWrite(insta_lf_m);
                                    var insta_lf_b: [10]u8 = undefined; var insta_lf_l = itoa_mod.itoa(res_ty, insta_lf_b[0..]); var insta_lf_s: usize = @intCast(usize, 9) - @intCast(usize, insta_lf_l); pal.markerWrite(insta_lf_b[insta_lf_s..@intCast(usize, 9)]);
                                    var insta_lf_n: []const u8 = "\n"; pal.markerWrite(insta_lf_n);
                                    if (res_ty != @intCast(u32, 0xFFFFFFFF) and res_ty != type_mod.TYPE_VOID) {
                                        var tp = emitter.registry.tu_items[@intCast(usize, bty.payload_idx)];
                                        var vfi: usize = @intCast(usize, 0);
                                        while (vfi < @intCast(usize, tp.fields_count) and vfound == @intCast(u8, 0)) : (vfi += @intCast(usize, 1)) {
                                            var vfe = emitter.registry.fe_items[@intCast(usize, tp.fields_start) + vfi];
                                            if (vfe.type_id == res_ty) {
                                                vfound = @intCast(u8, 1);
                                                var pld: []const u8 = ".payload."; bufferedWriterWrite(&emitter.writer, pld);
                                                var vname = interner_mod.stringInternerGet(emitter.interner, vfe.name_id);
                                                bufferedWriterWrite(&emitter.writer, vname);
                                                var dot_sf: []const u8 = "._"; bufferedWriterWrite(&emitter.writer, dot_sf);
                                                var sfe_idx: u32 = @intCast(u32, 0);
                                                if (hash_mod.u32ToU32MapGet(&emitter.current_fn.temp_variant_sub_field, lf.result)) |svi| { sfe_idx = svi; }
                                                var sfib: [10]u8 = undefined; var sfil = itoa_mod.itoa(sfe_idx, sfib[0..]); var sfis: usize = @intCast(usize, 9) - @intCast(usize, sfil); bufferedWriterWrite(&emitter.writer, sfib[sfis..@intCast(usize, 9)]);
                                            }
                                        }
                                    }
                                    if (vfound == @intCast(u8, 0)) { var s2: []const u8 = ".payload"; bufferedWriterWrite(&emitter.writer, s2); }
                                }
                          } else if (bty.kind == type_mod.TypeKind.ptr_type or bty.kind == type_mod.TypeKind.many_ptr_type) {
                              field_name_resolved = @intCast(u8, 1);
                              var pointee = emitter.registry.ptr_items[@intCast(usize, bty.payload_idx)].base;
                              var pty = emitter.registry.types_items[@intCast(usize, pointee)];
                              if (pty.kind == type_mod.TypeKind.struct_type or pty.kind == type_mod.TypeKind.union_type) {
                                  var pst_fstart: usize = @intCast(usize, 0);
                                  var pst_fcount: usize = @intCast(usize, 0);
                                  if (pty.kind == type_mod.TypeKind.union_type) {
                                      var pup = emitter.registry.un_items[@intCast(usize, pty.payload_idx)];
                                      pst_fstart = @intCast(usize, pup.fields_start);
                                      pst_fcount = @intCast(usize, pup.fields_count);
                                  } else {
                                      var pst = emitter.registry.st_items[@intCast(usize, pty.payload_idx)];
                                      pst_fstart = @intCast(usize, pst.fields_start);
                                      pst_fcount = @intCast(usize, pst.fields_count);
                                  }
                                  if (lf.field_id < @intCast(u32, pst_fcount)) {
                                      var pfe = emitter.registry.fe_items[pst_fstart + @intCast(usize, lf.field_id)];
                                      var pfn = interner_mod.stringInternerGet(emitter.interner, pfe.name_id);
                                      var arrow: []const u8 = "->"; bufferedWriterWrite(&emitter.writer, arrow);
                                      bufferedWriterWrite(&emitter.writer, pfn);
                                  }
                              }
                          } else if (bty.kind == type_mod.TypeKind.struct_type or bty.kind == type_mod.TypeKind.union_type) {
                              field_name_resolved = @intCast(u8, 1);
                              var lf_fstart: usize = @intCast(usize, 0);
                              var lf_fcount: usize = @intCast(usize, 0);
                              if (bty.kind == type_mod.TypeKind.union_type) {
                                  var lf_up = emitter.registry.un_items[@intCast(usize, bty.payload_idx)];
                                  lf_fstart = @intCast(usize, lf_up.fields_start);
                                  lf_fcount = @intCast(usize, lf_up.fields_count);
                              } else {
                                  var lf_st = emitter.registry.st_items[@intCast(usize, bty.payload_idx)];
                                  lf_fstart = @intCast(usize, lf_st.fields_start);
                                  lf_fcount = @intCast(usize, lf_st.fields_count);
                              }
                              if (lf.field_id < @intCast(u32, lf_fcount)) {
                                  var lf_fe = emitter.registry.fe_items[lf_fstart + @intCast(usize, lf.field_id)];
                                  var lf_fname = interner_mod.stringInternerGet(emitter.interner, lf_fe.name_id);
                                  var lf_dot: []const u8 = "."; bufferedWriterWrite(&emitter.writer, lf_dot);
                                  bufferedWriterWrite(&emitter.writer, lf_fname);
                              } else { var s2: []const u8 = ".f_"; bufferedWriterWrite(&emitter.writer, s2); var fb: [16]u8 = undefined; var fl = itoa_mod.itoa(lf.field_id, fb[0..]); var fn_idx: u32 = @intCast(u32, @intCast(u32, 15) - fl); var fn_start: usize = @intCast(usize, fn_idx); var fn_end: usize = @intCast(usize, 15); bufferedWriterWrite(&emitter.writer, fb[fn_start..fn_end]); }
                          }
                      }
                      break;
                  }
              }
              if (field_name_resolved == @intCast(u8, 0)) {
                  var lfu_m: []const u8 = "LFU:f"; pal.markerWrite(lfu_m);
                  var lfu_fb: [10]u8 = undefined; var lfu_fl = itoa_mod.itoa(lf.field_id, lfu_fb[0..]); var lfu_fs: usize = @intCast(usize, 9) - @intCast(usize, lfu_fl); pal.markerWrite(lfu_fb[lfu_fs..@intCast(usize, 9)]);
                  var lfu_nl: []const u8 = "\n"; pal.markerWrite(lfu_nl);
                  if (lf.field_id == type_mod.SLICE_FIELD_PTR) { var pn: []const u8 = ".ptr"; bufferedWriterWrite(&emitter.writer, pn); }
                  else if (lf.field_id == type_mod.SLICE_FIELD_LEN) { var pn: []const u8 = ".len"; bufferedWriterWrite(&emitter.writer, pn); }
                  else {
                      var s2: []const u8 = ".f_";
                      bufferedWriterWrite(&emitter.writer, s2);
                      var fb: [16]u8 = undefined;
                      var fl = itoa_mod.itoa(lf.field_id, fb[0..]);
                      var fn_idx: u32 = @intCast(u32, @intCast(u32, 15) - fl);
                      var fn_start: usize = @intCast(usize, fn_idx);
                      var fn_end: usize = @intCast(usize, 15);
                      bufferedWriterWrite(&emitter.writer, fb[fn_start..fn_end]);
                  }
              }
              var s3: []const u8 = ";\n";
              bufferedWriterWrite(&emitter.writer, s3);
                }
           },
        .store_field => |sf| {
            var base = if (sf.name_id != @intCast(u32, 0) and sf.name_id != @intCast(u32, 0xFFFFFFFF)) mangleLocalName(emitter.mangler, emitter.interner, sf.name_id) else resolveTempName(emitter, sf.base);
              var val = resolveTempName(emitter, sf.value);
             var is_arr2: u8 = @intCast(u8, 0);
             var arr_len2: u32 = @intCast(u32, 0);
             bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
             bufferedWriterWrite(&emitter.writer, base);
             var fn_prefix2: []const u8 = ".f_";
             var found2: u8 = @intCast(u8, 0);
              var suffix_pending: u8 = @intCast(u8, 0);
              var sf_cast: []const u8 = "";
              var tj2: usize = @intCast(usize, 0);
             while (tj2 < emitter.current_fn.hoisted_temps.len) : (tj2 += @intCast(usize, 1)) {
                 var ht = emitter.current_fn.hoisted_temps.items[tj2];
                 if (ht.temp_id == sf.base) {
                     if (ht.type_id != type_mod.TYPE_UNDEFINED) {
                         var bty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
                         if (bty.kind == type_mod.TypeKind.slice_type) {
                              if (sf.field_id == type_mod.SLICE_FIELD_PTR) { var pn: []const u8 = ".ptr"; fn_prefix2 = pn; found2 = @intCast(u8, 1); suffix_pending = @intCast(u8, 1); var sf_el = emitter.registry.slice_items[@intCast(usize, bty.payload_idx)].elem; sf_cast = ptrCTypeNameFromElem(emitter.registry, emitter.mangler, sf_el); }
                              else if (sf.field_id == type_mod.SLICE_FIELD_LEN) { var pn: []const u8 = ".len"; fn_prefix2 = pn; found2 = @intCast(u8, 1); suffix_pending = @intCast(u8, 1); }
                          } else if (bty.kind == type_mod.TypeKind.tagged_union_type) {
                               if (sf.field_id == type_mod.TU_FIELD_TAG) { var pn: []const u8 = ".tag"; fn_prefix2 = pn; found2 = @intCast(u8, 1); suffix_pending = @intCast(u8, 1); }
                               else if (sf.field_id == type_mod.TU_FIELD_PAYLOAD) {
                                   var sf_src_ty: u32 = @intCast(u32, 0xFFFFFFFF);
                                   var sf_stj: usize = @intCast(usize, 0);
                                   while (sf_stj < emitter.current_fn.hoisted_temps.len) : (sf_stj += @intCast(usize, 1)) {
                                       var sf_sht = emitter.current_fn.hoisted_temps.items[sf_stj];
                                       if (sf_sht.temp_id == sf.value) { sf_src_ty = sf_sht.type_id; }
                                   }
                                   var sf_vfound: u8 = @intCast(u8, 0);
                                   if (sf_src_ty != @intCast(u32, 0xFFFFFFFF) and sf_src_ty != type_mod.TYPE_VOID) {
                                       var sf_tp = emitter.registry.tu_items[@intCast(usize, bty.payload_idx)];
                                       var sf_vfi: usize = @intCast(usize, 0);
                                       while (sf_vfi < @intCast(usize, sf_tp.fields_count) and sf_vfound == @intCast(u8, 0)) : (sf_vfi += @intCast(usize, 1)) {
                                           var sf_vfe = emitter.registry.fe_items[@intCast(usize, sf_tp.fields_start) + sf_vfi];
                                           if (sf_vfe.type_id == sf_src_ty) {
                                               sf_vfound = @intCast(u8, 1);
                                               var sf_pld: []const u8 = ".payload."; bufferedWriterWrite(&emitter.writer, sf_pld);
                                               var sf_vname = interner_mod.stringInternerGet(emitter.interner, sf_vfe.name_id);
                                               bufferedWriterWrite(&emitter.writer, sf_vname);
                                               var sf_dot: []const u8 = "._"; bufferedWriterWrite(&emitter.writer, sf_dot);
                                               var sf_sfe_idx: u32 = @intCast(u32, 0);
                                               if (hash_mod.u32ToU32MapGet(&emitter.current_fn.temp_variant_sub_field, sf.value)) |svi| { sf_sfe_idx = svi; }
                                               var sf_sfib: [10]u8 = undefined; var sf_sfil = itoa_mod.itoa(sf_sfe_idx, sf_sfib[0..]); var sf_sfis: usize = @intCast(usize, 9) - @intCast(usize, sf_sfil); bufferedWriterWrite(&emitter.writer, sf_sfib[sf_sfis..@intCast(usize, 9)]);
                                               found2 = @intCast(u8, 1);
                                           }
                                       }
                                   }
                                   if (sf_vfound == @intCast(u8, 0)) { var pn: []const u8 = ".payload"; fn_prefix2 = pn; found2 = @intCast(u8, 1); suffix_pending = @intCast(u8, 1); }
                               }
                           } else if (bty.kind == type_mod.TypeKind.ptr_type or bty.kind == type_mod.TypeKind.many_ptr_type) {
                               var pointee = emitter.registry.ptr_items[@intCast(usize, bty.payload_idx)].base;
                               var pty = emitter.registry.types_items[@intCast(usize, pointee)];
                                if (pty.kind == type_mod.TypeKind.struct_type) {
                                    var arrow_s: []const u8 = "->";
                                    bufferedWriterWrite(&emitter.writer, arrow_s);
                                     var pst = emitter.registry.st_items[@intCast(usize, pty.payload_idx)];
                                     var fe = emitter.registry.fe_items[@intCast(usize, pst.fields_start) + @intCast(usize, sf.field_id)];
                                     var fname: []const u8 = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
                                     bufferedWriterWrite(&emitter.writer, fname);
                                     found2 = @intCast(u8, 1);
                                     if (typeIsPtrKind(emitter.registry, fe.type_id) != @intCast(u8, 0)) { sf_cast = getCTypeName(emitter.registry, emitter.mangler, fe.type_id); }
                                 } else if (pty.kind == type_mod.TypeKind.union_type) {
                                     var arrow_s: []const u8 = "->";
                                     bufferedWriterWrite(&emitter.writer, arrow_s);
                                     var pup = emitter.registry.un_items[@intCast(usize, pty.payload_idx)];
                                     var fe = emitter.registry.fe_items[@intCast(usize, pup.fields_start) + @intCast(usize, sf.field_id)];
                                     var fname: []const u8 = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
                                     bufferedWriterWrite(&emitter.writer, fname);
                                     found2 = @intCast(u8, 1);
                                     if (typeIsPtrKind(emitter.registry, fe.type_id) != @intCast(u8, 0)) { sf_cast = getCTypeName(emitter.registry, emitter.mangler, fe.type_id); }
                                 }
                            } else if (bty.kind == type_mod.TypeKind.struct_type) {
                               var dot_s: []const u8 = ".";
                               bufferedWriterWrite(&emitter.writer, dot_s);
                               var fe: type_mod.FieldEntry = emitter.registry.fe_items[@intCast(usize, emitter.registry.st_items[@intCast(usize, bty.payload_idx)].fields_start) + @intCast(usize, sf.field_id)];
                               var fname: []const u8 = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
                               bufferedWriterWrite(&emitter.writer, fname);
                               found2 = @intCast(u8, 1);
                                if (typeIsPtrKind(emitter.registry, fe.type_id) != @intCast(u8, 0)) { sf_cast = getCTypeName(emitter.registry, emitter.mangler, fe.type_id); }
                                var sf_fety = emitter.registry.types_items[@intCast(usize, fe.type_id)];
                                if (sf_fety.kind == type_mod.TypeKind.array_type) {
                                    var sfap = emitter.registry.array_items[@intCast(usize, sf_fety.payload_idx)];
                                    is_arr2 = @intCast(u8, 1);
                                    arr_len2 = sfap.length;
                                }
                            } else if (bty.kind == type_mod.TypeKind.union_type) {
                                var dot_s: []const u8 = ".";
                                bufferedWriterWrite(&emitter.writer, dot_s);
                                var up = emitter.registry.un_items[@intCast(usize, bty.payload_idx)];
                                var fe: type_mod.FieldEntry = emitter.registry.fe_items[@intCast(usize, up.fields_start) + @intCast(usize, sf.field_id)];
                                var fname: []const u8 = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
                                bufferedWriterWrite(&emitter.writer, fname);
                                found2 = @intCast(u8, 1);
                                if (typeIsPtrKind(emitter.registry, fe.type_id) != @intCast(u8, 0)) { sf_cast = getCTypeName(emitter.registry, emitter.mangler, fe.type_id); }
                            }
                     }
                     break;
                 }
             }
             if (found2 == @intCast(u8, 0)) {
                 var fi_buf: [10]u8 = undefined;
                 var fi_l = itoa_mod.itoa(sf.field_id, fi_buf[0..]);
                 var p0: []const u8 = "internal: store_field unresolved field (field_id ";
                 var p1: []const u8 = ")";
                 var fi_s: usize = @intCast(usize, 9) - @intCast(usize, fi_l);
                 var parts: [3][]const u8 = [3][]const u8{ p0, fi_buf[fi_s..@intCast(usize, 9)], p1 };
                 var msg = diag_mod.diagnosticBuilderMakeMsg(emitter.interner, &parts[0], @intCast(u32, 3));
                 diag_mod.diagnosticCollectorAdd(emitter.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
                 diag_mod.diagnosticCollectorFlushAndExit(emitter.diag, @intCast(u32, 3));
              }
             if (suffix_pending != @intCast(u8, 0)) { bufferedWriterWrite(&emitter.writer, fn_prefix2); }
             if (is_arr2 != @intCast(u8, 0)) {
                var sf_semi: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, sf_semi);
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var sf_lb: []const u8 = "{\n"; bufferedWriterWrite(&emitter.writer, sf_lb);
                var sf_ld: []const u8 = "    unsigned int _j = 0;\n"; bufferedWriterWrite(&emitter.writer, sf_ld);
                var sf_lw: []const u8 = "    while (_j < "; bufferedWriterWrite(&emitter.writer, sf_lw);
                var sf_lab: [20]u8 = undefined; var sf_lal = itoa_mod.itoa(arr_len2, sf_lab[0..]); var sf_las: usize = @intCast(usize, 19) - @intCast(usize, sf_lal); bufferedWriterWrite(&emitter.writer, sf_lab[sf_las..@intCast(usize, 19)]);
                var sf_lw2: []const u8 = ") {\n        "; bufferedWriterWrite(&emitter.writer, sf_lw2);
                bufferedWriterWrite(&emitter.writer, base);
                bufferedWriterWrite(&emitter.writer, fn_prefix2);
                var sf_lv: []const u8 = "[_j] = "; bufferedWriterWrite(&emitter.writer, sf_lv);
                bufferedWriterWrite(&emitter.writer, val);
                var sf_lv2: []const u8 = "[_j];\n        _j++;\n    }\n}\n"; bufferedWriterWrite(&emitter.writer, sf_lv2);
             } else {
                 var sf_cast_name: []const u8 = "";
                 if (sf_cast.len != @intCast(usize, 0)) {
                     var sf_src_ty: u32 = @intCast(u32, 0xFFFFFFFF);
                     var sf_ssg: u8 = @intCast(u8, 0);
                     if (getTempEffType(emitter, sf.value, &sf_src_ty, &sf_ssg) == @intCast(u8, 1) and typeIsIntKind(emitter.registry, sf_src_ty) != @intCast(u8, 0)) {
                         sf_cast_name = sf_cast;
                     }
                 }
                 var s2: []const u8 = " = "; bufferedWriterWrite(&emitter.writer, s2);
                 if (sf_cast_name.len != @intCast(usize, 0)) {
                     var sc0: []const u8 = "("; bufferedWriterWrite(&emitter.writer, sc0);
                     bufferedWriterWrite(&emitter.writer, sf_cast_name);
                     var sc1: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, sc1);
                 }
                 bufferedWriterWrite(&emitter.writer, val);
                 var s3: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, s3);
             }
         },
         .load_index => |li| {
            var result = resolveTempName(emitter, li.result);
            emitBaseIdxAccess(emitter, li.base, li.index, result, @intCast(u8, 0));
        },
        .load => |l| {
            var vflow_ldv: []const u8 = "VFLOW:ldv\n"; pal.markerWrite(vflow_ldv);
            var ptr = resolveTempName(emitter, l.ptr);
            var result = resolveTempName(emitter, l.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = *";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, ptr);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .store => |s| {
            var ptr = resolveTempName(emitter, s.ptr);
            var val = resolveTempName(emitter, s.value);
            var st_cast: []const u8 = "";
            var st_pty: u32 = @intCast(u32, 0xFFFFFFFF);
            var st_psg: u8 = @intCast(u8, 0);
            if (getTempEffType(emitter, s.ptr, &st_pty, &st_psg) == @intCast(u8, 1)) {
                var st_pt = emitter.registry.types_items[@intCast(usize, st_pty)];
                if (st_pt.kind == type_mod.TypeKind.ptr_type or st_pt.kind == type_mod.TypeKind.many_ptr_type) {
                    var st_base = emitter.registry.ptr_items[@intCast(usize, st_pt.payload_idx)].base;
                    if (typeIsPtrKind(emitter.registry, st_base) != @intCast(u8, 0)) {
                        var st_vty: u32 = @intCast(u32, 0xFFFFFFFF);
                        var st_vsg: u8 = @intCast(u8, 0);
                        if (getTempEffType(emitter, s.value, &st_vty, &st_vsg) == @intCast(u8, 1) and typeIsIntKind(emitter.registry, st_vty) != @intCast(u8, 0)) {
                            st_cast = getCTypeName(emitter.registry, emitter.mangler, st_base);
                        }
                    }
                }
            }
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var sp: []const u8 = "*";
            bufferedWriterWrite(&emitter.writer, sp);
            bufferedWriterWrite(&emitter.writer, ptr);
            var sp2: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, sp2);
            if (st_cast.len != @intCast(usize, 0)) {
                var st_c0: []const u8 = "(";
                bufferedWriterWrite(&emitter.writer, st_c0);
                bufferedWriterWrite(&emitter.writer, st_cast);
                var st_c1: []const u8 = ")";
                bufferedWriterWrite(&emitter.writer, st_c1);
            }
            bufferedWriterWrite(&emitter.writer, val);
            var sp3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, sp3);
        },
        .addr_of => |a| {
            var op = resolveTempName(emitter, a.operand);
            var result = resolveTempName(emitter, a.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = &";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, op);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .addr_of_field => |af| {
            var base = resolveTempName(emitter, af.base);
            var result = resolveTempName(emitter, af.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = &";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, base);
            var af_found: u8 = @intCast(u8, 0);
            var af_tj: usize = @intCast(usize, 0);
            while (af_tj < emitter.current_fn.hoisted_temps.len) : (af_tj += @intCast(usize, 1)) {
                var ht = emitter.current_fn.hoisted_temps.items[af_tj];
                if (ht.temp_id == af.base and ht.type_id != type_mod.TYPE_UNDEFINED) {
                    var bty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
                    var pointee: u32 = ht.type_id;
                    if (bty.kind == type_mod.TypeKind.ptr_type or bty.kind == type_mod.TypeKind.many_ptr_type) {
                        pointee = emitter.registry.ptr_items[@intCast(usize, bty.payload_idx)].base;
                    }
                    var pty = emitter.registry.types_items[@intCast(usize, pointee)];
                    if (pty.kind == type_mod.TypeKind.struct_type) {
                        var arrow_s: []const u8 = "->";
                        bufferedWriterWrite(&emitter.writer, arrow_s);
                        var pst = emitter.registry.st_items[@intCast(usize, pty.payload_idx)];
                        var fe = emitter.registry.fe_items[@intCast(usize, pst.fields_start) + @intCast(usize, af.field_id)];
                        var fname: []const u8 = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
                        bufferedWriterWrite(&emitter.writer, fname);
                        af_found = @intCast(u8, 1);
                    } else if (pty.kind == type_mod.TypeKind.union_type) {
                        var arrow_s: []const u8 = "->";
                        bufferedWriterWrite(&emitter.writer, arrow_s);
                        var pup = emitter.registry.un_items[@intCast(usize, pty.payload_idx)];
                        var fe = emitter.registry.fe_items[@intCast(usize, pup.fields_start) + @intCast(usize, af.field_id)];
                        var fname: []const u8 = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
                        bufferedWriterWrite(&emitter.writer, fname);
                        af_found = @intCast(u8, 1);
                    }
                    break;
                }
            }
            if (af_found == @intCast(u8, 0)) {
                var af_m: []const u8 = "internal: addr_of_field unresolved base field (field_id ";
                var af_b: [10]u8 = undefined;
                var af_l = itoa_mod.itoa(af.field_id, af_b[0..]);
                var af_s: usize = @intCast(usize, 9) - @intCast(usize, af_l);
                var af_e: []const u8 = ")";
                var parts: [3][]const u8 = [3][]const u8{ af_m, af_b[af_s..@intCast(usize, 9)], af_e };
                var msg = diag_mod.diagnosticBuilderMakeMsg(emitter.interner, &parts[0], @intCast(u32, 3));
                diag_mod.diagnosticCollectorAdd(emitter.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
                diag_mod.diagnosticCollectorFlushAndExit(emitter.diag, @intCast(u32, 3));
            }
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
         .binary => |b| {
              var bin_m: []const u8 = "BIN:d"; pal.markerWrite(bin_m);
              var bin_db: [10]u8 = undefined; var bin_dl = itoa_mod.itoa(b.result, bin_db[0..]); var bin_ds: usize = @intCast(usize, 9) - @intCast(usize, bin_dl); pal.markerWrite(bin_db[bin_ds..@intCast(usize, 9)]);
              var bin_lm: []const u8 = "l"; pal.markerWrite(bin_lm);
              var bin_lb: [10]u8 = undefined; var bin_ll = itoa_mod.itoa(b.lhs, bin_lb[0..]); var bin_ls: usize = @intCast(usize, 9) - @intCast(usize, bin_ll); pal.markerWrite(bin_lb[bin_ls..@intCast(usize, 9)]);
              var bin_rm: []const u8 = "r"; pal.markerWrite(bin_rm);
              var bin_rb: [10]u8 = undefined; var bin_rl = itoa_mod.itoa(b.rhs, bin_rb[0..]); var bin_rs: usize = @intCast(usize, 9) - @intCast(usize, bin_rl); pal.markerWrite(bin_rb[bin_rs..@intCast(usize, 9)]);
              var bin_nl: []const u8 = "\n"; pal.markerWrite(bin_nl);
             var result = resolveTempName(emitter, b.result);
            var lhs = resolveTempName(emitter, b.lhs);
            if (b.rhs < @intCast(u32, 1000) and b.rhs != @intCast(u32, 0)) {
                var instc_br_m: []const u8 = "INSTC:brhs"; pal.markerWrite(instc_br_m);
                var instc_br_b: [10]u8 = undefined; var instc_br_l = itoa_mod.itoa(b.rhs, instc_br_b[0..]); var instc_br_s: usize = @intCast(usize, 9) - @intCast(usize, instc_br_l); pal.markerWrite(instc_br_b[instc_br_s..@intCast(usize, 9)]);
                var instc_br_n: []const u8 = "\n"; pal.markerWrite(instc_br_n);
            }
            var rhs = resolveTempName(emitter, b.rhs);
            if (b.op >= @intCast(u8, 16)) {
                var wty: u32 = @intCast(u32, 0);
                var wsg: u8 = @intCast(u8, 0);
                getTempTypeInfo(emitter, b.result, b.lhs, b.rhs, &wty, &wsg);
                if (b.op >= @intCast(u8, 19)) {
                    var sfty = emitter.registry.types_items[@intCast(usize, wty)];
                    if (sfty.kind == TypeKind.void_type or sfty.kind == TypeKind.integer_literal_type) {
                        getTempTypeInfo(emitter, b.lhs, b.rhs, @intCast(u32, 0), &wty, &wsg);
                    }
                    emitSatBinary(emitter, b.op, lhs, rhs, result, wty, wsg);
                } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, result);
                var eqs: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, eqs);
                var sp: []const u8 = " ";
                if (wsg != @intCast(u8, 0)) {
                    var o1: []const u8 = "("; bufferedWriterWrite(&emitter.writer, o1);
                    var ct = getCTypeName(emitter.registry, emitter.mangler, wty);
                    bufferedWriterWrite(&emitter.writer, ct);
                    var o2: []const u8 = ")(("; bufferedWriterWrite(&emitter.writer, o2);
                    var ut = getUnsignedCTypeName(emitter.registry, emitter.mangler, wty);
                    bufferedWriterWrite(&emitter.writer, ut);
                    var o3: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, o3);
                    bufferedWriterWrite(&emitter.writer, lhs);
                    bufferedWriterWrite(&emitter.writer, sp);
                    var wop = getBinOpStr(b.op);
                    bufferedWriterWrite(&emitter.writer, wop);
                    bufferedWriterWrite(&emitter.writer, sp);
                    var o3c: []const u8 = "("; bufferedWriterWrite(&emitter.writer, o3c);
                    bufferedWriterWrite(&emitter.writer, ut);
                    var o3b: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, o3b);
                    bufferedWriterWrite(&emitter.writer, rhs);
                    var o4: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, o4);
                } else {
                    bufferedWriterWrite(&emitter.writer, lhs);
                    bufferedWriterWrite(&emitter.writer, sp);
                    var wop = getBinOpStr(b.op);
                    bufferedWriterWrite(&emitter.writer, wop);
                    bufferedWriterWrite(&emitter.writer, sp);
                    bufferedWriterWrite(&emitter.writer, rhs);
                }
                var s2: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, s2);
                }
            } else {
            var lhs_is_tag: u8 = @intCast(u8, 0);
            var rhs_is_tag: u8 = @intCast(u8, 0);
            if (b.op == @intCast(u8, 10) or b.op == @intCast(u8, 11)) {
                var ht_i: usize = @intCast(usize, 0);
                while (ht_i < emitter.current_fn.hoisted_temps.len) : (ht_i += @intCast(usize, 1)) {
                    var ht = emitter.current_fn.hoisted_temps.items[ht_i];
                    if (ht.temp_id == b.lhs and ht.type_id != type_mod.TYPE_UNDEFINED) {
                        var lty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
                        if (lty.kind == type_mod.TypeKind.tagged_union_type) { lhs_is_tag = @intCast(u8, 1); }
                    }
                    if (ht.temp_id == b.rhs and ht.type_id != type_mod.TYPE_UNDEFINED) {
                        var rty = emitter.registry.types_items[@intCast(usize, ht.type_id)];
                        if (rty.kind == type_mod.TypeKind.tagged_union_type) { rhs_is_tag = @intCast(u8, 1); }
                    }
                }
            }
            var op_str = getBinOpStr(b.op);
            var is_shift_op: u8 = @intCast(u8, 0);
            if (b.op == @intCast(u8, 8) or b.op == @intCast(u8, 9)) { is_shift_op = @intCast(u8, 1); }
            var lhs_paren: u8 = @intCast(u8, 0);
            if (is_shift_op != @intCast(u8, 0) and !isAtomicCOperand(lhs)) { lhs_paren = @intCast(u8, 1); }
            var rhs_paren: u8 = @intCast(u8, 0);
            if (is_shift_op != @intCast(u8, 0) and !isAtomicCOperand(rhs)) { rhs_paren = @intCast(u8, 1); }
            var lhs_cast: []const u8 = "";
            var rhs_cast: []const u8 = "";
            if (b.op >= @intCast(u8, 10)) {
                var l_sgn: i8 = @intCast(i8, -1);
                var r_sgn: i8 = @intCast(i8, -1);
                var l_tyid: u32 = @intCast(u32, 0);
                var r_tyid: u32 = @intCast(u32, 0);
                var l_sg: u8 = @intCast(u8, 0);
                var r_sg: u8 = @intCast(u8, 0);
                if (getTempEffType(emitter, b.lhs, &l_tyid, &l_sg) == @intCast(u8, 1)) {
                    l_sgn = classifyIntSignedness(emitter.registry, l_tyid);
                }
                if (getTempEffType(emitter, b.rhs, &r_tyid, &r_sg) == @intCast(u8, 1)) {
                    r_sgn = classifyIntSignedness(emitter.registry, r_tyid);
                }
                if (l_sgn == @intCast(i8, 1) and r_sgn == @intCast(i8, 0)) {
                    lhs_cast = getCTypeName(emitter.registry, emitter.mangler, r_tyid);
                } else if (l_sgn == @intCast(i8, 0) and r_sgn == @intCast(i8, 1)) {
                    rhs_cast = getCTypeName(emitter.registry, emitter.mangler, l_tyid);
                }
            }
            var bnr_m: []const u8 = "BNR:r"; pal.markerWrite(bnr_m);
            var bnr_rb: [10]u8 = undefined; var bnr_rl = itoa_mod.itoa(@intCast(u32, result.len), bnr_rb[0..]); var bnr_rs: usize = @intCast(usize, 9) - @intCast(usize, bnr_rl); pal.markerWrite(bnr_rb[bnr_rs..@intCast(usize, 9)]);
            var bnr_lm: []const u8 = "l"; pal.markerWrite(bnr_lm);
            var bnr_lb: [10]u8 = undefined; var bnr_ll = itoa_mod.itoa(@intCast(u32, lhs.len), bnr_lb[0..]); var bnr_ls: usize = @intCast(usize, 9) - @intCast(usize, bnr_ll); pal.markerWrite(bnr_lb[bnr_ls..@intCast(usize, 9)]);
            var bnr_rm: []const u8 = "R"; pal.markerWrite(bnr_rm);
            var bnr_rrb: [10]u8 = undefined; var bnr_rrl = itoa_mod.itoa(@intCast(u32, rhs.len), bnr_rrb[0..]); var bnr_rrs: usize = @intCast(usize, 9) - @intCast(usize, bnr_rrl); pal.markerWrite(bnr_rrb[bnr_rrs..@intCast(usize, 9)]);
            var bnr_nl: []const u8 = "\n"; pal.markerWrite(bnr_nl);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            if (lhs_cast.len != @intCast(usize, 0)) {
                var lc0: []const u8 = "("; bufferedWriterWrite(&emitter.writer, lc0);
                bufferedWriterWrite(&emitter.writer, lhs_cast);
                var lc1: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, lc1);
            }
            if (lhs_paren != @intCast(u8, 0)) {
                var lp: []const u8 = "(";
                bufferedWriterWrite(&emitter.writer, lp);
            }
            bufferedWriterWrite(&emitter.writer, lhs);
            if (lhs_is_tag != @intCast(u8, 0)) {
                var tag_s: []const u8 = ".tag";
                bufferedWriterWrite(&emitter.writer, tag_s);
            }
            if (lhs_paren != @intCast(u8, 0)) {
                var rp: []const u8 = ")";
                bufferedWriterWrite(&emitter.writer, rp);
            }
            var sp: []const u8 = " ";
            bufferedWriterWrite(&emitter.writer, sp);
            bufferedWriterWrite(&emitter.writer, op_str);
            bufferedWriterWrite(&emitter.writer, sp);
            if (rhs_cast.len != @intCast(usize, 0)) {
                var rc0: []const u8 = "("; bufferedWriterWrite(&emitter.writer, rc0);
                bufferedWriterWrite(&emitter.writer, rhs_cast);
                var rc1: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, rc1);
            }
            if (rhs_paren != @intCast(u8, 0)) {
                var rp2: []const u8 = "(";
                bufferedWriterWrite(&emitter.writer, rp2);
            }
            bufferedWriterWrite(&emitter.writer, rhs);
            if (rhs_is_tag != @intCast(u8, 0)) {
                var tag_s: []const u8 = ".tag";
                bufferedWriterWrite(&emitter.writer, tag_s);
            }
            if (rhs_paren != @intCast(u8, 0)) {
                var rp3: []const u8 = ")";
                bufferedWriterWrite(&emitter.writer, rp3);
            }
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
            }
        },
        .unary => |u| {
            var result = resolveTempName(emitter, u.result);
            var opd = resolveTempName(emitter, u.operand);
            if (u.op == @intCast(u8, 3)) {
                var wty: u32 = @intCast(u32, 0);
                var wsg: u8 = @intCast(u8, 0);
                getTempTypeInfo(emitter, u.result, u.operand, @intCast(u32, 0), &wty, &wsg);
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, result);
                var s: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s);
                if (wsg != @intCast(u8, 0)) {
                    var o1: []const u8 = "("; bufferedWriterWrite(&emitter.writer, o1);
                    var ct = getCTypeName(emitter.registry, emitter.mangler, wty);
                    bufferedWriterWrite(&emitter.writer, ct);
                    var o2: []const u8 = ")(0u - ("; bufferedWriterWrite(&emitter.writer, o2);
                    var ut = getUnsignedCTypeName(emitter.registry, emitter.mangler, wty);
                    bufferedWriterWrite(&emitter.writer, ut);
                    var o3: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, o3);
                    bufferedWriterWrite(&emitter.writer, opd);
                    var o4: []const u8 = ")"; bufferedWriterWrite(&emitter.writer, o4);
                } else {
                    var op_str = getUnOpStr(u.op);
                    bufferedWriterWrite(&emitter.writer, op_str);
                    bufferedWriterWrite(&emitter.writer, opd);
                }
                var s2: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, s2);
            } else {
            var op_str = getUnOpStr(u.op);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, op_str);
            bufferedWriterWrite(&emitter.writer, opd);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
            }
        },
        .int_const => |ic| {
            var result = resolveTempName(emitter, ic.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var is_tagged_union: u8 = @intCast(u8, 0);
            var temp_type_id: u32 = @intCast(u32, 0);
            temp_type_id = type_mod.TYPE_USIZE;
            var is_signed: u8 = @intCast(u8, 0);
            var width_bits: u32 = @intCast(u32, 32);
            var ht_found_tid: u32 = @intCast(u32, 0);
            ht_found_tid = type_mod.TYPE_USIZE;
            var tu_fi: usize = @intCast(usize, 0);
            while (tu_fi < emitter.current_fn.hoisted_temps.len) : (tu_fi += @intCast(usize, 1)) {
                var ht = emitter.current_fn.hoisted_temps.items[tu_fi];
                if (ht.temp_id == ic.result and ht.type_id != type_mod.TYPE_UNDEFINED) {
                    ht_found_tid = ht.type_id;
                    break;
                }
            }
            temp_type_id = intConstTypeForValue(emitter.registry, ic.value, ht_found_tid);
            var ict_bty = emitter.registry.types_items[@intCast(usize, temp_type_id)];
            if (ict_bty.kind == type_mod.TypeKind.i8_type or ict_bty.kind == type_mod.TypeKind.i16_type or ict_bty.kind == type_mod.TypeKind.i32_type or ict_bty.kind == type_mod.TypeKind.i64_type or ict_bty.kind == type_mod.TypeKind.isize_type) {
                is_signed = @intCast(u8, 1);
            }
            width_bits = @intCast(u32, ict_bty.size * @intCast(u32, 8));
            if (ict_bty.kind == type_mod.TypeKind.tagged_union_type) {
                is_tagged_union = @intCast(u8, 1);
            }
            if (is_tagged_union != @intCast(u8, 0)) {
                var tag_dot: []const u8 = ".tag = ";
                bufferedWriterWrite(&emitter.writer, tag_dot);
            } else {
                var s: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s);
            }
            var ib: [32]u8 = undefined;
            var neg_magnitude: u8 = @intCast(u8, 0);
            if (is_signed != @intCast(u8, 0)) {
                var masked = ic.value;
                if (width_bits < @intCast(u32, 64)) {
                    var wbm = (@intCast(u64, 1) << @intCast(u64, width_bits)) - @intCast(u64, 1);
                    masked = masked & wbm;
                }
                var sb = @intCast(u8, width_bits - @intCast(u32, 1));
                var sign_bit = @intCast(u64, 1) << @intCast(u64, sb);
                if ((masked & sign_bit) != @intCast(u64, 0)) {
                    var magnitude: u64 = undefined;
                    if (width_bits < @intCast(u32, 64)) {
                        var wbm2 = @intCast(u64, 1) << @intCast(u64, width_bits);
                        magnitude = wbm2 - masked;
                    } else {
                        magnitude = @intCast(u64, 0) - masked;
                    }
                    neg_magnitude = @intCast(u8, 1);
                    var cname = getCTypeName(emitter.registry, emitter.mangler, temp_type_id);
                    var lp: []const u8 = "(";
                    bufferedWriterWrite(&emitter.writer, lp);
                    bufferedWriterWrite(&emitter.writer, cname);
                    var rp: []const u8 = ")-";
                    bufferedWriterWrite(&emitter.writer, rp);
                    var il = itoa_mod.itoa64(magnitude, ib[0..]);
                    var is_idx = @intCast(u32, @intCast(u32, 31) - il);
                    var is_start: usize = @intCast(usize, is_idx);
                    var is_end: usize = @intCast(usize, 31);
                    bufferedWriterWrite(&emitter.writer, ib[is_start..is_end]);
                    var nsuf = intLitSuffixNeg(magnitude);
                    bufferedWriterWrite(&emitter.writer, nsuf);
                }
            }
            if (neg_magnitude == @intCast(u8, 0)) {
                var il = itoa_mod.itoa64(ic.value, ib[0..]);
                var is_idx = @intCast(u32, @intCast(u32, 31) - il);
                var is_start: usize = @intCast(usize, is_idx);
                var is_end: usize = @intCast(usize, 31);
                bufferedWriterWrite(&emitter.writer, ib[is_start..is_end]);
                var usuf = intLitSuffixUns(ic.value);
                bufferedWriterWrite(&emitter.writer, usuf);
            }
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .enum_const => |ec| {
            var result = resolveTempName(emitter, ec.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            var ety = emitter.registry.types_items[@intCast(usize, ec.type_id)];
            var e_mid = nameManglerMangle(emitter.mangler, ety.name_id, @intCast(u8, 2), ety.module_id);
            var e_name = interner_mod.stringInternerGet(emitter.interner, e_mid);
            bufferedWriterWrite(&emitter.writer, e_name);
            var us: []const u8 = "_";
            bufferedWriterWrite(&emitter.writer, us);
            var mem_name = interner_mod.stringInternerGet(emitter.interner, ec.member_name_id);
            bufferedWriterWrite(&emitter.writer, mem_name);
            var sc: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, sc);
        },
        .float_const => |fc| {
            var result = resolveTempName(emitter, fc.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            var dx2_buf: [64]u8 = undefined;
            var dx2 = format_mod.formatF64(fc.value, dx2_buf[0..], 64);
            var dx2s: []const u8 = "D2:"; pal.measureMarkerWrite(dx2s);
            pal.measureMarkerWrite(dx2);
            var dx2n: []const u8 = "\n"; pal.measureMarkerWrite(dx2n);
            var buf: [64]u8 = undefined;
            var fb = format_mod.formatF64(fc.value, buf[0..], 64);
            bufferedWriterWrite(&emitter.writer, fb);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .string_const => |sc| {
            var result = resolveTempName(emitter, sc.result);
            var str = interner_mod.stringInternerGet(emitter.interner, sc.string_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = \"";
            bufferedWriterWrite(&emitter.writer, s);
            var si: usize = @intCast(usize, 0);
            while (si < str.len) : (si += @intCast(usize, 1)) {
                var b = str[si];
                if (b == @intCast(u8, '\n')) {
                    var esc: []const u8 = "\\n";
                    bufferedWriterWrite(&emitter.writer, esc);
                } else if (b == @intCast(u8, '\t')) {
                    var esc: []const u8 = "\\t";
                    bufferedWriterWrite(&emitter.writer, esc);
                } else if (b == @intCast(u8, '\r')) {
                    var esc: []const u8 = "\\r";
                    bufferedWriterWrite(&emitter.writer, esc);
                } else if (b == @intCast(u8, '"') or b == @intCast(u8, '\\')) {
                    var bs: []const u8 = "\\";
                    bufferedWriterWrite(&emitter.writer, bs);
                    var ch: [1]u8 = undefined;
                    ch[0] = b;
                    bufferedWriterWrite(&emitter.writer, ch[0..1]);
                } else {
                    var ch: [1]u8 = undefined;
                    ch[0] = b;
                    bufferedWriterWrite(&emitter.writer, ch[0..1]);
                }
            }
            var s2: []const u8 = "\";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .null_const => |nc| {
            var result = resolveTempName(emitter, nc.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var nct = getTempTypeByIndex(emitter, nc.result);
            if (nct != @intCast(u32, 0xFFFFFFFF) and emitter.registry.types_items[@intCast(usize, nct)].kind == type_mod.TypeKind.optional_type) {
                bufferedWriterWrite(&emitter.writer, result);
                var sno: []const u8 = ".has_value = 0;\n";
                bufferedWriterWrite(&emitter.writer, sno);
            } else if (nct != @intCast(u32, 0xFFFFFFFF) and emitter.registry.types_items[@intCast(usize, nct)].kind == type_mod.TypeKind.null_type) {
                bufferedWriterWrite(&emitter.writer, result);
                var snz: []const u8 = " = 0;\n";
                bufferedWriterWrite(&emitter.writer, snz);
            } else {
                bufferedWriterWrite(&emitter.writer, result);
                var s: []const u8 = " = NULL;\n";
                bufferedWriterWrite(&emitter.writer, s);
            }
        },
        .set_optional_null => |sn| {
            var sres = resolveTempName(emitter, sn.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, sres);
            var sohv: []const u8 = ".has_value = 0;\n";
            bufferedWriterWrite(&emitter.writer, sohv);
        },
        .bool_const => |bc| {
            var result = resolveTempName(emitter, bc.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            if (bc.value != @intCast(u8, 0)) {
                var s: []const u8 = " = 1;\n";
                bufferedWriterWrite(&emitter.writer, s);
            } else {
                var s: []const u8 = " = 0;\n";
                bufferedWriterWrite(&emitter.writer, s);
            }
        },
        .undefined_const => |uc| {
            var result = resolveTempName(emitter, uc.result);
            var uct_m: []const u8 = "UCT:r"; pal.markerWrite(uct_m);
            var uct_rb: [10]u8 = undefined; var uct_rl = itoa_mod.itoa(uc.result, uct_rb[0..]); var uct_rs: usize = @intCast(usize, 9) - @intCast(usize, uct_rl); pal.markerWrite(uct_rb[uct_rs..@intCast(usize, 9)]);
            var uct_tm: []const u8 = "t"; pal.markerWrite(uct_tm);
            var uct_tb: [10]u8 = undefined; var uct_tl = itoa_mod.itoa(uc.type_id, uct_tb[0..]); var uct_ts: usize = @intCast(usize, 9) - @intCast(usize, uct_tl); pal.markerWrite(uct_tb[uct_ts..@intCast(usize, 9)]);
            var uct_nl: []const u8 = "\n"; pal.markerWrite(uct_nl);
            var uct_ty = emitter.registry.types_items[@intCast(usize, uc.type_id)];
             if (uct_ty.kind == type_mod.TypeKind.array_type) {
                 var uap = emitter.registry.array_items[@intCast(usize, uct_ty.payload_idx)];
                 var loop_begin: []const u8 = "{\n";
                 bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                 bufferedWriterWrite(&emitter.writer, loop_begin);
                 var uap_zi = arrLoopDeclSigned(uap.length);
                 bufferedWriterWrite(&emitter.writer, uap_zi);
                 var loop_cond: []const u8 = "    while (_i < ";
                 bufferedWriterWrite(&emitter.writer, loop_cond);
                 var alb: [20]u8 = undefined; var all = itoa_mod.itoa(uap.length, alb[0..]); var als: usize = @intCast(usize, 19) - @intCast(usize, all); bufferedWriterWrite(&emitter.writer, alb[als..@intCast(usize, 19)]);
                 var loop_body: []const u8 = ") {\n        ";
                 bufferedWriterWrite(&emitter.writer, loop_body);
                 var elem_ty = emitter.registry.types_items[@intCast(usize, uap.elem)];
                 if (elem_ty.kind == type_mod.TypeKind.tagged_union_type) {
                     bufferedWriterWrite(&emitter.writer, result);
                     var lb_tu: []const u8 = "[_i].tag = 0;\n        _i++;\n    }\n}\n";
                     bufferedWriterWrite(&emitter.writer, lb_tu);
               } else if (elem_ty.kind == type_mod.TypeKind.struct_type) {
                      var ucs_m: []const u8 = "UCS:e"; pal.markerWrite(ucs_m);
                      var ucs_eb: [10]u8 = undefined; var ucs_el = itoa_mod.itoa(uap.elem, ucs_eb[0..]); var ucs_es: usize = @intCast(usize, 9) - @intCast(usize, ucs_el); pal.markerWrite(ucs_eb[ucs_es..@intCast(usize, 9)]);
                      var ucs_nl: []const u8 = "\n"; pal.markerWrite(ucs_nl);
                      var final_ender: []const u8 = "_i++;\n    }\n}\n";
                      var st = emitter.registry.st_items[@intCast(usize, elem_ty.payload_idx)];
                      var sfi: usize = @intCast(usize, 0);
                      while (sfi < @intCast(usize, st.fields_count)) : (sfi += @intCast(usize, 1)) {
                          var sfe = emitter.registry.fe_items[@intCast(usize, st.fields_start) + sfi];
                          var sfety = emitter.registry.types_items[@intCast(usize, sfe.type_id)];
                          if (sfety.kind == type_mod.TypeKind.array_type) {
                               var sfap = emitter.registry.array_items[@intCast(usize, sfety.payload_idx)];
                               var slpb = arrLoopDeclSignedK(sfap.length);
                               bufferedWriterWrite(&emitter.writer, slpb);
                              var slpw: []const u8 = "    while (_k < ";
                              bufferedWriterWrite(&emitter.writer, slpw);
                              var slpab: [20]u8 = undefined; var slpal = itoa_mod.itoa(sfap.length, slpab[0..]); var slpas: usize = @intCast(usize, 19) - @intCast(usize, slpal); bufferedWriterWrite(&emitter.writer, slpab[slpas..@intCast(usize, 19)]);
                              var slpb2: []const u8 = ") {\n        ";
                              bufferedWriterWrite(&emitter.writer, slpb2);
                              bufferedWriterWrite(&emitter.writer, result);
                              var slpd: []const u8 = "[_i].";
                              bufferedWriterWrite(&emitter.writer, slpd);
                              var slpfn: []const u8 = interner_mod.stringInternerGet(emitter.interner, sfe.name_id);
                              bufferedWriterWrite(&emitter.writer, slpfn);
                              var slpb3: []const u8 = "[_k] = 0;\n        _k++;\n    }\n";
                              bufferedWriterWrite(&emitter.writer, slpb3);
                          } else {
                              bufferedWriterWrite(&emitter.writer, result);
                              var sld: []const u8 = "[_i].";
                              bufferedWriterWrite(&emitter.writer, sld);
                              var slfn: []const u8 = interner_mod.stringInternerGet(emitter.interner, sfe.name_id);
                              bufferedWriterWrite(&emitter.writer, slfn);
                              var sle: []const u8 = " = 0;\n        ";
                              bufferedWriterWrite(&emitter.writer, sle);
                          }
                      }
                      bufferedWriterWrite(&emitter.writer, final_ender);
                  } else {
                     bufferedWriterWrite(&emitter.writer, result);
                     var lb: []const u8 = "[_i] = 0;\n        _i++;\n    }\n}\n";
                     bufferedWriterWrite(&emitter.writer, lb);
                 }
            } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, result);
                var s: []const u8 = " = 0;\n";
                bufferedWriterWrite(&emitter.writer, s);
            }
        },
         .call => |c| {
            var result = resolveTempName(emitter, c.result);
            var callee = resolveTempName(emitter, c.callee);
            var is_void: u8 = @intCast(u8, 0);
            var hti: usize = @intCast(usize, 0);
            while (hti < emitter.current_fn.hoisted_temps.len) : (hti += @intCast(usize, 1)) {
                var ht = emitter.current_fn.hoisted_temps.items[hti];
                if (ht.temp_id == c.callee) {
                    var ct = ht.type_id;
                    var cty = emitter.registry.types_items[@intCast(usize, ct)];
                    if (cty.kind == type_mod.TypeKind.ptr_type or cty.kind == type_mod.TypeKind.many_ptr_type) {
                        ct = emitter.registry.ptr_items[@intCast(usize, cty.payload_idx)].base;
                        cty = emitter.registry.types_items[@intCast(usize, ct)];
                    }
                    if (cty.kind == type_mod.TypeKind.fn_type) {
                        var fp = emitter.registry.fn_items[@intCast(usize, cty.payload_idx)];
                        if (fp.return_type == type_mod.TYPE_VOID) { is_void = @intCast(u8, 1); }
                    }
                    break;
                }
            }
            if (c.args_count > @intCast(u32, 0)) {
                var ad_m: []const u8 = "AD:a"; pal.markerWrite(ad_m);
                var ad_ab: [20]u8 = undefined; var ad_al = itoa_mod.itoa(c.args_count, ad_ab[0..]); var ad_as: usize = @intCast(usize, 19) - @intCast(usize, ad_al); pal.markerWrite(ad_ab[ad_as..@intCast(usize, 19)]);
            }
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var cd_dead: u8 = @intCast(u8, 0);
            if (is_void == @intCast(u8, 0)) {
                if (dceTempIsDead(emitter, c.result)) { cd_dead = @intCast(u8, 1); }
            }
            if (cd_dead == @intCast(u8, 1)) {
                var vp: []const u8 = "(void)";
                bufferedWriterWrite(&emitter.writer, vp);
            } else if (is_void == @intCast(u8, 0)) {
                bufferedWriterWrite(&emitter.writer, result);
                var s: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s);
            }
            bufferedWriterWrite(&emitter.writer, callee);
            var sp: []const u8 = "(";
            bufferedWriterWrite(&emitter.writer, sp);
            var ai: u32 = @intCast(u32, 0);
            while (ai < c.args_count) : (ai += @intCast(u32, 1)) {
                if (ai > @intCast(u32, 0)) {
                    var sc: []const u8 = ", ";
                    bufferedWriterWrite(&emitter.writer, sc);
                }
                var arg = resolveTempName(emitter, c.args_start + ai);
                bufferedWriterWrite(&emitter.writer, arg);
            }
            var s2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
         .call_direct => |c_slot| {
            var c = lir_mod.lirSideGetCallDirect(emitter.current_fn, c_slot);
            if (pal.isMarkersEnabled()) {
            var mkc: []const u8 = "/*==MARKER_CALL n=";
            bufferedWriterWrite(&emitter.writer, mkc);
            var mknb: [10]u8 = undefined; var mknl = itoa_mod.itoa(c.name_id, mknb[0..]); var mkns: usize = @intCast(usize, 9) - @intCast(usize, mknl);
            bufferedWriterWrite(&emitter.writer, mknb[mkns..@intCast(usize, 9)]);
            var mkmk: []const u8 = " m=";
            bufferedWriterWrite(&emitter.writer, mkmk);
            var mkmmb: [10]u8 = undefined; var mkmml = itoa_mod.itoa(c.module_id, mkmmb[0..]); var mkmms: usize = @intCast(usize, 9) - @intCast(usize, mkmml);
            bufferedWriterWrite(&emitter.writer, mkmmb[mkmms..@intCast(usize, 9)]);
            var mkend: []const u8 = "==*/\n";
            bufferedWriterWrite(&emitter.writer, mkend);
            }
             var mangled_id = nameManglerMangle(emitter.mangler, c.name_id, @intCast(u8, 0), c.module_id);
             var fn_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
              if (c.is_extern == @intCast(u8, 1)) { var orig_c = interner_mod.stringInternerGet(emitter.interner, c.name_id); fn_name = orig_c; }
              if (dceTempIsDead(emitter, c.result)) {
                 bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                 var vp: []const u8 = "(void)";
                 bufferedWriterWrite(&emitter.writer, vp);
                 bufferedWriterWrite(&emitter.writer, fn_name);
                 var sp2: []const u8 = "(";
                 bufferedWriterWrite(&emitter.writer, sp2);
                 var ai2: u32 = @intCast(u32, 0);
                 while (ai2 < c.args_count) : (ai2 += @intCast(u32, 1)) {
                     if (ai2 > @intCast(u32, 0)) { var sc2: []const u8 = ", "; bufferedWriterWrite(&emitter.writer, sc2); }
                     var arg2 = resolveTempName(emitter, c.args_start + ai2);
                     bufferedWriterWrite(&emitter.writer, arg2);
                 }
                 var s2c: []const u8 = ");\n";
                 bufferedWriterWrite(&emitter.writer, s2c);
                 return;
             }
             var dc2_nm: []const u8 = "DC2:N"; pal.markerWriteInt(dc2_nm, c.name_id);
             bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
              var dcr_m: []const u8 = "DC2:r"; pal.markerWriteInt(dcr_m, c.result);
               var vfcd_m: []const u8 = "VFLOW:cdv\n"; pal.markerWrite(vfcd_m);
               var need_wrap: u8 = @intCast(u8, 0);
               var wrap_kind: u8 = @intCast(u8, 0);
               var wrap_pay_void: u8 = @intCast(u8, 0);
               if (c.is_extern == @intCast(u8, 1) and c.return_type != type_mod.TYPE_VOID) {
                   var rt_ty = emitter.registry.types_items[@intCast(usize, c.return_type)];
                   if (rt_ty.kind == type_mod.TypeKind.optional_type) {
                       need_wrap = @intCast(u8, 1);
                       wrap_kind = @intCast(u8, 1);
                       var op = emitter.registry.opt_items[@intCast(usize, rt_ty.payload_idx)];
                       var pay_ty = emitter.registry.types_items[@intCast(usize, op.payload)];
                       if (pay_ty.kind == type_mod.TypeKind.void_type) { wrap_pay_void = @intCast(u8, 1); }
                   } else if (rt_ty.kind == type_mod.TypeKind.error_union_type) {
                       need_wrap = @intCast(u8, 1);
                       wrap_kind = @intCast(u8, 2);
                       var eu = emitter.registry.eu_items[@intCast(usize, rt_ty.payload_idx)];
                       var pay_ty = emitter.registry.types_items[@intCast(usize, eu.payload)];
                       if (pay_ty.kind == type_mod.TypeKind.void_type) { wrap_pay_void = @intCast(u8, 1); }
                   }
               }
               if (need_wrap == @intCast(u8, 1)) {
                   var result = resolveTempName(emitter, c.result);
                    if (wrap_kind == @intCast(u8, 1)) {
                         if (wrap_pay_void == @intCast(u8, 0)) {
                            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                            bufferedWriterWrite(&emitter.writer, result);
                            var l2: []const u8 = ".value = ";
                            bufferedWriterWrite(&emitter.writer, l2);
                            var cd_rt = emitter.registry.types_items[@intCast(usize, c.return_type)];
                            var cd_pay: u32 = @intCast(u32, 0);
                            if (cd_rt.kind == type_mod.TypeKind.optional_type) {
                                var cd_op = emitter.registry.opt_items[@intCast(usize, cd_rt.payload_idx)];
                                cd_pay = cd_op.payload;
                            }
                            if (cd_pay != @intCast(u32, 0) and (emitter.registry.types_items[@intCast(usize, cd_pay)].kind == type_mod.TypeKind.ptr_type or emitter.registry.types_items[@intCast(usize, cd_pay)].kind == type_mod.TypeKind.many_ptr_type)) {
                                var cd_c0: []const u8 = "(";
                                bufferedWriterWrite(&emitter.writer, cd_c0);
                                var cd_pc = getCTypeName(emitter.registry, emitter.mangler, cd_pay);
                                bufferedWriterWrite(&emitter.writer, cd_pc);
                                var cd_c1: []const u8 = ")";
                                bufferedWriterWrite(&emitter.writer, cd_c1);
                            }
                            bufferedWriterWrite(&emitter.writer, fn_name);
                            var sp: []const u8 = "(";
                            bufferedWriterWrite(&emitter.writer, sp);
                            var ai: u32 = @intCast(u32, 0);
                            while (ai < c.args_count) : (ai += @intCast(u32, 1)) {
                                if (ai > @intCast(u32, 0)) { var sc: []const u8 = ", "; bufferedWriterWrite(&emitter.writer, sc); }
                                var arg = resolveTempName(emitter, c.args_start + ai);
                                bufferedWriterWrite(&emitter.writer, arg);
                            }
                            var s2: []const u8 = ");\n";
                            bufferedWriterWrite(&emitter.writer, s2);
                            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                            bufferedWriterWrite(&emitter.writer, result);
                            var l1: []const u8 = ".has_value = ";
                            bufferedWriterWrite(&emitter.writer, l1);
                            bufferedWriterWrite(&emitter.writer, result);
                            var l3: []const u8 = ".value != 0;\n";
                            bufferedWriterWrite(&emitter.writer, l3);
                        } else {
                            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                            bufferedWriterWrite(&emitter.writer, result);
                            var l1: []const u8 = ".has_value = 1;\n";
                            bufferedWriterWrite(&emitter.writer, l1);
                            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                            bufferedWriterWrite(&emitter.writer, fn_name);
                            var sp: []const u8 = "(";
                            bufferedWriterWrite(&emitter.writer, sp);
                            var ai: u32 = @intCast(u32, 0);
                            while (ai < c.args_count) : (ai += @intCast(u32, 1)) {
                                if (ai > @intCast(u32, 0)) { var sc: []const u8 = ", "; bufferedWriterWrite(&emitter.writer, sc); }
                                var arg = resolveTempName(emitter, c.args_start + ai);
                                bufferedWriterWrite(&emitter.writer, arg);
                            }
                            var s2: []const u8 = ");\n";
                            bufferedWriterWrite(&emitter.writer, s2);
                        }
                    } else {
                       bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                       bufferedWriterWrite(&emitter.writer, result);
                       var l1: []const u8 = ".is_error = 0;\n";
                       bufferedWriterWrite(&emitter.writer, l1);
                       if (wrap_pay_void == @intCast(u8, 0)) {
                           bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                           bufferedWriterWrite(&emitter.writer, result);
                           var l2: []const u8 = ".data.payload = ";
                           bufferedWriterWrite(&emitter.writer, l2);
                           bufferedWriterWrite(&emitter.writer, fn_name);
                           var sp: []const u8 = "(";
                           bufferedWriterWrite(&emitter.writer, sp);
                           var ai: u32 = @intCast(u32, 0);
                           while (ai < c.args_count) : (ai += @intCast(u32, 1)) {
                               if (ai > @intCast(u32, 0)) { var sc: []const u8 = ", "; bufferedWriterWrite(&emitter.writer, sc); }
                               var arg = resolveTempName(emitter, c.args_start + ai);
                               bufferedWriterWrite(&emitter.writer, arg);
                           }
                           var s2: []const u8 = ");\n";
                           bufferedWriterWrite(&emitter.writer, s2);
                       } else {
                           bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                           bufferedWriterWrite(&emitter.writer, fn_name);
                           var sp: []const u8 = "(";
                           bufferedWriterWrite(&emitter.writer, sp);
                           var ai: u32 = @intCast(u32, 0);
                           while (ai < c.args_count) : (ai += @intCast(u32, 1)) {
                               if (ai > @intCast(u32, 0)) { var sc: []const u8 = ", "; bufferedWriterWrite(&emitter.writer, sc); }
                               var arg = resolveTempName(emitter, c.args_start + ai);
                               bufferedWriterWrite(&emitter.writer, arg);
                           }
                           var s2: []const u8 = ");\n";
                           bufferedWriterWrite(&emitter.writer, s2);
                       }
                   }
               } else {
               if (c.return_type != type_mod.TYPE_VOID) {
                var result = resolveTempName(emitter, c.result);
                bufferedWriterWrite(&emitter.writer, result);
                var s: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s);
            }
            bufferedWriterWrite(&emitter.writer, fn_name);
            var sp: []const u8 = "(";
            bufferedWriterWrite(&emitter.writer, sp);
            var ai: u32 = @intCast(u32, 0);
            while (ai < c.args_count) : (ai += @intCast(u32, 1)) {
                if (ai > @intCast(u32, 0)) {
                    var sc: []const u8 = ", ";
                    bufferedWriterWrite(&emitter.writer, sc);
                }
                var arg = resolveTempName(emitter, c.args_start + ai);
                bufferedWriterWrite(&emitter.writer, arg);
            }
            var s2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, s2);
               }
        },
         .tail_call => |tc_slot| {
            var tc = lir_mod.lirSideGetTailCall(emitter.current_fn, tc_slot);
            var fn_name: []const u8 = undefined;
            if (tc.is_indirect == @intCast(u8, 1)) {
                fn_name = resolveTempName(emitter, tc.callee);
            } else {
                var mangled_id = nameManglerMangle(emitter.mangler, tc.callee, @intCast(u8, 0), tc.module_id);
                fn_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
            }
            if (tc.is_extern == @intCast(u8, 1)) {
                var orig_c = interner_mod.stringInternerGet(emitter.interner, tc.callee);
                fn_name = orig_c;
            }
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            if (tc.return_type != type_mod.TYPE_VOID) {
                var result = resolveTempName(emitter, tc.result);
                bufferedWriterWrite(&emitter.writer, result);
                var eq: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, eq);
            }
            bufferedWriterWrite(&emitter.writer, fn_name);
            var op: []const u8 = "(";
            bufferedWriterWrite(&emitter.writer, op);
            var ai: u32 = @intCast(u32, 0);
            while (ai < tc.args_count) : (ai += @intCast(u32, 1)) {
                if (ai > @intCast(u32, 0)) {
                    var sc: []const u8 = ", ";
                    bufferedWriterWrite(&emitter.writer, sc);
                }
                var arg = resolveTempName(emitter, tc.args_start + ai);
                bufferedWriterWrite(&emitter.writer, arg);
            }
            var cl: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, cl);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            if (tc.return_type != type_mod.TYPE_VOID) {
                var r: []const u8 = "return ";
                bufferedWriterWrite(&emitter.writer, r);
                var rv = resolveTempName(emitter, tc.result);
                bufferedWriterWrite(&emitter.writer, rv);
                var rs: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, rs);
            } else {
                var rv: []const u8 = "return;\n";
                bufferedWriterWrite(&emitter.writer, rv);
            }
        },
        .switch_br => |s| {
            var s1: []const u8 = "switch (";
            bufferedWriterWrite(&emitter.writer, s1);
            var cond = resolveTempName(emitter, s.cond);
            bufferedWriterWrite(&emitter.writer, cond);
            var s2: []const u8 = ") {\n";
            bufferedWriterWrite(&emitter.writer, s2);
            emitter.indent += @intCast(u32, 1);
            var i: u32 = s.cases_start;
            var end = s.cases_start + s.cases_count;
            while (i < end) : (i += @intCast(u32, 1)) {
                var c = emitter.switch_cases.items[@intCast(usize, i)];
                var case_kw: []const u8 = "case ";
                bufferedWriterWrite(&emitter.writer, case_kw);
                var val_buf: [20]u8 = undefined;
                var val_len = itoa_mod.itoa(@intCast(u32, c.value), val_buf[0..]);
                var val_start = @intCast(usize, @intCast(u32, val_buf.len) - @intCast(u32, 1) - val_len);
                var val_str = val_buf[val_start .. @intCast(usize, @intCast(u32, val_buf.len) - @intCast(u32, 1))];
                bufferedWriterWrite(&emitter.writer, val_str);
                var gotoa: []const u8 = ": goto z_bb_";
                bufferedWriterWrite(&emitter.writer, gotoa);
                var bb_buf: [10]u8 = undefined;
                var bb_len = itoa_mod.itoa(c.target_bb, bb_buf[0..]);
                var bb_start = @intCast(usize, @intCast(u32, bb_buf.len) - @intCast(u32, 1) - bb_len);
                var bb_str = bb_buf[bb_start .. @intCast(usize, @intCast(u32, bb_buf.len) - @intCast(u32, 1))];
                bufferedWriterWrite(&emitter.writer, bb_str);
                var semi: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, semi);
            }
            var default_kw: []const u8 = "default: goto z_bb_";
            bufferedWriterWrite(&emitter.writer, default_kw);
            var def_buf: [10]u8 = undefined;
            var def_len = itoa_mod.itoa(s.else_bb, def_buf[0..]);
            var def_start = @intCast(usize, @intCast(u32, def_buf.len) - @intCast(u32, 1) - def_len);
            var def_str = def_buf[def_start .. @intCast(usize, @intCast(u32, def_buf.len) - @intCast(u32, 1))];
            bufferedWriterWrite(&emitter.writer, def_str);
            var semi2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, semi2);
            emitter.indent -= @intCast(u32, 1);
            var close: []const u8 = "}\n";
            bufferedWriterWrite(&emitter.writer, close);
        },
        .wrap_optional => |w| {
            var insta_w_m: []const u8 = "INSTA:optw\n"; pal.markerWrite(insta_w_m);
            var dst = resolveTempName(emitter, w.result);
            var src = resolveTempName(emitter, w.value);
            var wo_ty = emitter.registry.types_items[@intCast(usize, w.type_id)];
            var wo_op = emitter.registry.opt_items[@intCast(usize, wo_ty.payload_idx)];
            var wo_pay = emitter.registry.types_items[@intCast(usize, wo_op.payload)];
            if (wo_pay.kind == type_mod.TypeKind.void_type) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l1: []const u8 = ".has_value = 1;\n";
                bufferedWriterWrite(&emitter.writer, l1);
            } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l1: []const u8 = ".has_value = 1;\n";
                bufferedWriterWrite(&emitter.writer, l1);
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l2: []const u8 = ".value = ";
                bufferedWriterWrite(&emitter.writer, l2);
                bufferedWriterWrite(&emitter.writer, src);
                var semi: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, semi);
            }
        },
        .int_cast => |c| {
            var dst = resolveTempName(emitter, c.result);
            var src = resolveTempName(emitter, c.value);
            var icm: []const u8 = "IC:v"; pal.markerWrite(icm);
            var icvb: [10]u8 = undefined; var icvl = itoa_mod.itoa(c.value, icvb[0..]); var icvs: usize = @intCast(usize, 9) - @intCast(usize, icvl); pal.markerWrite(icvb[icvs..@intCast(usize, 9)]);
            var ictm: []const u8 = "t"; pal.markerWrite(ictm);
            var ictb: [10]u8 = undefined; var ictl = itoa_mod.itoa(c.target, ictb[0..]); var icts: usize = @intCast(usize, 9) - @intCast(usize, ictl); pal.markerWrite(ictb[icts..@intCast(usize, 9)]);
            var icrm: []const u8 = "r"; pal.markerWrite(icrm);
            var icrb: [10]u8 = undefined; var icrl = itoa_mod.itoa(c.result, icrb[0..]); var icrs: usize = @intCast(usize, 9) - @intCast(usize, icrl); pal.markerWrite(icrb[icrs..@intCast(usize, 9)]);
            var icnl: []const u8 = "\n"; pal.markerWrite(icnl);
            var ctype = getCTypeName(emitter.registry, emitter.mangler, c.target);
            if (c.is_checked != @intCast(u8, 0)) {
                var src_tid = getTempTypeByIndex(emitter, c.value);
                if (src_tid != @intCast(u32, 0xFFFFFFFF)) {
                    var dst_suffix = getCastTypeSuffix(emitter.registry, c.target);
                    var src_suffix = getCastTypeSuffix(emitter.registry, src_tid);
                    var fn_buf: [64]u8 = undefined;
                    var fn_idx: usize = 0;
                    var boot_s: []const u8 = "__bootstrap_";
                    format_mod.copyStr(fn_buf[0..], &fn_idx, boot_s);
                    format_mod.copyStr(fn_buf[0..], &fn_idx, dst_suffix);
                    var from_s: []const u8 = "_from_";
                    format_mod.copyStr(fn_buf[0..], &fn_idx, from_s);
                    format_mod.copyStr(fn_buf[0..], &fn_idx, src_suffix);
                    var fn_name = fn_buf[0..fn_idx];
                    if (isBootstrapHelperDefined(fn_name)) {
                        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                        bufferedWriterWrite(&emitter.writer, dst);
                        var s1: []const u8 = " = ";
                        bufferedWriterWrite(&emitter.writer, s1);
                        bufferedWriterWrite(&emitter.writer, fn_name);
                        var s2: []const u8 = "(";
                        bufferedWriterWrite(&emitter.writer, s2);
                        bufferedWriterWrite(&emitter.writer, src);
                        var s3: []const u8 = ");\n";
                        bufferedWriterWrite(&emitter.writer, s3);
                    } else {
                        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                        bufferedWriterWrite(&emitter.writer, dst);
                        var s1: []const u8 = " = (";
                        bufferedWriterWrite(&emitter.writer, s1);
                        bufferedWriterWrite(&emitter.writer, ctype);
                        var s2: []const u8 = ")";
                        bufferedWriterWrite(&emitter.writer, s2);
                        bufferedWriterWrite(&emitter.writer, src);
                        var s3: []const u8 = ";\n";
                        bufferedWriterWrite(&emitter.writer, s3);
                    }
                } else {
                    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                    bufferedWriterWrite(&emitter.writer, dst);
                    var s1: []const u8 = " = (";
                    bufferedWriterWrite(&emitter.writer, s1);
                    bufferedWriterWrite(&emitter.writer, ctype);
                    var s2: []const u8 = ")";
                    bufferedWriterWrite(&emitter.writer, s2);
                    bufferedWriterWrite(&emitter.writer, src);
                    var s3: []const u8 = ";\n";
                    bufferedWriterWrite(&emitter.writer, s3);
                }
            } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var s1: []const u8 = " = (";
                bufferedWriterWrite(&emitter.writer, s1);
                bufferedWriterWrite(&emitter.writer, ctype);
                var s2: []const u8 = ")";
                bufferedWriterWrite(&emitter.writer, s2);
                bufferedWriterWrite(&emitter.writer, src);
                var s3: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, s3);
            }
        },
        .int_to_float => |c| {
            var dst = resolveTempName(emitter, c.result);
            var src = resolveTempName(emitter, c.value);
            var ctype = getCTypeName(emitter.registry, emitter.mangler, c.target);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = (";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, ctype);
            var s2: []const u8 = ")";
            bufferedWriterWrite(&emitter.writer, s2);
            bufferedWriterWrite(&emitter.writer, src);
            var s3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .float_cast => |c| {
            var dst = resolveTempName(emitter, c.result);
            var src = resolveTempName(emitter, c.value);
            var ctype = getCTypeName(emitter.registry, emitter.mangler, c.target);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = (";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, ctype);
            var s2: []const u8 = ")";
            bufferedWriterWrite(&emitter.writer, s2);
            bufferedWriterWrite(&emitter.writer, src);
            var s3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .make_slice => |s| {
            var dst = resolveTempName(emitter, s.result);
            var ptr = resolveTempName(emitter, s.ptr);
            var len = resolveTempName(emitter, s.len);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var l1: []const u8 = ".ptr = ";
            bufferedWriterWrite(&emitter.writer, l1);
            bufferedWriterWrite(&emitter.writer, ptr);
            var semi1: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, semi1);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var l2: []const u8 = ".len = ";
            bufferedWriterWrite(&emitter.writer, l2);
            bufferedWriterWrite(&emitter.writer, len);
            var semi2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, semi2);
        },
        .print_str => |p| {
            var str = interner_mod.stringInternerGet(emitter.interner, p.string_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s1: []const u8 = "std_print(";
            bufferedWriterWrite(&emitter.writer, s1);
            emitCStringLiteral(&emitter.writer, str);
            var s2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .print_val => |p| {
            var val = resolveTempName(emitter, p.value);
            var fn_name = getPrintFnName(emitter.registry, p.type_id, p.fmt);
            var ty = emitter.registry.types_items[@intCast(usize, p.type_id)];
            var is_slice: u8 = if (ty.kind == TypeKind.slice_type) @intCast(u8, 1) else @intCast(u8, 0);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, fn_name);
            var lp: []const u8 = "(";
            bufferedWriterWrite(&emitter.writer, lp);
            bufferedWriterWrite(&emitter.writer, val);
            if (is_slice != @intCast(u8, 0)) {
                var dot1: []const u8 = ".ptr, ";
                bufferedWriterWrite(&emitter.writer, dot1);
                bufferedWriterWrite(&emitter.writer, val);
                var dot2: []const u8 = ".len";
                bufferedWriterWrite(&emitter.writer, dot2);
            }
            var rp: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, rp);
        },
        .builtin_put_char => |bpc| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var bpc1: []const u8 = "putchar(";
            bufferedWriterWrite(&emitter.writer, bpc1);
            var bpc_v = resolveTempName(emitter, bpc.value);
            bufferedWriterWrite(&emitter.writer, bpc_v);
            var bpc2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, bpc2);
        },
        .builtin_stdout_write => |bsow| {
            emitFwriteCall(emitter, bsow.ptr, bsow.len, @intCast(u8, 1));
        },
        .builtin_stderr_write => |bsew| {
            emitFwriteCall(emitter, bsew.ptr, bsew.len, @intCast(u8, 0));
        },
        .builtin_get_char => |bgc| {
            var bgc_res = resolveTempName(emitter, bgc.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            if (dceTempIsDead(emitter, bgc.result)) {
                var vp: []const u8 = "(void)getchar();\n";
                bufferedWriterWrite(&emitter.writer, vp);
            } else {
            bufferedWriterWrite(&emitter.writer, bgc_res);
            var bgc1: []const u8 = " = getchar();\n";
            bufferedWriterWrite(&emitter.writer, bgc1);
            }
        },
        .builtin_exit => |bex| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var bex1: []const u8 = "exit(";
            bufferedWriterWrite(&emitter.writer, bex1);
            var bex_v = resolveTempName(emitter, bex.value);
            bufferedWriterWrite(&emitter.writer, bex_v);
            var bex2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, bex2);
        },
        .builtin_sleep_ms => |bsm| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var bsm0: []const u8 = "#ifdef _WIN32\n";
            bufferedWriterWrite(&emitter.writer, bsm0);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var bsm1: []const u8 = "Sleep(";
            bufferedWriterWrite(&emitter.writer, bsm1);
            var bsm_v = resolveTempName(emitter, bsm.value);
            bufferedWriterWrite(&emitter.writer, bsm_v);
            var bsm2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, bsm2);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var bsm3: []const u8 = "#else\n";
            bufferedWriterWrite(&emitter.writer, bsm3);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var bsm4: []const u8 = "usleep(";
            bufferedWriterWrite(&emitter.writer, bsm4);
            bufferedWriterWrite(&emitter.writer, bsm_v);
            var bsm5: []const u8 = " * 1000);\n";
            bufferedWriterWrite(&emitter.writer, bsm5);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var bsm6: []const u8 = "#endif\n";
            bufferedWriterWrite(&emitter.writer, bsm6);
        },
        .builtin_console_clear => {
            emitConsoleClear(emitter);
        },
        .builtin_console_gotoxy => |bcg| {
            emitConsoleGotoxy(emitter, bcg.x, bcg.y);
        },
        .builtin_console_set_color => |bcc| {
            emitConsoleSetColor(emitter, bcc.fg, bcc.bg);
        },
        .builtin_socket_create => |bsc| {
            emitSocketCreate(emitter, bsc.port, bsc.result);
        },
        .builtin_socket_bind_listen => |bsbl| {
            emitSocketBindListen(emitter, bsbl.sock, bsbl.backlog, bsbl.result);
        },
        .builtin_socket_accept => |bsa| {
            emitSocketAccept(emitter, bsa.sock, bsa.result);
        },
        .builtin_socket_connect => |bscon| {
            emitSocketConnect(emitter, bscon.sock, bscon.port, bscon.result);
        },
        .builtin_socket_send => |bss| {
            emitSocketSendRecv(emitter, bss.sock, bss.buf, bss.len, bss.result, @intCast(u8, 0));
        },
        .builtin_socket_recv => |bsr| {
            emitSocketSendRecv(emitter, bsr.sock, bsr.buf, bsr.len, bsr.result, @intCast(u8, 1));
        },
        .builtin_socket_select => |bssel_slot| {
            var bssel = lir_mod.lirSideGetSocketSelect(emitter.current_fn, bssel_slot);
            emitSocketSelect(emitter, bssel.nfds, bssel.readfds, bssel.writefds, bssel.exceptfds, bssel.timeout_ms, bssel.result);
        },
        .builtin_socket_fd_zero => |bsfz| {
            emitSocketFdZero(emitter, bsfz.set);
        },
        .builtin_socket_fd_set => |bsfs| {
            emitSocketFdSet(emitter, bsfs.fd, bsfs.set, @intCast(u8, 0), @intCast(u32, 0));
        },
        .builtin_socket_fd_isset => |bsfi| {
            emitSocketFdSet(emitter, bsfi.fd, bsfi.set, @intCast(u8, 1), bsfi.result);
        },
        .builtin_socket_close => |bscl| {
            emitSocketClose(emitter, bscl.sock);
        },
        .ptr_cast => |pc| {
            var dst = resolveTempName(emitter, pc.result);
            var src = resolveTempName(emitter, pc.value);
            var ctype = getCTypeName(emitter.registry, emitter.mangler, pc.target);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = (";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, ctype);
            var s2: []const u8 = ")";
            bufferedWriterWrite(&emitter.writer, s2);
            bufferedWriterWrite(&emitter.writer, src);
            var s3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .check_error => |e| {
            var dst = resolveTempName(emitter, e.result);
            var src = resolveTempName(emitter, e.value);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, src);
            var s2: []const u8 = ".is_error;\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .unwrap_error_payload => |e| {
            var insta_p_m: []const u8 = "INSTA:eup\n"; pal.markerWrite(insta_p_m);
            var dst = resolveTempName(emitter, e.result);
            var src = resolveTempName(emitter, e.value);
            var eup_src_tid = getTempTypeByIndex(emitter, e.value);
            var eup_pay_void: u8 = @intCast(u8, 0);
            if (eup_src_tid != @intCast(u32, 0xFFFFFFFF)) {
                var eup_src_ty = emitter.registry.types_items[@intCast(usize, eup_src_tid)];
                if (eup_src_ty.kind == type_mod.TypeKind.error_union_type) {
                    var eup_eu = emitter.registry.eu_items[@intCast(usize, eup_src_ty.payload_idx)];
                    var eup_pay = emitter.registry.types_items[@intCast(usize, eup_eu.payload)];
                    if (eup_pay.kind == type_mod.TypeKind.void_type) {
                        eup_pay_void = @intCast(u8, 1);
                    }
                }
            }
            if (eup_pay_void == @intCast(u8, 0)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var s1: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s1);
                bufferedWriterWrite(&emitter.writer, src);
                var s2: []const u8 = ".data.payload;\n";
                bufferedWriterWrite(&emitter.writer, s2);
            }
        },
        .unwrap_error_code => |e| {
            var insta_c_m: []const u8 = "INSTA:euc\n"; pal.markerWrite(insta_c_m);
            var dst = resolveTempName(emitter, e.result);
            var src = resolveTempName(emitter, e.value);
            var euc_src_tid = getTempTypeByIndex(emitter, e.value);
            var euc_pay_void: u8 = @intCast(u8, 0);
            if (euc_src_tid != @intCast(u32, 0xFFFFFFFF)) {
                var euc_src_ty = emitter.registry.types_items[@intCast(usize, euc_src_tid)];
                if (euc_src_ty.kind == type_mod.TypeKind.error_union_type) {
                    var euc_eu = emitter.registry.eu_items[@intCast(usize, euc_src_ty.payload_idx)];
                    var euc_pay = emitter.registry.types_items[@intCast(usize, euc_eu.payload)];
                    if (euc_pay.kind == type_mod.TypeKind.void_type) {
                        euc_pay_void = @intCast(u8, 1);
                    }
                }
            }
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, src);
            if (euc_pay_void != @intCast(u8, 0)) {
                var s2: []const u8 = ".err;\n";
                bufferedWriterWrite(&emitter.writer, s2);
            } else {
                var s2: []const u8 = ".data.err;\n";
                bufferedWriterWrite(&emitter.writer, s2);
            }
        },
        .wrap_error_ok => |w| {
            var dst = resolveTempName(emitter, w.result);
            var src = resolveTempName(emitter, w.value);
            var eu_ty = emitter.registry.types_items[@intCast(usize, w.type_id)];
            var eu = emitter.registry.eu_items[@intCast(usize, eu_ty.payload_idx)];
            var pay_ty = emitter.registry.types_items[@intCast(usize, eu.payload)];
            if (pay_ty.kind == type_mod.TypeKind.void_type) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l1: []const u8 = ".err = 0;\n";
                bufferedWriterWrite(&emitter.writer, l1);
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l2: []const u8 = ".is_error = 0;\n";
                bufferedWriterWrite(&emitter.writer, l2);
            } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l1: []const u8 = ".data.payload = ";
                bufferedWriterWrite(&emitter.writer, l1);
                bufferedWriterWrite(&emitter.writer, src);
                var semi1: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, semi1);
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l2: []const u8 = ".is_error = 0;\n";
                bufferedWriterWrite(&emitter.writer, l2);
            }
        },
        .wrap_error_err => |w| {
            var dst = resolveTempName(emitter, w.result);
            var src = resolveTempName(emitter, w.value);
            var eu_ty = emitter.registry.types_items[@intCast(usize, w.type_id)];
            var eu = emitter.registry.eu_items[@intCast(usize, eu_ty.payload_idx)];
            var pay_ty = emitter.registry.types_items[@intCast(usize, eu.payload)];
            if (pay_ty.kind == type_mod.TypeKind.void_type) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l1: []const u8 = ".err = ";
                bufferedWriterWrite(&emitter.writer, l1);
                bufferedWriterWrite(&emitter.writer, src);
                var semi1: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, semi1);
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l2: []const u8 = ".is_error = 1;\n";
                bufferedWriterWrite(&emitter.writer, l2);
            } else {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l1: []const u8 = ".data.err = ";
                bufferedWriterWrite(&emitter.writer, l1);
                bufferedWriterWrite(&emitter.writer, src);
                var semi1: []const u8 = ";\n";
                bufferedWriterWrite(&emitter.writer, semi1);
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var l2: []const u8 = ".is_error = 1;\n";
                bufferedWriterWrite(&emitter.writer, l2);
            }
        },
        .check_optional => |e| {
            var gapc_coe: []const u8 = "GAPC:coe\n"; pal.markerWrite(gapc_coe);
            var dst = resolveTempName(emitter, e.result);
            var src = resolveTempName(emitter, e.value);
            var gapc_cos: []const u8 = "GAPC:cos"; pal.markerWriteInt(gapc_cos, e.value);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, src);
            var s2: []const u8 = ".has_value;\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .unwrap_optional => |e| {
            var insta_ou_m: []const u8 = "INSTA:optu\n"; pal.markerWrite(insta_ou_m);
            var dst = resolveTempName(emitter, e.result);
            var src = resolveTempName(emitter, e.value);
            var uo_src_tid = getTempTypeByIndex(emitter, e.value);
            var uo_pay_void: u8 = @intCast(u8, 0);
            if (uo_src_tid != @intCast(u32, 0xFFFFFFFF)) {
                var uo_src_ty = emitter.registry.types_items[@intCast(usize, uo_src_tid)];
                if (uo_src_ty.kind == type_mod.TypeKind.optional_type) {
                    var uo_opt = emitter.registry.opt_items[@intCast(usize, uo_src_ty.payload_idx)];
                    var uo_pay = emitter.registry.types_items[@intCast(usize, uo_opt.payload)];
                    if (uo_pay.kind == type_mod.TypeKind.void_type) {
                        uo_pay_void = @intCast(u8, 1);
                    }
                }
            }
            if (uo_pay_void == @intCast(u8, 0)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                bufferedWriterWrite(&emitter.writer, dst);
                var s1: []const u8 = " = ";
                bufferedWriterWrite(&emitter.writer, s1);
                bufferedWriterWrite(&emitter.writer, src);
                var s2: []const u8 = ".value;\n";
                bufferedWriterWrite(&emitter.writer, s2);
            }
        },
        .unwrap_optional_abi => |e| {
            var dst = resolveTempName(emitter, e.result);
            var src = resolveTempName(emitter, e.value);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s0: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s0);
            bufferedWriterWrite(&emitter.writer, src);
            var s1: []const u8 = ".has_value ? ";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, src);
            var s2: []const u8 = ".value : NULL;\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .int_to_ptr => |c| {
            var dst = resolveTempName(emitter, c.result);
            var src = resolveTempName(emitter, c.value);
            var ctype = getCTypeName(emitter.registry, emitter.mangler, c.target);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = (";
            bufferedWriterWrite(&emitter.writer, s1);
            bufferedWriterWrite(&emitter.writer, ctype);
            var s2: []const u8 = ")(unsigned int)";
            bufferedWriterWrite(&emitter.writer, s2);
            bufferedWriterWrite(&emitter.writer, src);
            var s3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .ptr_to_int => |c| {
            var dst = resolveTempName(emitter, c.result);
            var src = resolveTempName(emitter, c.value);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var s1: []const u8 = " = (";
            bufferedWriterWrite(&emitter.writer, s1);
            var dst_type = getCTypeName(emitter.registry, emitter.mangler, type_mod.TYPE_USIZE);
            bufferedWriterWrite(&emitter.writer, dst_type);
            var s2: []const u8 = ")";
            bufferedWriterWrite(&emitter.writer, s2);
            bufferedWriterWrite(&emitter.writer, src);
            var s3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .func_ref => |fr| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var fr_result = resolveTempName(emitter, fr.result);
            bufferedWriterWrite(&emitter.writer, fr_result);
            var fr_eq: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, fr_eq);
            var fr_mangled = nameManglerMangle(emitter.mangler, fr.name_id, @intCast(u8, 0), fr.module_id);
            var fr_name = interner_mod.stringInternerGet(emitter.interner, fr_mangled);
            bufferedWriterWrite(&emitter.writer, fr_name);
            var fr_semi: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, fr_semi);
        },
        .va_start => |vs| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var vs0: []const u8 = "va_start(";
            bufferedWriterWrite(&emitter.writer, vs0);
            var vs_vl = resolveTempName(emitter, vs.va_list_temp);
            bufferedWriterWrite(&emitter.writer, vs_vl);
            var vs_c: []const u8 = ", ";
            bufferedWriterWrite(&emitter.writer, vs_c);
            var vs_lp = resolveTempName(emitter, vs.last_param_temp);
            bufferedWriterWrite(&emitter.writer, vs_lp);
            var vs_e: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, vs_e);
        },
        .va_arg => |va| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var va_vl = resolveTempName(emitter, va.va_list_temp);
            if (dceTempIsDead(emitter, va.result)) {
                var vp: []const u8 = "(void)va_arg(";
                bufferedWriterWrite(&emitter.writer, vp);
                bufferedWriterWrite(&emitter.writer, va_vl);
                var va_c2: []const u8 = ", ";
                bufferedWriterWrite(&emitter.writer, va_c2);
                var va_ct2 = getCTypeName(emitter.registry, emitter.mangler, va.type_id);
                bufferedWriterWrite(&emitter.writer, va_ct2);
                var va_e2: []const u8 = ");\n";
                bufferedWriterWrite(&emitter.writer, va_e2);
            } else {
            var va_res = resolveTempName(emitter, va.result);
            bufferedWriterWrite(&emitter.writer, va_res);
            var va_eq: []const u8 = " = va_arg(";
            bufferedWriterWrite(&emitter.writer, va_eq);
            bufferedWriterWrite(&emitter.writer, va_vl);
            var va_c: []const u8 = ", ";
            bufferedWriterWrite(&emitter.writer, va_c);
            var va_ct = getCTypeName(emitter.registry, emitter.mangler, va.type_id);
            bufferedWriterWrite(&emitter.writer, va_ct);
            var va_e: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, va_e);
            }
        },
        .va_end => |ve| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var ve0: []const u8 = "va_end(";
            bufferedWriterWrite(&emitter.writer, ve0);
            var ve_vl = resolveTempName(emitter, ve.va_list_temp);
            bufferedWriterWrite(&emitter.writer, ve_vl);
            var ve_e: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, ve_e);
        },
        else => {},
    }
}

fn dceTempIsDead(emitter: *C89Emitter, temp_id: u32) bool {
    if (temp_id >= emitter.d4_max_temp) { return false; }
    var p = emitter.d4_t2p[@intCast(usize, temp_id)];
    if (p == @intCast(u32, 0xFFFFFFFF)) { return false; }
    return emitter.d4_dead[@intCast(usize, p)] == @intCast(u8, 1);
}

fn dceMarkReadPos(max_temp: u32, tid_to_pos: [*]u32, read_count: [*]u32, t: u32) void {
    if (t < max_temp) {
        var p = tid_to_pos[@intCast(usize, t)];
        if (p != @intCast(u32, 0xFFFFFFFF)) {
            read_count[@intCast(usize, p)] += @intCast(u32, 1);
        }
    }
}

fn dceReleaseReadPos(max_temp: u32, tid_to_pos: [*]u32, read_count: [*]u32, t: u32) void {
    if (t < max_temp) {
        var p = tid_to_pos[@intCast(usize, t)];
        if (p != @intCast(u32, 0xFFFFFFFF)) {
            if (read_count[@intCast(usize, p)] > @intCast(u32, 0)) {
                read_count[@intCast(usize, p)] -= @intCast(u32, 1);
            }
        }
    }
}

fn dceProtectPos(max_temp: u32, tid_to_pos: [*]u32, protected_arr: [*]u8, t: u32) void {
    if (t < max_temp) {
        var p = tid_to_pos[@intCast(usize, t)];
        if (p != @intCast(u32, 0xFFFFFFFF)) {
            protected_arr[@intCast(usize, p)] = @intCast(u8, 1);
        }
    }
}

fn dceNoDeclPos(max_temp: u32, tid_to_pos: [*]u32, no_decl_arr: [*]u8, t: u32) void {
    if (t < max_temp) {
        var p = tid_to_pos[@intCast(usize, t)];
        if (p != @intCast(u32, 0xFFFFFFFF)) {
            no_decl_arr[@intCast(usize, p)] = @intCast(u8, 1);
        }
    }
}

fn dceFieldIsArray(registry: *TypeRegistry, lir_fn: *LirFunction, base_temp: u32, field_id: u32) bool {
    var bi: usize = @intCast(usize, 0);
    while (bi < lir_fn.hoisted_temps.len) : (bi += @intCast(usize, 1)) {
        var ht = lir_fn.hoisted_temps.items[bi];
        if (ht.temp_id == base_temp) {
            if (ht.type_id != type_mod.TYPE_UNDEFINED) {
                var bty = registry.types_items[@intCast(usize, ht.type_id)];
                if (bty.kind == type_mod.TypeKind.struct_type) {
                    var bst = registry.st_items[@intCast(usize, bty.payload_idx)];
                    if (field_id < @intCast(u32, bst.fields_count)) {
                        var fe = registry.fe_items[@intCast(usize, bst.fields_start) + @intCast(usize, field_id)];
                        var fty = registry.types_items[@intCast(usize, fe.type_id)];
                        if (fty.kind == type_mod.TypeKind.array_type) { return true; }
                    }
                } else if (bty.kind == type_mod.TypeKind.union_type) {
                    var bun = registry.un_items[@intCast(usize, bty.payload_idx)];
                    if (field_id < @intCast(u32, bun.fields_count)) {
                        var fe = registry.fe_items[@intCast(usize, bun.fields_start) + @intCast(usize, field_id)];
                        var fty = registry.types_items[@intCast(usize, fe.type_id)];
                        if (fty.kind == type_mod.TypeKind.array_type) { return true; }
                    }
                }
            }
            break;
        }
    }
    return false;
}

fn dceTempIsArray(registry: *TypeRegistry, lir_fn: *LirFunction, temp: u32) bool {
    var bi: usize = @intCast(usize, 0);
    while (bi < lir_fn.hoisted_temps.len) : (bi += @intCast(usize, 1)) {
        var ht = lir_fn.hoisted_temps.items[bi];
        if (ht.temp_id == temp) {
            if (ht.type_id != type_mod.TYPE_UNDEFINED) {
                var bty = registry.types_items[@intCast(usize, ht.type_id)];
                if (bty.kind == type_mod.TypeKind.array_type) { return true; }
            }
            break;
        }
    }
    return false;
}

fn dceMarkAllReads(lir_fn: *LirFunction, max_temp: u32, tid_to_pos: [*]u32, read_count: [*]u32, protected_arr: [*]u8, no_decl_arr: [*]u8, registry: *TypeRegistry) void {
    var bb_idx: usize = @intCast(usize, 0);
    while (bb_idx < lir_fn.blocks.len) : (bb_idx += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bb_idx];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            switch (inst) {
                .assign => |a| { dceMarkReadPos(max_temp, tid_to_pos, read_count, a.src); },
                .assign_field => |a| { dceMarkReadPos(max_temp, tid_to_pos, read_count, a.base); if (!dceFieldIsArray(registry, lir_fn, a.base, a.field_id)) { dceMarkReadPos(max_temp, tid_to_pos, read_count, a.src); } },
                .assign_index => |a| { if (!dceTempIsArray(registry, lir_fn, a.base)) { dceMarkReadPos(max_temp, tid_to_pos, read_count, a.base); } dceMarkReadPos(max_temp, tid_to_pos, read_count, a.index); dceMarkReadPos(max_temp, tid_to_pos, read_count, a.src); },
                .branch => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.cond); },
                .switch_br => |s| { dceMarkReadPos(max_temp, tid_to_pos, read_count, s.cond); },
                .ret => |v| { dceMarkReadPos(max_temp, tid_to_pos, read_count, v); },
                .binary => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.lhs); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.rhs); },
                .unary => |u| { dceMarkReadPos(max_temp, tid_to_pos, read_count, u.operand); },
                .call => |c| { dceMarkReadPos(max_temp, tid_to_pos, read_count, c.callee); var ai: u32 = @intCast(u32, 0); while (ai < c.args_count) : (ai += @intCast(u32, 1)) { dceMarkReadPos(max_temp, tid_to_pos, read_count, c.args_start + ai); } },
                .load_field => |lf| { dceMarkReadPos(max_temp, tid_to_pos, read_count, lf.base); },
                .store_field => |sf| { dceMarkReadPos(max_temp, tid_to_pos, read_count, sf.base); dceMarkReadPos(max_temp, tid_to_pos, read_count, sf.value); },
                .load_index => |li| { dceMarkReadPos(max_temp, tid_to_pos, read_count, li.base); dceMarkReadPos(max_temp, tid_to_pos, read_count, li.index); },
                .load => |l| { dceMarkReadPos(max_temp, tid_to_pos, read_count, l.ptr); },
                .store => |st| { dceMarkReadPos(max_temp, tid_to_pos, read_count, st.ptr); dceMarkReadPos(max_temp, tid_to_pos, read_count, st.value); },
                .addr_of => |a| { dceMarkReadPos(max_temp, tid_to_pos, read_count, a.operand); },
                .addr_of_field => |a| { dceMarkReadPos(max_temp, tid_to_pos, read_count, a.base); },
                .wrap_optional => |w| { dceMarkReadPos(max_temp, tid_to_pos, read_count, w.value); },
                .call_direct => |c_slot| { var c = lir_mod.lirSideGetCallDirect(lir_fn, c_slot); var ai: u32 = @intCast(u32, 0); while (ai < c.args_count) : (ai += @intCast(u32, 1)) { dceMarkReadPos(max_temp, tid_to_pos, read_count, c.args_start + ai); } },
                .va_start => |vs| { dceMarkReadPos(max_temp, tid_to_pos, read_count, vs.last_param_temp); },
                .va_arg => |va| { dceMarkReadPos(max_temp, tid_to_pos, read_count, va.va_list_temp); },
                .va_end => |ve| { dceMarkReadPos(max_temp, tid_to_pos, read_count, ve.va_list_temp); },
                .tail_call => |tc_slot| { var tc = lir_mod.lirSideGetTailCall(lir_fn, tc_slot); if (tc.is_indirect != @intCast(u8, 0)) { dceMarkReadPos(max_temp, tid_to_pos, read_count, tc.callee); } var ai: u32 = @intCast(u32, 0); while (ai < tc.args_count) : (ai += @intCast(u32, 1)) { dceMarkReadPos(max_temp, tid_to_pos, read_count, tc.args_start + ai); } dceProtectPos(max_temp, tid_to_pos, protected_arr, tc.result); },
                .unwrap_optional => |u| { dceMarkReadPos(max_temp, tid_to_pos, read_count, u.value); },
                .unwrap_optional_abi => |u| { dceMarkReadPos(max_temp, tid_to_pos, read_count, u.value); },
                .check_optional => |c| { dceMarkReadPos(max_temp, tid_to_pos, read_count, c.value); },
                .wrap_error_ok => |w| { dceMarkReadPos(max_temp, tid_to_pos, read_count, w.value); },
                .wrap_error_err => |w| { dceMarkReadPos(max_temp, tid_to_pos, read_count, w.value); },
                .unwrap_error_payload => |u| { dceMarkReadPos(max_temp, tid_to_pos, read_count, u.value); },
                .unwrap_error_code => |u| { dceMarkReadPos(max_temp, tid_to_pos, read_count, u.value); },
                .check_error => |c| { dceMarkReadPos(max_temp, tid_to_pos, read_count, c.value); },
                .make_slice => |ms| { dceMarkReadPos(max_temp, tid_to_pos, read_count, ms.ptr); dceMarkReadPos(max_temp, tid_to_pos, read_count, ms.len); },
                .int_cast => |ic| { dceMarkReadPos(max_temp, tid_to_pos, read_count, ic.value); },
                .float_cast => |fc| { dceMarkReadPos(max_temp, tid_to_pos, read_count, fc.value); },
                .ptr_cast => |pc| { dceMarkReadPos(max_temp, tid_to_pos, read_count, pc.value); },
                .int_to_float => |itf| { dceMarkReadPos(max_temp, tid_to_pos, read_count, itf.value); },
                .ptr_to_int => |pti| { dceMarkReadPos(max_temp, tid_to_pos, read_count, pti.value); },
                .int_to_ptr => |itp| { dceMarkReadPos(max_temp, tid_to_pos, read_count, itp.value); },
                .store_local => |sl| { dceMarkReadPos(max_temp, tid_to_pos, read_count, sl.value); },
                .store_global => |sg| { dceMarkReadPos(max_temp, tid_to_pos, read_count, sg.value); },
                .print_val => |pv| { dceMarkReadPos(max_temp, tid_to_pos, read_count, pv.value); },
                .builtin_put_char => |bpc| { dceMarkReadPos(max_temp, tid_to_pos, read_count, bpc.value); },
                .builtin_stdout_write => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.ptr); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.len); },
                .builtin_stderr_write => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.ptr); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.len); },
                .builtin_get_char => |bgc| { },
                .builtin_exit => |be| { dceMarkReadPos(max_temp, tid_to_pos, read_count, be.value); },
                .builtin_sleep_ms => |bsm| { dceMarkReadPos(max_temp, tid_to_pos, read_count, bsm.value); },
                .builtin_console_gotoxy => |bcg| { dceMarkReadPos(max_temp, tid_to_pos, read_count, bcg.x); dceMarkReadPos(max_temp, tid_to_pos, read_count, bcg.y); },
                .builtin_console_set_color => |bcc| { dceMarkReadPos(max_temp, tid_to_pos, read_count, bcc.fg); dceMarkReadPos(max_temp, tid_to_pos, read_count, bcc.bg); },
                .builtin_socket_create => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.port); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_bind_listen => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.sock); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.backlog); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_accept => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.sock); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_connect => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.sock); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.port); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_send => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.sock); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.buf); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.len); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_recv => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.sock); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.buf); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.len); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_select => |b_slot| { var b = lir_mod.lirSideGetSocketSelect(lir_fn, b_slot); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.nfds); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.readfds); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.writefds); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.exceptfds); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.timeout_ms); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_fd_zero => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.set); },
                .builtin_socket_fd_set => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.fd); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.set); },
                .builtin_socket_fd_isset => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.fd); dceMarkReadPos(max_temp, tid_to_pos, read_count, b.set); dceProtectPos(max_temp, tid_to_pos, protected_arr, b.result); },
                .builtin_socket_close => |b| { dceMarkReadPos(max_temp, tid_to_pos, read_count, b.sock); },
                .load_global => |lg| { dceNoDeclPos(max_temp, tid_to_pos, no_decl_arr, lg.result); },
                else => {},
            }
        }
    }
}

fn dceMarkAllWritten(lir_fn: *LirFunction, max_temp: u32, tid_to_pos: [*]u32, written_arr: [*]u8) void {
    var bi: usize = @intCast(usize, 0);
    while (bi < lir_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = bb.insts.items[ii];
            switch (inst) {
                .set_optional_null => {},
                else => {
                    var rp = dceResultPos(max_temp, tid_to_pos, inst);
                    if (rp != @intCast(u32, 0xFFFFFFFF)) {
                        written_arr[@intCast(usize, rp)] = @intCast(u8, 1);
                    }
                },
            }
        }
    }
}

fn dceResultPos(max_temp: u32, tid_to_pos: [*]u32, inst: lir_mod.LirInst) u32 {
    var t: u32 = @intCast(u32, 0xFFFFFFFF);
    switch (inst) {
        .binary => |b| { t = b.result; },
        .unary => |u| { t = u.result; },
        .int_const => |ic| { t = ic.result; },
        .float_const => |fc| { t = fc.result; },
        .string_const => |sc| { t = sc.result; },
        .null_const => |nc| { t = nc.result; },
        .set_optional_null => |sn| { t = sn.result; },
        .bool_const => |bc| { t = bc.result; },
        .undefined_const => |uc| { t = uc.result; },
        .enum_const => |ec| { t = ec.result; },
        .int_cast => |ic| { t = ic.result; },
        .float_cast => |fc| { t = fc.result; },
        .ptr_cast => |pc| { t = pc.result; },
        .int_to_float => |itf| { t = itf.result; },
        .int_to_ptr => |itp| { t = itp.result; },
        .ptr_to_int => |pti| { t = pti.result; },
        .make_slice => |ms| { t = ms.result; },
        .addr_of => |a| { t = a.result; },
        .addr_of_field => |a| { t = a.result; },
        .func_ref => |fr| { t = fr.result; },
        .wrap_optional => |w| { t = w.result; },
        .wrap_error_ok => |w| { t = w.result; },
        .wrap_error_err => |w| { t = w.result; },
        .unwrap_optional => |u| { t = u.result; },
        .unwrap_optional_abi => |u| { t = u.result; },
        .check_optional => |c| { t = c.result; },
        .unwrap_error_payload => |u| { t = u.result; },
        .unwrap_error_code => |u| { t = u.result; },
        .check_error => |c| { t = c.result; },
        .load => |l| { t = l.result; },
        .load_field => |lf| { t = lf.result; },
        .load_index => |li| { t = li.result; },
        .load_local => |ll| { t = ll.result; },
        .assign => |a| { t = a.dst; },
        .assign_field => |a| { t = a.base; },
        .assign_index => |a| { t = a.base; },
        else => { return @intCast(u32, 0xFFFFFFFF); },
    }
    if (t >= max_temp) { return @intCast(u32, 0xFFFFFFFF); }
    var p = tid_to_pos[@intCast(usize, t)];
    return p;
}

fn dceReleaseOperands(max_temp: u32, tid_to_pos: [*]u32, read_count: [*]u32, inst: lir_mod.LirInst) void {
    switch (inst) {
        .binary => |b| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, b.lhs); dceReleaseReadPos(max_temp, tid_to_pos, read_count, b.rhs); },
        .unary => |u| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, u.operand); },
        .int_cast => |ic| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, ic.value); },
        .float_cast => |fc| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, fc.value); },
        .ptr_cast => |pc| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, pc.value); },
        .int_to_float => |itf| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, itf.value); },
        .int_to_ptr => |itp| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, itp.value); },
        .ptr_to_int => |pti| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, pti.value); },
        .make_slice => |ms| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, ms.ptr); dceReleaseReadPos(max_temp, tid_to_pos, read_count, ms.len); },
        .addr_of => |a| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.operand); },
        .addr_of_field => |a| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.base); },
        .wrap_optional => |w| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, w.value); },
        .wrap_error_ok => |w| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, w.value); },
        .wrap_error_err => |w| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, w.value); },
        .unwrap_optional => |u| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, u.value); },
        .unwrap_optional_abi => |u| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, u.value); },
        .check_optional => |c| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, c.value); },
        .unwrap_error_payload => |u| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, u.value); },
        .unwrap_error_code => |u| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, u.value); },
        .check_error => |c| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, c.value); },
        .load => |l| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, l.ptr); },
        .load_field => |lf| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, lf.base); },
        .load_index => |li| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, li.base); dceReleaseReadPos(max_temp, tid_to_pos, read_count, li.index); },
        .assign => |a| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.src); },
        .assign_field => |a| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.base); dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.src); },
        .assign_index => |a| { dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.base); dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.index); dceReleaseReadPos(max_temp, tid_to_pos, read_count, a.src); },
        else => {},
    }
}

 pub fn emitFunctionBody(emitter: *C89Emitter, lir_fn: *LirFunction) void {
    bufferedWriterFlush(&emitter.writer);
    var bfn_m: []const u8 = "BFN:p"; pal.markerWrite(bfn_m);
    var bfn_pb: [10]u8 = undefined; var bfn_pl = itoa_mod.itoa(@intCast(u32, emitter.writer.pos), bfn_pb[0..]); var bfn_ps: usize = @intCast(usize, 9) - @intCast(usize, bfn_pl); pal.markerWrite(bfn_pb[bfn_ps..@intCast(usize, 9)]);
    var bfn_nl: []const u8 = "\n"; pal.markerWrite(bfn_nl);
    emitter.current_fn = lir_fn;
    emitter.dedup_count = @intCast(u32, 0);
    emitter.temp_global_map.count = @intCast(usize, 0);
    var tg_cap: usize = @intCast(usize, 0);
    while (tg_cap < emitter.temp_global_map.capacity) : (tg_cap += @intCast(usize, 1)) {
        emitter.temp_global_map.occupied[tg_cap] = @intCast(u8, 0);
    }
    if (emitter.dl_hoisted == @intCast(u8, 0)) {
        var bb_idx: usize = @intCast(usize, 0);
        while (bb_idx < lir_fn.blocks.len) : (bb_idx += @intCast(usize, 1)) {
            var bb = &lir_fn.blocks.items[bb_idx];
            var ii: usize = @intCast(usize, 0);
            while (ii < bb.insts.len) : (ii += @intCast(usize, 1)) {
                var inst = bb.insts.items[ii];
                switch (inst) {
                    .decl_local => |dl| {
                        var dl_is_dup: u8 = @intCast(u8, 0);
                        var dl_lc: u32 = @intCast(u32, 0);
                        while (@intCast(usize, dl_lc) < @intCast(usize, emitter.dedup_count)) : (dl_lc += @intCast(u32, 1)) {
                            if (emitter.dedup_names[@intCast(usize, dl_lc)] == dl.name_id) { dl_is_dup = @intCast(u8, 1); break; }
                        }
                        if (dl_is_dup != @intCast(u8, 0)) { var da: []const u8 = "DxA:s\n"; pal.markerWrite(da); continue; }
                        if (isDeadLocalName(emitter, dl.name_id) != @intCast(u8, 0)) { var dld: []const u8 = "DLD:s\n"; pal.markerWrite(dld); continue; }
                        if (emitter.dedup_count >= emitter.dedup_cap) {
                            var nb = @ptrCast([*]u32, alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, emitter.dedup_cap * @intCast(u32, 2)) * @intCast(usize, @sizeOf(u32)), @intCast(usize, 4)) catch unreachable);
                            var ci: u32 = @intCast(u32, 0);
                            while (ci < emitter.dedup_count) : (ci += @intCast(u32, 1)) {
                                nb[@intCast(usize, ci)] = emitter.dedup_names[@intCast(usize, ci)];
                            }
                            emitter.dedup_names = nb;
                            emitter.dedup_cap = emitter.dedup_cap * @intCast(u32, 2);
                        }
                        emitter.dedup_names[@intCast(usize, emitter.dedup_count)] = dl.name_id;
                        emitter.dedup_count += @intCast(u32, 1);
                         var p1m: []const u8 = "P1:t"; pal.markerWrite(p1m);
                         var p1tb: [10]u8 = undefined; var p1tl = itoa_mod.itoa(dl.temp, p1tb[0..]); var p1ts: usize = @intCast(usize, 9) - @intCast(usize, p1tl); pal.markerWrite(p1tb[p1ts..@intCast(usize, 9)]);
                         var p1im: []const u8 = "T"; pal.markerWrite(p1im);
                         var p1ib: [10]u8 = undefined; var p1il = itoa_mod.itoa(@intCast(u32, dl.type_id), p1ib[0..]); var p1is: usize = @intCast(usize, 9) - @intCast(usize, p1il); pal.markerWrite(p1ib[p1is..@intCast(usize, 9)]);
                         var p1nm: []const u8 = "N"; pal.markerWrite(p1nm);
                         var p1nb: [10]u8 = undefined; var p1nl = itoa_mod.itoa(dl.name_id, p1nb[0..]); var p1ns: usize = @intCast(usize, 9) - @intCast(usize, p1nl); pal.markerWrite(p1nb[p1ns..@intCast(usize, 9)]);
                         var p1nl2: []const u8 = "\n"; pal.markerWrite(p1nl2);
                         var dl_type = getCTypeName(emitter.registry, emitter.mangler, dl.type_id);
                         var vfdl_tm: []const u8 = "VFLOW:dlT"; pal.markerWrite(vfdl_tm);
                         var vfdl_tb: [10]u8 = undefined; var vfdl_tl = itoa_mod.itoa(dl.type_id, vfdl_tb[0..]); var vfdl_ts: usize = @intCast(usize, 9) - @intCast(usize, vfdl_tl); pal.markerWrite(vfdl_tb[vfdl_ts..@intCast(usize, 9)]);
                         var vfdl_nl: []const u8 = "\n"; pal.markerWrite(vfdl_nl);
                         if (dl.type_id == @intCast(u32, 1)) {
                             var t4u_dl_m: []const u8 = "T4U:dl\n"; pal.markerWrite(t4u_dl_m);
                             var instb_ed_m: []const u8 = "INSTB:edl\n"; pal.markerWrite(instb_ed_m);
                         }
                         var dl_name = mangleLocalName(emitter.mangler, emitter.interner, dl.name_id);
                        if (dl.type_id != @intCast(u32, 1)) {
                        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                        bufferedWriterWrite(&emitter.writer, dl_type);
                        var sp1: []const u8 = " ";
                        bufferedWriterWrite(&emitter.writer, sp1);
                        bufferedWriterWrite(&emitter.writer, dl_name);
                        var sm1: []const u8 = ";\n";
                        bufferedWriterWrite(&emitter.writer, sm1);
                        }
                    },
                    .tail_call => {},
                    .va_start => {},
                    .va_arg => {},
                    .va_end => {},
                    else => {},
                }
            }
        }
        emitter.dl_hoisted = @intCast(u8, 1);
    }
    var bb_used_cap: u32 = @intCast(u32, 1);
    var bbcap_idx: usize = @intCast(usize, 0);
    while (bbcap_idx < lir_fn.blocks.len) : (bbcap_idx += @intCast(usize, 1)) {
        var bbcap = &lir_fn.blocks.items[bbcap_idx];
        if (bbcap.id >= bb_used_cap) { bb_used_cap = bbcap.id + @intCast(u32, 1); }
    }
    var raw_bu = alloc_mod.sandAlloc(emitter.alloc, @intCast(usize, bb_used_cap) * @intCast(usize, 1), @intCast(usize, 1)) catch unreachable;
    var bb_used_arr = @ptrCast([*]u8, raw_bu);
    var bu_z: u32 = @intCast(u32, 0);
    while (bu_z < bb_used_cap) : (bu_z += @intCast(u32, 1)) { bb_used_arr[@intCast(usize, bu_z)] = @intCast(u8, 0); }
    var bu_idx: usize = @intCast(usize, 0);
    while (bu_idx < lir_fn.blocks.len) : (bu_idx += @intCast(usize, 1)) {
        var bub = &lir_fn.blocks.items[bu_idx];
        var bu_ii: usize = @intCast(usize, 0);
        while (bu_ii < bub.insts.len) : (bu_ii += @intCast(usize, 1)) {
            var buinst = bub.insts.items[bu_ii];
            switch (buinst) {
                .jump => |jb| { if (jb < bb_used_cap) { bb_used_arr[@intCast(usize, jb)] = @intCast(u8, 1); } },
                .branch => |br| { if (br.then_bb < bb_used_cap) { bb_used_arr[@intCast(usize, br.then_bb)] = @intCast(u8, 1); } if (br.else_bb < bb_used_cap) { bb_used_arr[@intCast(usize, br.else_bb)] = @intCast(u8, 1); } },
                .switch_br => |sw| {
                    var swi: u32 = sw.cases_start;
                    var swend = sw.cases_start + sw.cases_count;
                    while (swi < swend) : (swi += @intCast(u32, 1)) {
                        var swc = emitter.switch_cases.items[@intCast(usize, swi)];
                        if (swc.target_bb < bb_used_cap) { bb_used_arr[@intCast(usize, swc.target_bb)] = @intCast(u8, 1); }
                    }
                    if (sw.else_bb < bb_used_cap) { bb_used_arr[@intCast(usize, sw.else_bb)] = @intCast(u8, 1); }
                },
                else => {},
            }
        }
    }
    emitter.bb_used = bb_used_arr;
    emitter.bb_used_count = bb_used_cap;
    var upi: u32 = @intCast(u32, 0);
    while (upi < @intCast(u32, lir_fn.params.len)) : (upi += @intCast(u32, 1)) {
        if (isLocalPosUsed(emitter, upi) == @intCast(u8, 0)) {
            var up_name = mangleLocalName(emitter.mangler, emitter.interner, lir_fn.params.items[@intCast(usize, upi)].name_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var up0: []const u8 = "(void)";
            bufferedWriterWrite(&emitter.writer, up0);
            bufferedWriterWrite(&emitter.writer, up_name);
            var up1: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, up1);
        }
    }
    var bb_idx: usize = @intCast(usize, 0);
    while (bb_idx < lir_fn.blocks.len) : (bb_idx += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bb_idx];
        if (bb.id > @intCast(u32, 0)) {
            if (bb.id < bb_used_cap and bb_used_arr[@intCast(usize, bb.id)] != @intCast(u8, 0)) {
                bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
                var l1: []const u8 = "z_bb_";
                bufferedWriterWrite(&emitter.writer, l1);
                var nb: [16]u8 = undefined;
                var nl = itoa_mod.itoa(bb.id, nb[0..]);
                var ns = @intCast(u32, @intCast(u32, 15) - nl);
                var si: usize = @intCast(usize, ns);
                var ei: usize = @intCast(usize, 15);
                bufferedWriterWrite(&emitter.writer, nb[si..ei]);
                var l2: []const u8 = ":\n";
                bufferedWriterWrite(&emitter.writer, l2);
            }
        }
        var inst_idx: usize = @intCast(usize, 0);
        while (inst_idx < bb.insts.len) : (inst_idx += @intCast(usize, 1)) {
            var inst = bb.insts.items[inst_idx];
            var dce_rp = dceResultPos(emitter.d4_max_temp, emitter.d4_t2p, inst);
            if (dce_rp != @intCast(u32, 0xFFFFFFFF)) {
                if (emitter.d4_dead[@intCast(usize, dce_rp)] == @intCast(u8, 1)) { continue; }
            }
            emitInst(emitter, inst);
        }
    }
    emitter.indent -= @intCast(u32, 1);
    var cl: []const u8 = "}\n\n";
    bufferedWriterWrite(&emitter.writer, cl);
    var bfx_m: []const u8 = "BFX:p"; pal.markerWrite(bfx_m);
    var bfx_pb: [10]u8 = undefined; var bfx_pl = itoa_mod.itoa(@intCast(u32, emitter.writer.pos), bfx_pb[0..]); var bfx_ps: usize = @intCast(usize, 9) - @intCast(usize, bfx_pl); pal.markerWrite(bfx_pb[bfx_ps..@intCast(usize, 9)]);
    var bfx_nl: []const u8 = "\n"; pal.markerWrite(bfx_nl);
}

pub fn emitZigRuntimeC(writer: *BufferedWriter) void {
    var l00: []const u8 = "/* zig_runtime.c - Z98 Runtime Library (generated) */\n";
    bufferedWriterWrite(writer, l00);
    var l01: []const u8 = "#include \"zig_compat.h\"\n";
    bufferedWriterWrite(writer, l01);
    var l02: []const u8 = "#include <string.h>\n";
    bufferedWriterWrite(writer, l02);
    var l03: []const u8 = "\n";
    bufferedWriterWrite(writer, l03);
    var l04: []const u8 = "/* Forward declarations for PAL functions */\n";
    bufferedWriterWrite(writer, l04);
    var l05: []const u8 = "extern void pal_print_stderr(const char* s, unsigned int len);\n";
    bufferedWriterWrite(writer, l05);
    var l05b: []const u8 = "extern void pal_print_stdout(const char* s, unsigned int len);\n";
    bufferedWriterWrite(writer, l05b);
    var l06: []const u8 = "extern void pal_abort(void);\n";
    bufferedWriterWrite(writer, l06);
    var l07: []const u8 = "extern int pal_i64_to_str(long long val, char* buf, int bufsize);\n";
    bufferedWriterWrite(writer, l07);
    var l08: []const u8 = "extern int pal_u64_to_str(unsigned long long val, char* buf, int bufsize);\n";
    bufferedWriterWrite(writer, l08);
    var l09: []const u8 = "extern int pal_f64_to_str(double val, char* buf, int bufsize);\n";
    bufferedWriterWrite(writer, l09);
    var l010: []const u8 = "\n";
    bufferedWriterWrite(writer, l010);
    var l011: []const u8 = "/* Panic handler */\n";
    bufferedWriterWrite(writer, l011);
    var l012: []const u8 = "void std_panic(const char* msg) {\n";
    bufferedWriterWrite(writer, l012);
    var l013: []const u8 = "    pal_print_stderr(\"panic: \", 7);\n";
    bufferedWriterWrite(writer, l013);
    var l014: []const u8 = "    pal_print_stderr(msg, strlen(msg));\n";
    bufferedWriterWrite(writer, l014);
    var l015: []const u8 = "    pal_print_stderr(\"\\n\", 1);\n";
    bufferedWriterWrite(writer, l015);
    var l016: []const u8 = "    pal_abort();\n";
    bufferedWriterWrite(writer, l016);
    var l017: []const u8 = "}\n";
    bufferedWriterWrite(writer, l017);
    var l018: []const u8 = "\n";
    bufferedWriterWrite(writer, l018);
    var l019: []const u8 = "/* Print helpers */\n";
    bufferedWriterWrite(writer, l019);
    var l020: []const u8 = "void std_print(const char* s) { if (s) pal_print_stdout(s, strlen(s)); }\n";
    bufferedWriterWrite(writer, l020);
    var l021: []const u8 = "void std_print_len(const char* s, unsigned int len) { if (s && len) pal_print_stdout(s, len); }\n";
    bufferedWriterWrite(writer, l021);
    var l022: []const u8 = "\n";
    bufferedWriterWrite(writer, l022);
    var l023: []const u8 = "void std_print_i32(int val) {\n";
    bufferedWriterWrite(writer, l023);
    var l024: []const u8 = "    char buf[16];\n";
    bufferedWriterWrite(writer, l024);
    var l025: []const u8 = "    pal_i64_to_str((long long)val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l025);
    var l026: []const u8 = "    std_print(buf);\n";
    bufferedWriterWrite(writer, l026);
    var l027: []const u8 = "}\n";
    bufferedWriterWrite(writer, l027);
    var l028: []const u8 = "\n";
    bufferedWriterWrite(writer, l028);
    var l029: []const u8 = "void std_print_u32(unsigned int val) {\n";
    bufferedWriterWrite(writer, l029);
    var l030: []const u8 = "    char buf[16];\n";
    bufferedWriterWrite(writer, l030);
    var l031: []const u8 = "    pal_u64_to_str((unsigned long long)val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l031);
    var l032: []const u8 = "    std_print(buf);\n";
    bufferedWriterWrite(writer, l032);
    var l033: []const u8 = "}\n";
    bufferedWriterWrite(writer, l033);
    var l034: []const u8 = "\n";
    bufferedWriterWrite(writer, l034);
    var l035: []const u8 = "void std_print_i64(long long val) {\n";
    bufferedWriterWrite(writer, l035);
    var l036: []const u8 = "    char buf[24];\n";
    bufferedWriterWrite(writer, l036);
    var l037: []const u8 = "    pal_i64_to_str(val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l037);
    var l038: []const u8 = "    std_print(buf);\n";
    bufferedWriterWrite(writer, l038);
    var l039: []const u8 = "}\n";
    bufferedWriterWrite(writer, l039);
    var l040: []const u8 = "\n";
    bufferedWriterWrite(writer, l040);
    var l041: []const u8 = "void std_print_u64(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l041);
    var l042: []const u8 = "    char buf[24];\n";
    bufferedWriterWrite(writer, l042);
    var l043: []const u8 = "    pal_u64_to_str(val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l043);
    var l044: []const u8 = "    std_print(buf);\n";
    bufferedWriterWrite(writer, l044);
    var l045: []const u8 = "}\n";
    bufferedWriterWrite(writer, l045);
    var l046: []const u8 = "\n";
    bufferedWriterWrite(writer, l046);
    var l047: []const u8 = "void std_print_f64(double val) {\n";
    bufferedWriterWrite(writer, l047);
    var l048: []const u8 = "    char buf[32];\n";
    bufferedWriterWrite(writer, l048);
    var l049: []const u8 = "    pal_f64_to_str(val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l049);
    var l050: []const u8 = "    std_print(buf);\n";
    bufferedWriterWrite(writer, l050);
    var l051: []const u8 = "}\n";
    bufferedWriterWrite(writer, l051);
    var l052: []const u8 = "\n";
    bufferedWriterWrite(writer, l052);
    var l053: []const u8 = "void std_print_bool(int val) {\n";
    bufferedWriterWrite(writer, l053);
    var l054: []const u8 = "    if (val) std_print(\"true\");\n";
    bufferedWriterWrite(writer, l054);
    var l055: []const u8 = "    else std_print(\"false\");\n";
    bufferedWriterWrite(writer, l055);
    var l056: []const u8 = "}\n";
    bufferedWriterWrite(writer, l056);
    var l057: []const u8 = "\n";
    bufferedWriterWrite(writer, l057);
    var l058: []const u8 = "void std_print_char(unsigned char val) { char c = (char)val; pal_print_stdout(&c, 1); }\n";
    bufferedWriterWrite(writer, l058);
    var l059: []const u8 = "\n";
    bufferedWriterWrite(writer, l059);
    var l060: []const u8 = "void std_print_str(const unsigned char* ptr, unsigned int len) {\n";
    bufferedWriterWrite(writer, l060);
    var l061: []const u8 = "    if (ptr && len) pal_print_stdout((const char*)ptr, len);\n";
    bufferedWriterWrite(writer, l061);
    var l062: []const u8 = "}\n";
    bufferedWriterWrite(writer, l062);
    var l063: []const u8 = "\n";
    bufferedWriterWrite(writer, l063);
    var l064: []const u8 = "/* Checked conversions (u64 -> target type) */\n";
    bufferedWriterWrite(writer, l064);
    var l065: []const u8 = "\n";
    bufferedWriterWrite(writer, l065);
    var l066: []const u8 = "signed char std_checked_cast_i8(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l066);
    var l067: []const u8 = "    if (val > 127ULL) std_panic(\"int cast overflow for i8\");\n";
    bufferedWriterWrite(writer, l067);
    var l068: []const u8 = "    return (signed char)val;\n";
    bufferedWriterWrite(writer, l068);
    var l069: []const u8 = "}\n";
    bufferedWriterWrite(writer, l069);
    var l070: []const u8 = "\n";
    bufferedWriterWrite(writer, l070);
    var l071: []const u8 = "unsigned char std_checked_cast_u8(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l071);
    var l072: []const u8 = "    if (val > 255ULL) std_panic(\"int cast overflow for u8\");\n";
    bufferedWriterWrite(writer, l072);
    var l073: []const u8 = "    return (unsigned char)val;\n";
    bufferedWriterWrite(writer, l073);
    var l074: []const u8 = "}\n";
    bufferedWriterWrite(writer, l074);
    var l075: []const u8 = "\n";
    bufferedWriterWrite(writer, l075);
    var l076: []const u8 = "short std_checked_cast_i16(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l076);
    var l077: []const u8 = "    if (val > 32767ULL) std_panic(\"int cast overflow for i16\");\n";
    bufferedWriterWrite(writer, l077);
    var l078: []const u8 = "    return (short)val;\n";
    bufferedWriterWrite(writer, l078);
    var l079: []const u8 = "}\n";
    bufferedWriterWrite(writer, l079);
    var l080: []const u8 = "\n";
    bufferedWriterWrite(writer, l080);
    var l081: []const u8 = "unsigned short std_checked_cast_u16(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l081);
    var l082: []const u8 = "    if (val > 65535ULL) std_panic(\"int cast overflow for u16\");\n";
    bufferedWriterWrite(writer, l082);
    var l083: []const u8 = "    return (unsigned short)val;\n";
    bufferedWriterWrite(writer, l083);
    var l084: []const u8 = "}\n";
    bufferedWriterWrite(writer, l084);
    var l085: []const u8 = "\n";
    bufferedWriterWrite(writer, l085);
    var l086: []const u8 = "int std_checked_cast_i32(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l086);
    var l087: []const u8 = "    if (val > 2147483647ULL) std_panic(\"int cast overflow for i32\");\n";
    bufferedWriterWrite(writer, l087);
    var l088: []const u8 = "    return (int)val;\n";
    bufferedWriterWrite(writer, l088);
    var l089: []const u8 = "}\n";
    bufferedWriterWrite(writer, l089);
    var l090: []const u8 = "\n";
    bufferedWriterWrite(writer, l090);
    var l091: []const u8 = "unsigned int std_checked_cast_u32(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l091);
    var l092: []const u8 = "    if (val > 4294967295ULL) std_panic(\"int cast overflow for u32\");\n";
    bufferedWriterWrite(writer, l092);
    var l093: []const u8 = "    return (unsigned int)val;\n";
    bufferedWriterWrite(writer, l093);
    var l094: []const u8 = "}\n";
    bufferedWriterWrite(writer, l094);
    var l095: []const u8 = "\n";
    bufferedWriterWrite(writer, l095);
    var l096: []const u8 = "long long std_checked_cast_i64(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l096);
    var l097: []const u8 = "    if (val > 9223372036854775807ULL) std_panic(\"int cast overflow for i64\");\n";
    bufferedWriterWrite(writer, l097);
    var l098: []const u8 = "    return (long long)val;\n";
    bufferedWriterWrite(writer, l098);
    var l099: []const u8 = "}\n";
    bufferedWriterWrite(writer, l099);
    var l100: []const u8 = "\n";
    bufferedWriterWrite(writer, l100);
    var l101: []const u8 = "unsigned long long std_checked_cast_u64(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l101);
    var l102: []const u8 = "    return val;\n";
    bufferedWriterWrite(writer, l102);
    var l103: []const u8 = "}\n";
    bufferedWriterWrite(writer, l103);
    var l104: []const u8 = "\n/* Backward compatibility aliases for zig1 -> user code */\n";
    bufferedWriterWrite(writer, l104);
    var l105: []const u8 = "void __bootstrap_print(const char* s) { std_print(s); }\n";
    bufferedWriterWrite(writer, l105);
    var l106: []const u8 = "void __bootstrap_print_int(int n) { std_print_i32(n); }\n";
    bufferedWriterWrite(writer, l106);
    var l107: []const u8 = "void __bootstrap_print_char(int c) { unsigned char uc = (unsigned char)c; std_print_char(uc); }\n";
    bufferedWriterWrite(writer, l107);
    var l108: []const u8 = "void __bootstrap_panic(const char* msg, const char* file, int line) { (void)file; (void)line; std_panic(msg); }\n";
    bufferedWriterWrite(writer, l108);
    var l109: []const u8 = "void __bootstrap_write(const char* s, unsigned int len) { std_print_len(s, len); }\n";
    bufferedWriterWrite(writer, l109);
    var l110: []const u8 = "void __bootstrap_sleep_ms(unsigned int ms) { (void)ms; }\n";
    bufferedWriterWrite(writer, l110);
}

// Reference-only: emitBuildTargetSh/Bat/OwcBat are never called by any pipeline
// path (grep of the repo finds only these definitions). They hardcode the legacy
// root module filename "main.c"; since F-S7 the root module is emitted as
// main_<HEX8>.c, so these templates are stale. Kept as reference; do not emit.
pub fn emitBuildTargetSh(writer: *BufferedWriter, out_name: []const u8) void {
    var l01: []const u8 = "#!/bin/sh\n# build_target.sh - generated by zig1\nTARGET=${1:-linux}\nCFLAGS=\"-std=c89 -pedantic -Wall -Werror\"\n";
    bufferedWriterWrite(writer, l01);
    var l02: []const u8 = "\ncase \"$TARGET\" in\n    linux)\n        CC=gcc\n        PLATFORM_DEF=\"-DZIG_POSIX\"\n        LINK_FLAGS=\"\"\n        OUT=";
    bufferedWriterWrite(writer, l02);
    bufferedWriterWrite(writer, out_name);
    var l03: []const u8 = "\n        ;;\n    mingw)\n        CC=i686-w64-mingw32-gcc\n        PLATFORM_DEF=\"-DZIG_WIN32\"\n        LINK_FLAGS=\"-lkernel32 -nostdlib\"\n        OUT=";
    bufferedWriterWrite(writer, l03);
    bufferedWriterWrite(writer, out_name);
    var l04: []const u8 = "\n        ;;\n    *)\n        echo \"Unknown target: $TARGET\"; exit 1\n        ;;\nesac\n\necho \"Building for $TARGET...\"\n\n$CC $CFLAGS $PLATFORM_DEF -c zig_pal.c -o zig_pal.o\n$CC $CFLAGS $PLATFORM_DEF -c zig_runtime.c -o zig_runtime.o\n$CC $CFLAGS $PLATFORM_DEF -c main.c -o main.o\n\n$CC -o $OUT zig_pal.o zig_runtime.o main.o $LINK_FLAGS\n\necho \"Built: $OUT\"\n";
    bufferedWriterWrite(writer, l04);
}

pub fn emitBuildTargetBat(writer: *BufferedWriter, out_name: []const u8) void {
    var l01: []const u8 = "@echo off\nREM build_target.bat - generated by zig1\n\nset CC=cl\nset CFLAGS=/c /Za /W3 /WX /DZIG_WIN32\nset LINK=link\n\necho Compiling...\n%CC% %CFLAGS% zig_pal.c\n%CC% %CFLAGS% zig_runtime.c\n%CC% %CFLAGS% main.c\n\necho Linking...\n%LINK% /subsystem:console kernel32.lib zig_pal.obj zig_runtime.obj main.obj /out:";
    bufferedWriterWrite(writer, l01);
    bufferedWriterWrite(writer, out_name);
    var l02: []const u8 = "\n\necho Built: ";
    bufferedWriterWrite(writer, l02);
    bufferedWriterWrite(writer, out_name);
    var l03: []const u8 = "\n";
    bufferedWriterWrite(writer, l03);
}

pub fn emitBuildOwcBat(writer: *BufferedWriter, out_name: []const u8) void {
    var l01: []const u8 = "@echo off\nREM build_owc.bat - generated by zig1 for OpenWatcom\n\necho Compiling...\nwcc386 /za /we /dZIG_WIN32 zig_pal.c\nwcc386 /za /we /dZIG_WIN32 zig_runtime.c\nwcc386 /za /we /dZIG_WIN32 main.c\n\necho Linking...\nwlink system console op q opt stack=65536 file zig_pal.obj, zig_runtime.obj, main.obj name ";
    bufferedWriterWrite(writer, l01);
    bufferedWriterWrite(writer, out_name);
    var l02: []const u8 = "\n\necho Built: ";
    bufferedWriterWrite(writer, l02);
    bufferedWriterWrite(writer, out_name);
    var l03: []const u8 = "\n";
    bufferedWriterWrite(writer, l03);
}
