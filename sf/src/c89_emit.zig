const pal = @import("pal.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeKind = @import("type_registry.zig").TypeKind;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const LirInst = @import("lir.zig").LirInst;
const SwitchCaseArrayList = @import("lir.zig").SwitchCaseArrayList;
const U32ArrayList = @import("growable_array.zig").U32ArrayList;
const U64ToU32Map = @import("util/hash.zig").U64ToU32Map;
const U32ToU32Map = @import("util/hash.zig").U32ToU32Map;
const alloc_mod = @import("allocator.zig");
const Sand = @import("allocator.zig").Sand;
const hash_mod = @import("util/hash.zig");
const interner_mod = @import("string_interner.zig");
const type_resolver = @import("type_resolver.zig");
const itoa_mod = @import("util/itoa.zig");
const TypeResolver = type_resolver.TypeResolver;
const sym_reg = @import("symbol_registrator.zig");
const LirFunction = @import("lir.zig").LirFunction;
const LirParam = @import("lir.zig").LirParam;

pub const BufferedWriter = struct {
    buf: [4096]u8,
    pos: usize,
};

pub fn bufferedWriterInit() BufferedWriter {
    return BufferedWriter{ .buf = undefined, .pos = @intCast(usize, 0) };
}

pub fn bufferedWriterFlush(self: *BufferedWriter) void {
    if (self.pos == @intCast(usize, 0)) return;
    pal.stdout_write(self.buf[0..self.pos]);
    self.pos = @intCast(usize, 0);
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
    var total = level * @intCast(u32, 4);
    var i: u32 = @intCast(u32, 0);
    while (i < total) : (i += @intCast(u32, 1)) {
        if (self.pos == 4096) bufferedWriterFlush(self);
        self.buf[self.pos] = @intCast(u8, ' ');
        self.pos += @intCast(usize, 1);
    }
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

pub fn nameManglerInit(interner: *StringInterner, alloc: *Sand) NameMangler {
    var mangler = NameMangler{
        .hash_seed = @intCast(u32, 0),
        .cache = hash_mod.u64ToU32MapInit(alloc),
        .keyword_set = hash_mod.u32ToU32MapInit(alloc),
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
    var key: u64 = (@intCast(u64, module_id) << @intCast(u64, 32)) | @intCast(u64, name_id);
    if (hash_mod.u64ToU32MapGet(&self.cache, key)) |cached| return cached;
    var hash = hash_mod.fnv1a(name);
    var kind_char: u8 = @intCast(u8, 'L');
    if (kind == @intCast(u8, 0)) kind_char = @intCast(u8, 'F');
    else if (kind == @intCast(u8, 1)) kind_char = @intCast(u8, 'G');
    else if (kind == @intCast(u8, 2)) kind_char = @intCast(u8, 'T');
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
    var counter: u32 = @intCast(u32, 0);
    while (true) {
        var existing_mod = hash_mod.u32ToU32MapGet(&self.collision_mod, mangled_id);
        if (existing_mod) |mod| {
            var existing_name = hash_mod.u32ToU32MapGet(&self.collision_name, mangled_id);
            if (existing_name) |name| {
                if (mod == module_id and name == name_id) break;
            }
            counter += @intCast(u32, 1);
            p = prefix_end;
            var max_nc = @intCast(usize, 31) - prefix_end - @intCast(usize, 3);
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
};

pub fn c89EmitterInit(reg: *TypeRegistry, interner: *StringInterner, mangler: *NameMangler, diag: *DiagnosticCollector, sc: *SwitchCaseArrayList, ca: *U32ArrayList, alloc: *Sand) C89Emitter {
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
    };
}

fn getCTypeName(reg: *TypeRegistry, mangler: *NameMangler, tid: u32) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    if (ty.kind == TypeKind.void_type) { var s: []const u8 = "void"; return s; }
    if (ty.kind == TypeKind.bool_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.i8_type) { var s: []const u8 = "signed char"; return s; }
    if (ty.kind == TypeKind.i16_type) { var s: []const u8 = "short"; return s; }
    if (ty.kind == TypeKind.i32_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.i64_type) { var s: []const u8 = "z64"; return s; }
    if (ty.kind == TypeKind.u8_type) { var s: []const u8 = "unsigned char"; return s; }
    if (ty.kind == TypeKind.u16_type) { var s: []const u8 = "unsigned short"; return s; }
    if (ty.kind == TypeKind.u32_type) { var s: []const u8 = "unsigned int"; return s; }
    if (ty.kind == TypeKind.u64_type) { var s: []const u8 = "zu64"; return s; }
    if (ty.kind == TypeKind.f32_type) { var s: []const u8 = "float"; return s; }
    if (ty.kind == TypeKind.f64_type) { var s: []const u8 = "double"; return s; }
    if (ty.kind == TypeKind.usize_type) { var s: []const u8 = "unsigned int"; return s; }
    if (ty.kind == TypeKind.c_char_type) { var s: []const u8 = "char"; return s; }
    var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    return interner_mod.stringInternerGet(mangler.interner, mid);
}

pub fn emitZigCompatH(writer: *BufferedWriter) void {
    var l00: []const u8 = "/* zig_compat.h - C89 compatibility layer */\n";
    bufferedWriterWrite(writer, l00);
    var l01: []const u8 = "#ifndef ZIG_COMPAT_H\n";
    bufferedWriterWrite(writer, l01);
    var l02: []const u8 = "#define ZIG_COMPAT_H\n";
    bufferedWriterWrite(writer, l02);
    var l03: []const u8 = "\n";
    bufferedWriterWrite(writer, l03);
    var l04: []const u8 = "/* 64-bit integers */\n";
    bufferedWriterWrite(writer, l04);
    var l05: []const u8 = "#if defined(_MSC_VER) && _MSC_VER <= 1200\n";
    bufferedWriterWrite(writer, l05);
    var l06: []const u8 = "  typedef __int64 z64;\n";
    bufferedWriterWrite(writer, l06);
    var l07: []const u8 = "  typedef unsigned __int64 zu64;\n";
    bufferedWriterWrite(writer, l07);
    var l08: []const u8 = "#elif defined(__WATCOMC__)\n";
    bufferedWriterWrite(writer, l08);
    var l09: []const u8 = "  typedef __int64 z64;\n";
    bufferedWriterWrite(writer, l09);
    var l10: []const u8 = "  typedef unsigned __int64 zu64;\n";
    bufferedWriterWrite(writer, l10);
    var l11: []const u8 = "#else\n";
    bufferedWriterWrite(writer, l11);
    var l12: []const u8 = "  typedef long long z64;\n";
    bufferedWriterWrite(writer, l12);
    var l13: []const u8 = "  typedef unsigned long long zu64;\n";
    bufferedWriterWrite(writer, l13);
    var l14: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l14);
    var l15: []const u8 = "\n";
    bufferedWriterWrite(writer, l15);
    var l16: []const u8 = "/* Boolean */\n";
    bufferedWriterWrite(writer, l16);
    var l17: []const u8 = "#ifndef bool\n";
    bufferedWriterWrite(writer, l17);
    var l18: []const u8 = "  typedef int bool;\n";
    bufferedWriterWrite(writer, l18);
    var l19: []const u8 = "  #define true 1\n";
    bufferedWriterWrite(writer, l19);
    var l20: []const u8 = "  #define false 0\n";
    bufferedWriterWrite(writer, l20);
    var l21: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l21);
    var l22: []const u8 = "\n";
    bufferedWriterWrite(writer, l22);
    var l23: []const u8 = "/* Null pointer */\n";
    bufferedWriterWrite(writer, l23);
    var l24: []const u8 = "#ifndef NULL\n";
    bufferedWriterWrite(writer, l24);
    var l25: []const u8 = "  #define NULL ((void*)0)\n";
    bufferedWriterWrite(writer, l25);
    var l26: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l26);
    var l27: []const u8 = "\n";
    bufferedWriterWrite(writer, l27);
    var l28: []const u8 = "#endif\n";
    bufferedWriterWrite(writer, l28);
}

