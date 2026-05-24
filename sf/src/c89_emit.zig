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
const format_mod = @import("util/format.zig");
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
    pal.stderr_write(buf[sbase .. send]);
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
    if (hash_mod.u64ToU32MapGet(&self.cache, key)) |cached| {
        return cached;
    }
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
    if (ty.kind == TypeKind.enum_type) {
        var ep = reg.en_items[@intCast(usize, ty.payload_idx)];
        return getCTypeName(reg, mangler, ep.backing_type);
    }
    if (ty.kind == TypeKind.array_type) {
        var ap = reg.array_items[@intCast(usize, ty.payload_idx)];
        return getCTypeName(reg, mangler, ap.elem);
    }
    if (ty.kind == TypeKind.ptr_type or ty.kind == TypeKind.many_ptr_type) {
        var pp = reg.ptr_items[@intCast(usize, ty.payload_idx)];
        var et = reg.types_items[@intCast(usize, pp.base)];
        if (et.kind == TypeKind.u8_type) { var s: []const u8 = "unsigned char*"; return s; }
        if (et.kind == TypeKind.u32_type) { var s: []const u8 = "unsigned int*"; return s; }
        if (et.kind == TypeKind.i32_type) { var s: []const u8 = "int*"; return s; }
        if (et.kind == TypeKind.f64_type) { var s: []const u8 = "double*"; return s; }
        if (et.kind == TypeKind.c_char_type) { var s: []const u8 = "char*"; return s; }
        if (et.kind == TypeKind.usize_type) { var s: []const u8 = "unsigned int*"; return s; }
        var s: []const u8 = "void*"; return s;
    }
    if (ty.kind == TypeKind.undefined_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.integer_literal_type) { var s: []const u8 = "int"; return s; }
    if (ty.kind == TypeKind.null_type) { var s: []const u8 = "int"; return s; }
    var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    return interner_mod.stringInternerGet(mangler.interner, mid);
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