pub fn emitSpecialTypes(emitter: *C89Emitter, reg: *TypeRegistry, g: *sym_reg.DepGraph) void {
    var resolver: TypeResolver = type_resolver.typeResolverInit(reg, emitter.diag, emitter.alloc);
    type_resolver.typeResolverBuild(&resolver, g);
    type_resolver.typeResolverResolve(&resolver);
    var sorted = type_resolver.typeResolverGetSorted(&resolver);
    var i: usize = @intCast(usize, 0);
    while (i < sorted.len) : (i += @intCast(usize, 1)) {
        var tid = sorted[i];
        var ty = reg.types_items[@intCast(usize, tid)];
        if (ty.kind == TypeKind.void_type) continue;
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
                ty.kind != TypeKind.tagged_union_type and
                ty.kind != TypeKind.union_type)
                continue;
        }
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
    var tag_ep = reg.en_items[@intCast(usize, tag_ty.payload_idx)];
    var fstart: usize = @intCast(usize, tp.fields_start);
    var fcount: usize = @intCast(usize, tp.fields_count);
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
        bufferedWriterWrite(&emitter.writer, val_itoa[0..@intCast(usize, val_len)]);
        var sd: []const u8 = "\n";
        bufferedWriterWrite(&emitter.writer, sd);
    }
    var se: []const u8 = "typedef struct {\n";
    bufferedWriterWrite(&emitter.writer, se);
    var sf: []const u8 = "\tint tag;\n";
    bufferedWriterWrite(&emitter.writer, sf);
    var sg: []const u8 = "\tunion {\n";
    bufferedWriterWrite(&emitter.writer, sg);
    var sh: []const u8 = "\t\tchar _dummy;\n";
    bufferedWriterWrite(&emitter.writer, sh);
    var fi: usize = @intCast(usize, 0);
    while (fi < fcount) : (fi += @intCast(usize, 1)) {
        var fe = reg.fe_items[fstart + fi];
        var ft = reg.types_items[@intCast(usize, fe.type_id)];
        if (ft.kind != TypeKind.void_type) {
            var var_buf: [64]u8 = undefined;
            var vp: usize = @intCast(usize, 0);
            var vti: usize = @intCast(usize, 0);
            while (vti < tp_pos and vp < @intCast(usize, 63)) : (vti += @intCast(usize, 1)) {
                var_buf[vp] = tag_pref_buf[vti]; vp += @intCast(usize, 1);
            }
            if (vp < @intCast(usize, 63)) { var_buf[vp] = @intCast(u8, '_'); vp += @intCast(usize, 1); }
            var fe_name = interner_mod.stringInternerGet(emitter.interner, fe.name_id);
            var fni: usize = @intCast(usize, 0);
            while (fni < fe_name.len and vp < @intCast(usize, 63)) : (fni += @intCast(usize, 1)) {
                var_buf[vp] = fe_name[fni]; vp += @intCast(usize, 1);
            }
            if (vp > @intCast(usize, 63)) vp = @intCast(usize, 63);
            var varnid = interner_mod.stringInternerIntern(emitter.interner, var_buf[0..vp]);
            var var_mid = nameManglerMangle(emitter.mangler, varnid, @intCast(u8, 2), @intCast(u32, 0));
            var var_name = interner_mod.stringInternerGet(emitter.interner, var_mid);
            var si1: []const u8 = "\t\tstruct { ";
            bufferedWriterWrite(&emitter.writer, si1);
            var fi_type = getCTypeName(reg, emitter.mangler, fe.type_id);
            bufferedWriterWrite(&emitter.writer, fi_type);
            var si2: []const u8 = " _0; } ";
            bufferedWriterWrite(&emitter.writer, si2);
            bufferedWriterWrite(&emitter.writer, var_name);
            var si3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, si3);
        }
    }
    var sj: []const u8 = "\t} payload;\n";
    bufferedWriterWrite(&emitter.writer, sj);
    var sk: []const u8 = "} ";
    bufferedWriterWrite(&emitter.writer, sk);
    bufferedWriterWrite(&emitter.writer, struct_name);
    var sl: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, sl);
}

fn emitTypeDefinition(emitter: *C89Emitter, tid: u32) void {
    var ty = emitter.registry.types_items[@intCast(usize, tid)];
    if (ty.kind == TypeKind.slice_type) { emitSliceType(emitter, tid); return; }
    if (ty.kind == TypeKind.optional_type) { emitOptionalType(emitter, tid); return; }
    if (ty.kind == TypeKind.error_union_type) { emitErrorUnionType(emitter, tid); return; }
    if (ty.kind == TypeKind.tagged_union_type) { emitTaggedUnionType(emitter, tid); return; }
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
    var pay_c_name = getCTypeName(reg, emitter.mangler, op.payload);
    var pay_ty = reg.types_items[@intCast(usize, op.payload)];
    var pay_mid = nameManglerMangle(emitter.mangler, pay_ty.name_id, @intCast(u8, 2), @intCast(u32, 0));
    var pay_mangled = interner_mod.stringInternerGet(emitter.interner, pay_mid);
    var buf: [64]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    var pref: []const u8 = "Opt_";
    var pi: usize = @intCast(usize, 0);
    while (pi < pref.len and p < @intCast(usize, 63)) : (pi += @intCast(usize, 1)) {
        buf[p] = pref[pi]; p += @intCast(usize, 1);
    }
    var ei: usize = @intCast(usize, 0);
    while (ei < pay_mangled.len and p < @intCast(usize, 63)) : (ei += @intCast(usize, 1)) {
        buf[p] = pay_mangled[ei]; p += @intCast(usize, 1);
    }
    if (p > @intCast(usize, 63)) p = @intCast(usize, 63);
    var opt_nid = interner_mod.stringInternerIntern(emitter.interner, buf[0..p]);
    var mangled_id = nameManglerMangle(emitter.mangler, opt_nid, @intCast(u8, 2), @intCast(u32, 0));
    var mangled_c_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
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
    var buf: [64]u8 = undefined;
    var p: usize = @intCast(usize, 0);
    var pref: []const u8 = "EU_";
    var pi: usize = @intCast(usize, 0);
    while (pi < pref.len and p < @intCast(usize, 63)) : (pi += @intCast(usize, 1)) {
        buf[p] = pref[pi]; p += @intCast(usize, 1);
    }
    var pay_c_name: []const u8 = undefined;
    if (pay_ty.kind == TypeKind.void_type) {
        var vp: []const u8 = "void";
        var vi: usize = @intCast(usize, 0);
        while (vi < vp.len and p < @intCast(usize, 63)) : (vi += @intCast(usize, 1)) {
            buf[p] = vp[vi]; p += @intCast(usize, 1);
        }
    } else {
        pay_c_name = getCTypeName(reg, emitter.mangler, ep.payload);
        var pay_mid = nameManglerMangle(emitter.mangler, pay_ty.name_id, @intCast(u8, 2), @intCast(u32, 0));
        var pay_mangled = interner_mod.stringInternerGet(emitter.interner, pay_mid);
        var ei: usize = @intCast(usize, 0);
        while (ei < pay_mangled.len and p < @intCast(usize, 63)) : (ei += @intCast(usize, 1)) {
            buf[p] = pay_mangled[ei]; p += @intCast(usize, 1);
        }
    }
    if (p > @intCast(usize, 63)) p = @intCast(usize, 63);
    var eu_nid = interner_mod.stringInternerIntern(emitter.interner, buf[0..p]);
    var mangled_id = nameManglerMangle(emitter.mangler, eu_nid, @intCast(u8, 2), @intCast(u32, 0));
    var mangled_c_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
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

pub fn emitFunctionSignature(emitter: *C89Emitter, lir_fn: *LirFunction, module_id: u32) void {
    var orig = interner_mod.stringInternerGet(emitter.interner, lir_fn.name_id);
    var sc: []const u8 = "/* ";
    bufferedWriterWrite(&emitter.writer, sc);
    bufferedWriterWrite(&emitter.writer, orig);
    var sd: []const u8 = " */\n";
    bufferedWriterWrite(&emitter.writer, sd);

    var ret_c = getCTypeName(emitter.registry, emitter.mangler, lir_fn.return_type);
    bufferedWriterWrite(&emitter.writer, ret_c);
    var sp: []const u8 = " ";
    bufferedWriterWrite(&emitter.writer, sp);

    var fn_mid = nameManglerMangle(emitter.mangler, lir_fn.name_id, @intCast(u8, 0), module_id);
    var fn_name = interner_mod.stringInternerGet(emitter.interner, fn_mid);
    bufferedWriterWrite(&emitter.writer, fn_name);

    var op: []const u8 = "(";
    bufferedWriterWrite(&emitter.writer, op);

    if (lir_fn.params.len == @intCast(usize, 0)) {
        var vd: []const u8 = "void";
        bufferedWriterWrite(&emitter.writer, vd);
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
    }

    var cl: []const u8 = ") {\n";
    bufferedWriterWrite(&emitter.writer, cl);
    emitter.indent += @intCast(u32, 1);
}

fn mangleTempName(interner: *StringInterner, temp_id: u32) []const u8 {
    var buf: [20]u8 = undefined;
    buf[0] = @intCast(u8, 'z');
    buf[1] = @intCast(u8, 'T');
    buf[2] = @intCast(u8, '_');
    var len = itoa_mod.itoa(temp_id, buf[3..]);
    var end: usize = @intCast(usize, 3) + @intCast(usize, len);
    var mid = interner_mod.stringInternerIntern(interner, buf[0..end]);
    return interner_mod.stringInternerGet(interner, mid);
}

pub fn emitHoistedDecls(emitter: *C89Emitter, lir_fn: *LirFunction) void {
    var i: usize = @intCast(usize, 0);
    while (i < lir_fn.hoisted_temps.len) : (i += @intCast(usize, 1)) {
        var td = lir_fn.hoisted_temps.items[i];
        var c_type = getCTypeName(emitter.registry, emitter.mangler, td.type_id);
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, c_type);
        var sp: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, sp);
        var tn = mangleTempName(emitter.interner, td.temp_id);
        bufferedWriterWrite(&emitter.writer, tn);
        var sm: []const u8 = ";\n";
        bufferedWriterWrite(&emitter.writer, sm);
    }
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
    else { var s: []const u8 = "???"; return s; }
}