pub fn emitZigPalC(writer: *BufferedWriter) void {
    var h01: []const u8 = "/* zig_pal.c - Platform Abstraction Layer (generated by zig1) */\n#ifndef ZIG_PAL_C\n#define ZIG_PAL_C\n#include \"zig_compat.h\"\n\n#ifdef _WIN32\n#include <windows.h>\n#else\n#include <stdlib.h>\n#include <string.h>\n#include <unistd.h>\n#endif\n\n"; bufferedWriterWrite(writer, h01);
    var h02: []const u8 = "#ifdef _WIN32\ntypedef void* PlatFile;\n#define PLAT_INVALID_FILE ((void*)(isize)-1)\n#else\ntypedef int PlatFile;\n#define PLAT_INVALID_FILE (-1)\n#endif\n\n"; bufferedWriterWrite(writer, h02);
    var h03: []const u8 = "static usize pal_strlen(const char* s)\n{\n#ifdef _WIN32\n    const char* p = s;\n    while (*p) p++;\n    return (usize)(p - s);\n#else\n    return (usize)strlen(s);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h03);
    var h04: []const u8 = "static void pal_memcpy(void* dst, const void* src, usize n)\n{\n#ifdef _WIN32\n    char* d = (char*)dst;\n    const char* s = (const char*)src;\n    while (n--) *d++ = *s++;\n#else\n    memcpy(dst, src, (size_t)n);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h04);
    var h05: []const u8 = "static void pal_reverse(char* buf, int len)\n{\n    int i = 0;\n    int j = len - 1;\n    while (i < j) {\n        char t = buf[i];\n        buf[i] = buf[j];\n        buf[j] = t;\n        i++;\n        j--;\n    }\n}\n\n"; bufferedWriterWrite(writer, h05);
    var h06: []const u8 = "static int pal_u64_to_str_buf(u64 value, char* buf, int bufsize)\n{\n    int i;\n    if (bufsize <= 0) return 0;\n    if (value == 0) {\n        buf[0] = '0';\n        buf[1] = '\\0';\n        return 1;\n    }\n    i = 0;\n    while (value > 0 && i < bufsize - 1) {\n        buf[i++] = '0' + (char)(value % 10);\n        value /= 10;\n    }\n    buf[i] = '\\0';\n    pal_reverse(buf, i);\n    return i;\n}\n\n"; bufferedWriterWrite(writer, h06);
    var h07: []const u8 = "void pal_print_stderr(const char* msg, usize len)\n{\n#ifdef _WIN32\n    HANDLE h;\n    DWORD written;\n    if (!msg || len == 0) return;\n    h = GetStdHandle(STD_ERROR_HANDLE);\n    if (h == INVALID_HANDLE_VALUE || h == NULL) return;\n    if (!WriteConsoleA(h, msg, (DWORD)len, &written, NULL))\n        WriteFile(h, msg, (DWORD)len, &written, NULL);\n#else\n    write(2, msg, (size_t)len);\n#endif\n}\n\n"; bufferedWriterWrite(writer, h07);
    var h08: []const u8 = "void pal_abort(void)\n{\n#ifdef _WIN32\n    TerminateProcess(GetCurrentProcess(), 3);\n#else\n    abort();\n#endif\n}\n\n"; bufferedWriterWrite(writer, h08);
    var h09: []const u8 = "int pal_i64_to_str(i64 value, char* buf, int bufsize)\n{\n    u64 uval;\n    int is_neg;\n    int dlen;\n    if (bufsize <= 0) return 0;\n    if (value == 0) {\n        buf[0] = '0';\n        buf[1] = '\\0';\n        return 1;\n    }\n    is_neg = (value < 0) ? 1 : 0;\n    uval = is_neg ? (u64)(-(value + 1)) + 1 : (u64)value;\n    if (is_neg) {\n        buf[0] = '-';\n        dlen = pal_u64_to_str_buf(uval, buf + 1, bufsize - 1);\n        return dlen + 1;\n    }\n    return pal_u64_to_str_buf(uval, buf, bufsize);\n}\n\n"; bufferedWriterWrite(writer, h09);
    var h10: []const u8 = "int pal_u64_to_str(u64 value, char* buf, int bufsize)\n{\n    return pal_u64_to_str_buf(value, buf, bufsize);\n}\n\n"; bufferedWriterWrite(writer, h10);
    var h11: []const u8 = "int pal_f64_to_str(f64 value, char* buf, int bufsize)\n{\n    int int_len;\n    int i;\n    f64 frac_part;\n    i64 int_part;\n    u64 frac_int;\n    int pos;\n    if (bufsize < 2) {\n        if (bufsize == 1) buf[0] = '\\0';\n        return 0;\n    }\n    if (value < 0.0) {\n        buf[0] = '-';\n        pos = 1;\n        value = -value;\n    } else {\n        pos = 0;\n    }\n    int_part = (i64)value;\n    int_len = pal_i64_to_str(int_part, buf + pos, bufsize - pos);\n    if (int_len <= 0) return 0;\n    pos += int_len;\n    buf[pos++] = '.';\n    frac_part = value - (f64)int_part;\n    i = 0;\n    while (i < 6 && pos < bufsize - 1) {\n        frac_part *= 10.0;\n        frac_int = (u64)frac_part;\n        buf[pos++] = '0' + (char)(frac_int % 10);\n        frac_part -= (f64)frac_int;\n        i++;\n    }\n    while (pos > 0 && buf[pos - 1] == '0') pos--;\n    if (buf[pos - 1] == '.') pos++;\n    buf[pos] = '\\0';\n    return pos;\n}\n\n"; bufferedWriterWrite(writer, h11);
    var h12: []const u8 = "#if defined(_WIN32) && defined(ZIG_NO_CRT)\nint main(void);\nvoid __cdecl mainCRTStartup(void)\n{\n    int result = main();\n    ExitProcess((UINT)result);\n}\n#endif\n\n#endif /* ZIG_PAL_C */\n"; bufferedWriterWrite(writer, h12);
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
    var sf1: []const u8 = "\t"; bufferedWriterWrite(&emitter.writer, sf1);
    var tag_ctype = getCTypeName(reg, emitter.mangler, tp.tag_type);
    bufferedWriterWrite(&emitter.writer, tag_ctype);
    var sf2: []const u8 = " tag;\n"; bufferedWriterWrite(&emitter.writer, sf2);
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
    if (ty.kind == TypeKind.enum_type) { emitEnumType(emitter, tid); return; }
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
    var i: u16 = @intCast(u16, 0);
    while (i < ep.members_count) : (i += @intCast(u16, 1)) {
        var def: []const u8 = "#define "; bufferedWriterWrite(&emitter.writer, def);
        bufferedWriterWrite(&emitter.writer, mangled_name);
        var us: []const u8 = "_"; bufferedWriterWrite(&emitter.writer, us);
        var mi: u32 = @intCast(u32, i);
        var mname = interner_mod.stringInternerGet(emitter.interner, mi);
        bufferedWriterWrite(&emitter.writer, mname);
        var eq: []const u8 = " "; bufferedWriterWrite(&emitter.writer, eq);
        var d: []const u8 = "0\n"; bufferedWriterWrite(&emitter.writer, d);
    }
    var nl: []const u8 = "\n"; bufferedWriterWrite(&emitter.writer, nl);
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

pub fn emitFunctionSignature(emitter: *C89Emitter, lir_fn: *LirFunction) void {
    var orig = interner_mod.stringInternerGet(emitter.interner, lir_fn.name_id);
    var is_main: u8 = @intCast(u8, 0);
    if (orig.len == @intCast(usize, 4)) {
        if (orig[0] == 'm' and orig[1] == 'a' and orig[2] == 'i' and orig[3] == 'n') is_main = @intCast(u8, 1);
    }
    var fn_mid = nameManglerMangle(emitter.mangler, lir_fn.name_id, @intCast(u8, 0), lir_fn.module_id);
    var fn_name = interner_mod.stringInternerGet(emitter.interner, fn_mid);
    if (is_main == @intCast(u8, 1) and lir_fn.is_pub == @intCast(u8, 1)) {
        var mn: []const u8 = "main";
        fn_name = mn;
    }
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

fn emitFunctionForwardDecl(emitter: *C89Emitter, lir_fn: LirFunction) void {
    var ret_c = getCTypeName(emitter.registry, emitter.mangler, lir_fn.return_type);
    bufferedWriterWrite(&emitter.writer, ret_c);
    var sp: []const u8 = " ";
    bufferedWriterWrite(&emitter.writer, sp);
    var fn_mid = nameManglerMangle(emitter.mangler, lir_fn.name_id, @intCast(u8, 0), lir_fn.module_id);
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
        }
    }
    var rp: []const u8 = ");\n";
    bufferedWriterWrite(&emitter.writer, rp);
}