fn getUnOpStr(op: u8) []const u8 {
    if (op == @intCast(u8, 0)) { var s: []const u8 = "-"; return s; }
    else if (op == @intCast(u8, 1)) { var s: []const u8 = "!"; return s; }
    else { var s: []const u8 = "~"; return s; }
}

fn emitInst(emitter: *C89Emitter, inst: LirInst) void {
    switch (inst) {
        .nop => {},
        .ret_void => {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s: []const u8 = "return;\n";
            bufferedWriterWrite(&emitter.writer, s);
        },
        .loop_header => {},
        .label => {},
        .assign => |a| {
            var dst = mangleTempName(emitter.interner, a.dst);
            var src = mangleTempName(emitter.interner, a.src);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, dst);
            var sep: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, sep);
            bufferedWriterWrite(&emitter.writer, src);
            var sep2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, sep2);
        },
        .assign_field => |a| {
            var base = mangleTempName(emitter.interner, a.base);
            var src = mangleTempName(emitter.interner, a.src);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, base);
            var sep: []const u8 = ".f_";
            bufferedWriterWrite(&emitter.writer, sep);
            var fb: [16]u8 = undefined;
            var fl = itoa_mod.itoa(a.field_id, fb[0..]);
            var fn_idx = @intCast(u32, @intCast(u32, 15) - fl);
            var fn_start: usize = @intCast(usize, fn_idx);
            var fn_end: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, fb[fn_start..fn_end]);
            var sep2: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, sep2);
            bufferedWriterWrite(&emitter.writer, src);
            var sep3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, sep3);
        },
        .assign_index => |a| {
            var base = mangleTempName(emitter.interner, a.base);
            var idx = mangleTempName(emitter.interner, a.index);
            var src = mangleTempName(emitter.interner, a.src);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, base);
            var sep: []const u8 = "[";
            bufferedWriterWrite(&emitter.writer, sep);
            bufferedWriterWrite(&emitter.writer, idx);
            var sep2: []const u8 = "] = ";
            bufferedWriterWrite(&emitter.writer, sep2);
            bufferedWriterWrite(&emitter.writer, src);
            var sep3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, sep3);
        },
        .jump => |bb| {
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s: []const u8 = "goto z_bb_";
            bufferedWriterWrite(&emitter.writer, s);
            var nb: [16]u8 = undefined;
            var nl = itoa_mod.itoa(bb, nb[0..]);
            var ns = @intCast(u32, @intCast(u32, 15) - nl);
            var si: usize = @intCast(usize, ns);
            var ei: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, nb[si..ei]);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .branch => |b| {
            var cond = mangleTempName(emitter.interner, b.cond);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s: []const u8 = "if (";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, cond);
            var s2: []const u8 = ") goto z_bb_";
            bufferedWriterWrite(&emitter.writer, s2);
            var tb: [16]u8 = undefined;
            var tl = itoa_mod.itoa(b.then_bb, tb[0..]);
            var ts = @intCast(u32, @intCast(u32, 15) - tl);
            var tsi: usize = @intCast(usize, ts);
            var tei: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, tb[tsi..tei]);
            var s3: []const u8 = "; else goto z_bb_";
            bufferedWriterWrite(&emitter.writer, s3);
            var eb: [16]u8 = undefined;
            var el = itoa_mod.itoa(b.else_bb, eb[0..]);
            var es = @intCast(u32, @intCast(u32, 15) - el);
            var esi: usize = @intCast(usize, es);
            var eei: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, eb[esi..eei]);
            var s4: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s4);
        },
        .ret => |v| {
            var val = mangleTempName(emitter.interner, v);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var s: []const u8 = "return ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, val);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .load_local => |ll| {
            var result = mangleTempName(emitter.interner, ll.result);
            var name = mangleLocalName(emitter.mangler, emitter.interner, ll.name_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, name);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .store_local => |sl| {
            var val = mangleTempName(emitter.interner, sl.value);
            var name = mangleLocalName(emitter.mangler, emitter.interner, sl.name_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, name);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, val);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .load_global => |lg| {
            var result = mangleTempName(emitter.interner, lg.result);
            var name = mangleLocalName(emitter.mangler, emitter.interner, lg.name_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, name);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .store_global => |sg| {
            var val = mangleTempName(emitter.interner, sg.value);
            var name = mangleLocalName(emitter.mangler, emitter.interner, sg.name_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, name);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, val);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .load_field => |lf| {
            var base = mangleTempName(emitter.interner, lf.base);
            var result = mangleTempName(emitter.interner, lf.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, base);
            var s2: []const u8 = ".f_";
            bufferedWriterWrite(&emitter.writer, s2);
            var fb: [16]u8 = undefined;
            var fl = itoa_mod.itoa(lf.field_id, fb[0..]);
            var fn_idx = @intCast(u32, @intCast(u32, 15) - fl);
            var fn_start: usize = @intCast(usize, fn_idx);
            var fn_end: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, fb[fn_start..fn_end]);
            var s3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .store_field => |sf| {
            var base = mangleTempName(emitter.interner, sf.base);
            var val = mangleTempName(emitter.interner, sf.value);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, base);
            var s: []const u8 = ".f_";
            bufferedWriterWrite(&emitter.writer, s);
            var fb: [16]u8 = undefined;
            var fl = itoa_mod.itoa(sf.field_id, fb[0..]);
            var fn_idx = @intCast(u32, @intCast(u32, 15) - fl);
            var fn_start: usize = @intCast(usize, fn_idx);
            var fn_end: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, fb[fn_start..fn_end]);
            var s2: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s2);
            bufferedWriterWrite(&emitter.writer, val);
            var s3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .load_index => |li| {
            var base = mangleTempName(emitter.interner, li.base);
            var idx = mangleTempName(emitter.interner, li.index);
            var result = mangleTempName(emitter.interner, li.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, base);
            var s2: []const u8 = "[";
            bufferedWriterWrite(&emitter.writer, s2);
            bufferedWriterWrite(&emitter.writer, idx);
            var s3: []const u8 = "];\n";
            bufferedWriterWrite(&emitter.writer, s3);
        },
        .load => |l| {
            var ptr = mangleTempName(emitter.interner, l.ptr);
            var result = mangleTempName(emitter.interner, l.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = *";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, ptr);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .store => |s| {
            var ptr = mangleTempName(emitter.interner, s.ptr);
            var val = mangleTempName(emitter.interner, s.value);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            var sp: []const u8 = "*";
            bufferedWriterWrite(&emitter.writer, sp);
            bufferedWriterWrite(&emitter.writer, ptr);
            var sp2: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, sp2);
            bufferedWriterWrite(&emitter.writer, val);
            var sp3: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, sp3);
        },
        .addr_of => |a| {
            var op = mangleTempName(emitter.interner, a.operand);
            var result = mangleTempName(emitter.interner, a.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = &";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, op);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .binary => |b| {
            var result = mangleTempName(emitter.interner, b.result);
            var lhs = mangleTempName(emitter.interner, b.lhs);
            var rhs = mangleTempName(emitter.interner, b.rhs);
            var op_str = getBinOpStr(b.op);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, lhs);
            var sp: []const u8 = " ";
            bufferedWriterWrite(&emitter.writer, sp);
            bufferedWriterWrite(&emitter.writer, op_str);
            bufferedWriterWrite(&emitter.writer, sp);
            bufferedWriterWrite(&emitter.writer, rhs);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .unary => |u| {
            var result = mangleTempName(emitter.interner, u.result);
            var opd = mangleTempName(emitter.interner, u.operand);
            var op_str = getUnOpStr(u.op);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, op_str);
            bufferedWriterWrite(&emitter.writer, opd);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .int_const => |ic| {
            var result = mangleTempName(emitter.interner, ic.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            var ib: [32]u8 = undefined;
            var il = itoa_mod.itoa(@intCast(u32, ic.value), ib[0..]);
            var is_idx = @intCast(u32, @intCast(u32, 31) - il);
            var is_start: usize = @intCast(usize, is_idx);
            var is_end: usize = @intCast(usize, 31);
            bufferedWriterWrite(&emitter.writer, ib[is_start..is_end]);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .float_const => |fc| {
            var result = mangleTempName(emitter.interner, fc.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = 0.0;\n";
            bufferedWriterWrite(&emitter.writer, s);
        },
        .string_const => |sc| {
            var result = mangleTempName(emitter.interner, sc.result);
            var str = interner_mod.stringInternerGet(emitter.interner, sc.string_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = \"";
            bufferedWriterWrite(&emitter.writer, s);
            var si: usize = @intCast(usize, 0);
            while (si < str.len) : (si += @intCast(usize, 1)) {
                if (str[si] == @intCast(u8, '"') or str[si] == @intCast(u8, '\\')) {
                    var bs: []const u8 = "\\";
                    bufferedWriterWrite(&emitter.writer, bs);
                }
                var ch: [1]u8 = undefined;
                ch[0] = str[si];
                bufferedWriterWrite(&emitter.writer, ch[0..1]);
            }
            var s2: []const u8 = "\";\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .null_const => |nc| {
            var result = mangleTempName(emitter.interner, nc.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = NULL;\n";
            bufferedWriterWrite(&emitter.writer, s);
        },
        .bool_const => |bc| {
            var result = mangleTempName(emitter.interner, bc.result);
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
            var result = mangleTempName(emitter.interner, uc.result);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = 0;\n";
            bufferedWriterWrite(&emitter.writer, s);
        },
        .call => |c| {
            var result = mangleTempName(emitter.interner, c.result);
            var callee = mangleTempName(emitter.interner, c.callee);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, result);
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            bufferedWriterWrite(&emitter.writer, callee);
            var sp: []const u8 = "(";
            bufferedWriterWrite(&emitter.writer, sp);
            var ai: u32 = @intCast(u32, 0);
            while (ai < c.args_count) : (ai += @intCast(u32, 1)) {
                if (ai > @intCast(u32, 0)) {
                    var sc: []const u8 = ", ";
                    bufferedWriterWrite(&emitter.writer, sc);
                }
                var arg = mangleTempName(emitter.interner, c.args_start + ai);
                bufferedWriterWrite(&emitter.writer, arg);
            }
            var s2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        else => {},
    }
}

pub fn emitFunctionBody(emitter: *C89Emitter, lir_fn: *LirFunction) void {
    var bb_idx: usize = @intCast(usize, 0);
    while (bb_idx < lir_fn.blocks.len) : (bb_idx += @intCast(usize, 1)) {
        var bb = &lir_fn.blocks.items[bb_idx];
        if (bb.id > @intCast(u32, 0)) {
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
        var inst_idx: usize = @intCast(usize, 0);
        while (inst_idx < bb.insts.len) : (inst_idx += @intCast(usize, 1)) {
            emitInst(emitter, bb.insts.items[inst_idx]);
        }
    }
    emitter.indent -= @intCast(u32, 1);
    var cl: []const u8 = "}\n\n";
    bufferedWriterWrite(&emitter.writer, cl);
}