fn emitModuleHeader(emitter: *C89Emitter, name: []const u8, fns: []LirFunction) void {
    var s1: []const u8 = "/* Module: ";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, name);
    var s2: []const u8 = " */\n#include \"zig_compat.h\"\n#include \"zig_special_types.h\"\n\n/* Forward declarations */\n";
    bufferedWriterWrite(&emitter.writer, s2);
    var i: usize = @intCast(usize, 0);
    while (i < fns.len) : (i += @intCast(usize, 1)) {
        if (fns[i].is_extern == @intCast(u8, 0)) {
            emitFunctionForwardDecl(emitter, fns[i]);
        }
    }
    var nl: []const u8 = "\n";
    bufferedWriterWrite(&emitter.writer, nl);
}

fn emitModuleFooter(emitter: *C89Emitter) void {
    var s: []const u8 = "/* EOF */\n";
    bufferedWriterWrite(&emitter.writer, s);
}

pub fn emitModule(emitter: *C89Emitter, name: []const u8, fns: []LirFunction) void {
    var tbuf: [64]u8 = undefined;
    var ts1: []const u8 = "FMT0:"; pal.stderr_write(ts1);
    var tf0 = format_mod.formatF64(0.0, tbuf[0..], 64);
    pal.stderr_write(tf0);
    var ts2: []const u8 = " FMT4:"; pal.stderr_write(ts2);
    var tf4 = format_mod.formatF64(4.0, tbuf[0..], 64);
    pal.stderr_write(tf4);
    var ts3: []const u8 = " FMT3.5:"; pal.stderr_write(ts3);
    var tf35 = format_mod.formatF64(3.5, tbuf[0..], 64);
    pal.stderr_write(tf35);
    var tsn: []const u8 = "\n"; pal.stderr_write(tsn);
    emitModuleHeader(emitter, name, fns);
    var i: usize = @intCast(usize, 0);
    while (i < fns.len) : (i += @intCast(usize, 1)) {
        var func = fns[i];
        if (func.is_extern == @intCast(u8, 0)) {
            emitFunctionSignature(emitter, &func);
            emitHoistedDecls(emitter, &func);
            emitFunctionBody(emitter, &func);
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
    var i: usize = @intCast(usize, 0);
    while (i < lir_fn.hoisted_temps.len) : (i += @intCast(usize, 1)) {
        var td = lir_fn.hoisted_temps.items[i];
        var ty = emitter.registry.types_items[@intCast(usize, td.type_id)];
        var c_type = getCTypeName(emitter.registry, emitter.mangler, td.type_id);
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, c_type);
        var sp: []const u8 = " ";
        bufferedWriterWrite(&emitter.writer, sp);
        var tn = mangleTempName(emitter.interner, td.temp_id);
        bufferedWriterWrite(&emitter.writer, tn);
        if (ty.kind == TypeKind.array_type) {
            var ap_ind: usize = @intCast(usize, ty.payload_idx);
            var ap_len: u32 = emitter.registry.array_items[ap_ind].length;
            var lb: []const u8 = "[";
            bufferedWriterWrite(&emitter.writer, lb);
            var nb: [16]u8 = undefined;
            var nb_sl: []u8 = nb[0..@intCast(usize, 16)];
            var nl: u32 = itoa_mod.itoa(ap_len, nb_sl);
            var nstart: u32 = @intCast(u32, 15) - nl;
            var ns: usize = @intCast(usize, nstart);
            var ne: usize = @intCast(usize, 15);
            bufferedWriterWrite(&emitter.writer, nb[ns..ne]);
            var rb: []const u8 = "]";
            bufferedWriterWrite(&emitter.writer, rb);
        }
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

fn getCheckedCastFnName(reg: *TypeRegistry, tid: u32) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    if (ty.kind == TypeKind.i8_type) { var s: []const u8 = "__bootstrap_checked_cast_i8"; return s; }
    if (ty.kind == TypeKind.i16_type) { var s: []const u8 = "__bootstrap_checked_cast_i16"; return s; }
    if (ty.kind == TypeKind.i32_type) { var s: []const u8 = "__bootstrap_checked_cast_i32"; return s; }
    if (ty.kind == TypeKind.i64_type) { var s: []const u8 = "__bootstrap_checked_cast_i64"; return s; }
    if (ty.kind == TypeKind.u8_type) { var s: []const u8 = "__bootstrap_checked_cast_u8"; return s; }
    if (ty.kind == TypeKind.c_char_type) { var s: []const u8 = "__bootstrap_checked_cast_u8"; return s; }
    if (ty.kind == TypeKind.u16_type) { var s: []const u8 = "__bootstrap_checked_cast_u16"; return s; }
    if (ty.kind == TypeKind.u32_type) { var s: []const u8 = "__bootstrap_checked_cast_u32"; return s; }
    if (ty.kind == TypeKind.u64_type) { var s: []const u8 = "__bootstrap_checked_cast_u64"; return s; }
    { var s: []const u8 = "__bootstrap_checked_cast_u32"; return s; }
}

fn getPrintFnName(reg: *TypeRegistry, tid: u32) []const u8 {
    var ty = reg.types_items[@intCast(usize, tid)];
    if (ty.kind == TypeKind.u32_type) { var s: []const u8 = "__bootstrap_print_u32"; return s; }
    if (ty.kind == TypeKind.i64_type) { var s: []const u8 = "__bootstrap_print_i64"; return s; }
    if (ty.kind == TypeKind.u64_type) { var s: []const u8 = "__bootstrap_print_u64"; return s; }
    if (ty.kind == TypeKind.f64_type) { var s: []const u8 = "__bootstrap_print_f64"; return s; }
    if (ty.kind == TypeKind.bool_type) { var s: []const u8 = "__bootstrap_print_bool"; return s; }
    if (ty.kind == TypeKind.u8_type) { var s: []const u8 = "__bootstrap_print_char"; return s; }
    if (ty.kind == TypeKind.slice_type) { var s: []const u8 = "__bootstrap_print_str"; return s; }
    { var s: []const u8 = "__bootstrap_print_i32"; return s; }
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
        .decl_local => |dl| {
            var ty = emitter.registry.types_items[@intCast(usize, dl.type_id)];
            var c_type = getCTypeName(emitter.registry, emitter.mangler, dl.type_id);
            var name = mangleLocalName(emitter.mangler, emitter.interner, dl.name_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, c_type);
            var sp: []const u8 = " ";
            bufferedWriterWrite(&emitter.writer, sp);
            bufferedWriterWrite(&emitter.writer, name);
        if (ty.kind == TypeKind.array_type) {
                var ap_len: u32 = emitter.registry.array_items[@intCast(usize, ty.payload_idx)].length;
                var lb: []const u8 = "[";
                bufferedWriterWrite(&emitter.writer, lb);
                var nb: [16]u8 = undefined;
                var nb_sl: []u8 = nb[0..@intCast(usize, 16)];
                var nl: u32 = itoa_mod.itoa(ap_len, nb_sl);
                var nstart: u32 = @intCast(u32, 15) - nl;
                var ns2: usize = @intCast(usize, nstart);
                var ne2: usize = @intCast(usize, 15);
                bufferedWriterWrite(&emitter.writer, nb[ns2..ne2]);
                var rb: []const u8 = "]";
                bufferedWriterWrite(&emitter.writer, rb);
            }
            var sm: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, sm);
        },
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
            var fn_idx: u32 = @intCast(u32, @intCast(u32, 15) - fl);
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
            var ns: u32 = @intCast(u32, @intCast(u32, 15) - nl);
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
            var fn_idx: u32 = @intCast(u32, @intCast(u32, 15) - fl);
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
            var fn_idx: u32 = @intCast(u32, @intCast(u32, 15) - fl);
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
            var s: []const u8 = " = ";
            bufferedWriterWrite(&emitter.writer, s);
            var dx2_buf: [64]u8 = undefined;
            var dx2 = format_mod.formatF64(fc.value, dx2_buf[0..], 64);
            var dx2s: []const u8 = "D2:"; pal.stderr_write(dx2s);
            pal.stderr_write(dx2);
            var dx2n: []const u8 = "\n"; pal.stderr_write(dx2n);
            var buf: [64]u8 = undefined;
            var fb = format_mod.formatF64(fc.value, buf[0..], 64);
            bufferedWriterWrite(&emitter.writer, fb);
            var s2: []const u8 = ";\n";
            bufferedWriterWrite(&emitter.writer, s2);
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
        .call_direct => |c| {
            var mangled_id = nameManglerMangle(emitter.mangler, c.name_id, @intCast(u8, 1), c.module_id);
            var fn_name = interner_mod.stringInternerGet(emitter.interner, mangled_id);
            bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
            bufferedWriterWrite(&emitter.writer, fn_name);
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
        .switch_br => |s| {
            var s1: []const u8 = "switch (";
            bufferedWriterWrite(&emitter.writer, s1);
            var cond = mangleTempName(emitter.interner, s.cond);
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
            var dst = mangleTempName(emitter.interner, w.result);
            var src = mangleTempName(emitter.interner, w.value);
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
        },
        .int_cast => |c| {
            var dst = mangleTempName(emitter.interner, c.result);
            var src = mangleTempName(emitter.interner, c.value);
            var ctype = getCTypeName(emitter.registry, emitter.mangler, c.target);
            if (c.is_checked != @intCast(u8, 0)) {
                var fn_name = getCheckedCastFnName(emitter.registry, c.target);
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
        },
        .make_slice => |s| {
            var dst = mangleTempName(emitter.interner, s.result);
            var ptr = mangleTempName(emitter.interner, s.ptr);
            var len = mangleTempName(emitter.interner, s.len);
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
            var s1: []const u8 = "__bootstrap_print(";
            bufferedWriterWrite(&emitter.writer, s1);
            emitCStringLiteral(&emitter.writer, str);
            var s2: []const u8 = ");\n";
            bufferedWriterWrite(&emitter.writer, s2);
        },
        .print_val => |p| {
            var val = mangleTempName(emitter.interner, p.value);
            var fn_name = getPrintFnName(emitter.registry, p.type_id);
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
    var l012: []const u8 = "void __bootstrap_panic(const char* msg) {\n";
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
    var l020: []const u8 = "void __bootstrap_print(const char* s) { if (s) pal_print_stderr(s, strlen(s)); }\n";
    bufferedWriterWrite(writer, l020);
    var l021: []const u8 = "void __bootstrap_print_len(const char* s, unsigned int len) { if (s && len) pal_print_stderr(s, len); }\n";
    bufferedWriterWrite(writer, l021);
    var l022: []const u8 = "\n";
    bufferedWriterWrite(writer, l022);
    var l023: []const u8 = "void __bootstrap_print_i32(int val) {\n";
    bufferedWriterWrite(writer, l023);
    var l024: []const u8 = "    char buf[16];\n";
    bufferedWriterWrite(writer, l024);
    var l025: []const u8 = "    pal_i64_to_str((long long)val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l025);
    var l026: []const u8 = "    __bootstrap_print(buf);\n";
    bufferedWriterWrite(writer, l026);
    var l027: []const u8 = "}\n";
    bufferedWriterWrite(writer, l027);
    var l028: []const u8 = "\n";
    bufferedWriterWrite(writer, l028);
    var l029: []const u8 = "void __bootstrap_print_u32(unsigned int val) {\n";
    bufferedWriterWrite(writer, l029);
    var l030: []const u8 = "    char buf[16];\n";
    bufferedWriterWrite(writer, l030);
    var l031: []const u8 = "    pal_u64_to_str((unsigned long long)val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l031);
    var l032: []const u8 = "    __bootstrap_print(buf);\n";
    bufferedWriterWrite(writer, l032);
    var l033: []const u8 = "}\n";
    bufferedWriterWrite(writer, l033);
    var l034: []const u8 = "\n";
    bufferedWriterWrite(writer, l034);
    var l035: []const u8 = "void __bootstrap_print_i64(long long val) {\n";
    bufferedWriterWrite(writer, l035);
    var l036: []const u8 = "    char buf[24];\n";
    bufferedWriterWrite(writer, l036);
    var l037: []const u8 = "    pal_i64_to_str(val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l037);
    var l038: []const u8 = "    __bootstrap_print(buf);\n";
    bufferedWriterWrite(writer, l038);
    var l039: []const u8 = "}\n";
    bufferedWriterWrite(writer, l039);
    var l040: []const u8 = "\n";
    bufferedWriterWrite(writer, l040);
    var l041: []const u8 = "void __bootstrap_print_u64(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l041);
    var l042: []const u8 = "    char buf[24];\n";
    bufferedWriterWrite(writer, l042);
    var l043: []const u8 = "    pal_u64_to_str(val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l043);
    var l044: []const u8 = "    __bootstrap_print(buf);\n";
    bufferedWriterWrite(writer, l044);
    var l045: []const u8 = "}\n";
    bufferedWriterWrite(writer, l045);
    var l046: []const u8 = "\n";
    bufferedWriterWrite(writer, l046);
    var l047: []const u8 = "void __bootstrap_print_f64(double val) {\n";
    bufferedWriterWrite(writer, l047);
    var l048: []const u8 = "    char buf[32];\n";
    bufferedWriterWrite(writer, l048);
    var l049: []const u8 = "    pal_f64_to_str(val, buf, sizeof(buf));\n";
    bufferedWriterWrite(writer, l049);
    var l050: []const u8 = "    __bootstrap_print(buf);\n";
    bufferedWriterWrite(writer, l050);
    var l051: []const u8 = "}\n";
    bufferedWriterWrite(writer, l051);
    var l052: []const u8 = "\n";
    bufferedWriterWrite(writer, l052);
    var l053: []const u8 = "void __bootstrap_print_bool(int val) {\n";
    bufferedWriterWrite(writer, l053);
    var l054: []const u8 = "    if (val) __bootstrap_print(\"true\");\n";
    bufferedWriterWrite(writer, l054);
    var l055: []const u8 = "    else __bootstrap_print(\"false\");\n";
    bufferedWriterWrite(writer, l055);
    var l056: []const u8 = "}\n";
    bufferedWriterWrite(writer, l056);
    var l057: []const u8 = "\n";
    bufferedWriterWrite(writer, l057);
    var l058: []const u8 = "void __bootstrap_print_char(unsigned char val) { char c = (char)val; pal_print_stderr(&c, 1); }\n";
    bufferedWriterWrite(writer, l058);
    var l059: []const u8 = "\n";
    bufferedWriterWrite(writer, l059);
    var l060: []const u8 = "void __bootstrap_print_str(const unsigned char* ptr, unsigned int len) {\n";
    bufferedWriterWrite(writer, l060);
    var l061: []const u8 = "    if (ptr && len) pal_print_stderr((const char*)ptr, len);\n";
    bufferedWriterWrite(writer, l061);
    var l062: []const u8 = "}\n";
    bufferedWriterWrite(writer, l062);
    var l063: []const u8 = "\n";
    bufferedWriterWrite(writer, l063);
    var l064: []const u8 = "/* Checked conversions (u64 -> target type) */\n";
    bufferedWriterWrite(writer, l064);
    var l065: []const u8 = "\n";
    bufferedWriterWrite(writer, l065);
    var l066: []const u8 = "signed char __bootstrap_checked_cast_i8(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l066);
    var l067: []const u8 = "    if (val > 127ULL) __bootstrap_panic(\"int cast overflow for i8\");\n";
    bufferedWriterWrite(writer, l067);
    var l068: []const u8 = "    return (signed char)val;\n";
    bufferedWriterWrite(writer, l068);
    var l069: []const u8 = "}\n";
    bufferedWriterWrite(writer, l069);
    var l070: []const u8 = "\n";
    bufferedWriterWrite(writer, l070);
    var l071: []const u8 = "unsigned char __bootstrap_checked_cast_u8(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l071);
    var l072: []const u8 = "    if (val > 255ULL) __bootstrap_panic(\"int cast overflow for u8\");\n";
    bufferedWriterWrite(writer, l072);
    var l073: []const u8 = "    return (unsigned char)val;\n";
    bufferedWriterWrite(writer, l073);
    var l074: []const u8 = "}\n";
    bufferedWriterWrite(writer, l074);
    var l075: []const u8 = "\n";
    bufferedWriterWrite(writer, l075);
    var l076: []const u8 = "short __bootstrap_checked_cast_i16(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l076);
    var l077: []const u8 = "    if (val > 32767ULL) __bootstrap_panic(\"int cast overflow for i16\");\n";
    bufferedWriterWrite(writer, l077);
    var l078: []const u8 = "    return (short)val;\n";
    bufferedWriterWrite(writer, l078);
    var l079: []const u8 = "}\n";
    bufferedWriterWrite(writer, l079);
    var l080: []const u8 = "\n";
    bufferedWriterWrite(writer, l080);
    var l081: []const u8 = "unsigned short __bootstrap_checked_cast_u16(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l081);
    var l082: []const u8 = "    if (val > 65535ULL) __bootstrap_panic(\"int cast overflow for u16\");\n";
    bufferedWriterWrite(writer, l082);
    var l083: []const u8 = "    return (unsigned short)val;\n";
    bufferedWriterWrite(writer, l083);
    var l084: []const u8 = "}\n";
    bufferedWriterWrite(writer, l084);
    var l085: []const u8 = "\n";
    bufferedWriterWrite(writer, l085);
    var l086: []const u8 = "int __bootstrap_checked_cast_i32(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l086);
    var l087: []const u8 = "    if (val > 2147483647ULL) __bootstrap_panic(\"int cast overflow for i32\");\n";
    bufferedWriterWrite(writer, l087);
    var l088: []const u8 = "    return (int)val;\n";
    bufferedWriterWrite(writer, l088);
    var l089: []const u8 = "}\n";
    bufferedWriterWrite(writer, l089);
    var l090: []const u8 = "\n";
    bufferedWriterWrite(writer, l090);
    var l091: []const u8 = "unsigned int __bootstrap_checked_cast_u32(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l091);
    var l092: []const u8 = "    if (val > 4294967295ULL) __bootstrap_panic(\"int cast overflow for u32\");\n";
    bufferedWriterWrite(writer, l092);
    var l093: []const u8 = "    return (unsigned int)val;\n";
    bufferedWriterWrite(writer, l093);
    var l094: []const u8 = "}\n";
    bufferedWriterWrite(writer, l094);
    var l095: []const u8 = "\n";
    bufferedWriterWrite(writer, l095);
    var l096: []const u8 = "long long __bootstrap_checked_cast_i64(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l096);
    var l097: []const u8 = "    if (val > 9223372036854775807ULL) __bootstrap_panic(\"int cast overflow for i64\");\n";
    bufferedWriterWrite(writer, l097);
    var l098: []const u8 = "    return (long long)val;\n";
    bufferedWriterWrite(writer, l098);
    var l099: []const u8 = "}\n";
    bufferedWriterWrite(writer, l099);
    var l100: []const u8 = "\n";
    bufferedWriterWrite(writer, l100);
    var l101: []const u8 = "unsigned long long __bootstrap_checked_cast_u64(unsigned long long val) {\n";
    bufferedWriterWrite(writer, l101);
    var l102: []const u8 = "    return val;\n";
    bufferedWriterWrite(writer, l102);
    var l103: []const u8 = "}\n";
    bufferedWriterWrite(writer, l103);
}

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
