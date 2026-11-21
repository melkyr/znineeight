// P3-M1: compiler-side debug map (Phase 2 Project 3).
//
// Two independent pieces:
//   1. DebugSpanStore — a parallel per-function spill of `DebugSpanEntry`
//      (bb/inst ordinal -> AST span_start), keyed by LirSlot.disk_offset.
//      It lives outside lir_stream so the LIR record format / expected_len are
//      untouched. Lowering appends one function's spans before the scratch
//      reset; emission reads exactly one function's spans at a time.
//   2. DebugMapWriter — the three streamed sidecars (`<stem>.z98dbg.syms`,
//      `.lines`, `.cnames`). `.lines` is group-per-out_file with RLE; each
//      group's run count is patched by absolute seek at group end. `.syms` /
//      `.cnames` are sorted in memory (one small record per symbol) and
//      written at close. Inst rows never accumulate in RAM.
//
// Byte layout (little-endian, binding):
//   header (all files): 8-byte magic + u32 version=1 + u32 record_count +
//                       u32 file_total_len (both counts patched at close)
//   .syms record:  u8 kind, u32 src_line, str16 src_name, str16 module_stem,
//                  str16 src_file
//   .lines group:  str16 src_file, str16 out_file, u32 run_count,
//                  runs: u32 src_line, u32 out_line_start, u32 out_count
//   .cnames rec:   str16 src_name, str16 mangled_name

const alloc_mod = @import("allocator.zig");
const Sand = @import("allocator.zig").Sand;
const spill_mod = @import("spill_store.zig");
const lir_mod = @import("lir.zig");
const sm_mod = @import("source_manager.zig");
const nm_mod = @import("name_mangler.zig");
const interner_mod = @import("string_interner.zig");
const mr_mod = @import("module_registry.zig");
const type_mod = @import("type_registry.zig");

pub const HEADER_LEN: u32 = 20;
pub const VERSION: u32 = 1;

fn magicSyms() []const u8 {
    var s: []const u8 = "Z98DBGsy";
    return s;
}
fn magicLines() []const u8 {
    var s: []const u8 = "Z98DBGln";
    return s;
}
fn magicCnames() []const u8 {
    var s: []const u8 = "Z98DBGcn";
    return s;
}

fn minUsize(a: usize, b: usize) usize {
    if (a < b) return a;
    return b;
}

fn strCompare(a: []const u8, b: []const u8) i32 {
    var n = minUsize(a.len, b.len);
    var i: usize = @intCast(usize, 0);
    while (i < n) : (i += @intCast(usize, 1)) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

// ---------------------------------------------------------------------------
// Span spill
// ---------------------------------------------------------------------------

pub const DebugFnSpanIndex = struct {
    disk_offset: u32,
    spill_offset: u32,
    count: u32,
};

pub const DebugSpanStore = struct {
    spill: spill_mod.SpillStore,
    index_items: [*]DebugFnSpanIndex,
    index_len: usize,
    index_capacity: usize,
    alloc: *Sand,
    enabled: u8,
};

pub fn debugSpanStoreInit() DebugSpanStore {
    return DebugSpanStore{
        .spill = spill_mod.spillStoreInit(),
        .index_items = undefined,
        .index_len = @intCast(usize, 0),
        .index_capacity = @intCast(usize, 0),
        .alloc = undefined,
        .enabled = @intCast(u8, 0),
    };
}

fn debugSpanIndexEnsure(self: *DebugSpanStore, need: usize) void {
    if (need <= self.index_capacity) return;
    var cap = self.index_capacity;
    if (cap == @intCast(usize, 0)) cap = @intCast(usize, 16);
    while (cap < need) : (cap *= @intCast(usize, 2)) {}
    var raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, @sizeOf(DebugFnSpanIndex)) * cap, @intCast(usize, 4)) catch unreachable;
    var dst = @ptrCast([*]DebugFnSpanIndex, raw);
    var i: usize = @intCast(usize, 0);
    while (i < self.index_len) : (i += @intCast(usize, 1)) {
        dst[i] = self.index_items[i];
    }
    self.index_items = dst;
    self.index_capacity = cap;
}

pub fn debugSpanStoreOpen(self: *DebugSpanStore, alloc: *Sand, path: []const u8) void {
    self.alloc = alloc;
    var mode: [*]const u8 = "w+b";
    spill_mod.spillOpen(&self.spill, spill_mod.SpillBackend.disk, path, alloc, mode);
    self.index_len = @intCast(usize, 0);
    self.enabled = @intCast(u8, 1);
}

fn debugSpanSort(spans: []lir_mod.DebugSpanEntry) void {
    var i: usize = @intCast(usize, 1);
    while (i < spans.len) : (i += @intCast(usize, 1)) {
        var key = spans[i];
        var j: usize = i;
        while (j > @intCast(usize, 0)) {
            var prev = spans[j - @intCast(usize, 1)];
            var after = prev.bb > key.bb or (prev.bb == key.bb and prev.inst > key.inst);
            if (!after) break;
            spans[j] = prev;
            j -= @intCast(usize, 1);
        }
        spans[j] = key;
    }
}

fn debugStoreWriteU32(self: *DebugSpanStore, value: u32) void {
    var b: [4]u8 = undefined;
    b[0] = @intCast(u8, value & @intCast(u32, 0xFF));
    b[1] = @intCast(u8, (value >> @intCast(u32, 8)) & @intCast(u32, 0xFF));
    b[2] = @intCast(u8, (value >> @intCast(u32, 16)) & @intCast(u32, 0xFF));
    b[3] = @intCast(u8, (value >> @intCast(u32, 24)) & @intCast(u32, 0xFF));
    spill_mod.spillWriteAt(&self.spill, self.spill.cur, b[0..]);
}

pub fn debugSpanStoreAppend(self: *DebugSpanStore, disk_offset: u32, spans: []lir_mod.DebugSpanEntry) void {
    if (self.enabled == @intCast(u8, 0) or spans.len == @intCast(usize, 0)) return;
    debugSpanSort(spans);
    debugSpanIndexEnsure(self, self.index_len + @intCast(usize, 1));
    var rec = DebugFnSpanIndex{
        .disk_offset = disk_offset,
        .spill_offset = self.spill.cur,
        .count = @intCast(u32, spans.len),
    };
    debugStoreWriteU32(self, @intCast(u32, spans.len));
    spill_mod.spillWriteAt(&self.spill, self.spill.cur, @ptrCast([*]const u8, spans.ptr)[0 .. spans.len * @intCast(usize, @sizeOf(lir_mod.DebugSpanEntry))]);
    self.index_items[self.index_len] = rec;
    self.index_len += @intCast(usize, 1);
}

pub fn debugSpanStoreLookup(self: *DebugSpanStore, disk_offset: u32) ?DebugFnSpanIndex {
    if (self.enabled == @intCast(u8, 0)) return null;
    var i: usize = @intCast(usize, 0);
    while (i < self.index_len) : (i += @intCast(usize, 1)) {
        if (self.index_items[i].disk_offset == disk_offset) return self.index_items[i];
    }
    return null;
}

fn debugStoreReadU32(self: *DebugSpanStore, off: u32) u32 {
    var b: [4]u8 = undefined;
    spill_mod.spillReadAt(&self.spill, off, b[0..]);
    return @intCast(u32, b[0]) | (@intCast(u32, b[1]) << @intCast(u32, 8)) | (@intCast(u32, b[2]) << @intCast(u32, 16)) | (@intCast(u32, b[3]) << @intCast(u32, 24));
}

pub fn debugSpanStoreRead(self: *DebugSpanStore, rec: DebugFnSpanIndex, dst: []lir_mod.DebugSpanEntry) void {
    if (dst.len == @intCast(usize, 0)) return;
    var count = debugStoreReadU32(self, rec.spill_offset);
    var n = @intCast(usize, count);
    if (n > dst.len) n = dst.len;
    var byte_len = n * @intCast(usize, @sizeOf(lir_mod.DebugSpanEntry));
    spill_mod.spillReadAt(&self.spill, rec.spill_offset + @intCast(u32, 4), @ptrCast([*]u8, dst.ptr)[0..byte_len]);
}

pub fn debugSpanStoreClose(self: *DebugSpanStore) void {
    if (self.enabled == @intCast(u8, 0)) return;
    spill_mod.spillClose(&self.spill);
    self.enabled = @intCast(u8, 0);
}

pub fn debugSpanLookup(spans: []lir_mod.DebugSpanEntry, bb: u32, inst: u32) u32 {
    var lo: usize = @intCast(usize, 0);
    var hi: usize = spans.len;
    while (lo < hi) {
        var mid = lo + (hi - lo) / @intCast(usize, 2);
        var e = spans[mid];
        if (e.bb < bb or (e.bb == bb and e.inst < inst)) {
            lo = mid + @intCast(usize, 1);
        } else if (e.bb > bb or (e.bb == bb and e.inst > inst)) {
            hi = mid;
        } else {
            return e.span_start;
        }
    }
    return @intCast(u32, 0);
}

// ---------------------------------------------------------------------------
// Symbols (small in-memory records, written sorted at close)
// ---------------------------------------------------------------------------

pub const DebugSymbol = struct {
    kind: u8,
    is_extern: u8,
    name_id: u32,
    module_id: u32,
    type_id: u32,
    src_line: u32,
    src_file_id: u32,
    // AST span of the declaration. Async synthetic functions have no per-inst
    // spans; their rows fall back to this span (the suspending fn's line).
    decl_span: u32,
};

pub const DebugSymbolList = struct {
    items: [*]DebugSymbol,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn debugSymbolListInit(allocator: *Sand) DebugSymbolList {
    return DebugSymbolList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

fn debugSymbolListEnsure(self: *DebugSymbolList, need: usize) void {
    if (need <= self.capacity) return;
    var cap = self.capacity;
    if (cap == @intCast(usize, 0)) cap = @intCast(usize, 32);
    while (cap < need) : (cap *= @intCast(usize, 2)) {}
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, @sizeOf(DebugSymbol)) * cap, @intCast(usize, 4)) catch unreachable;
    var dst = @ptrCast([*]DebugSymbol, raw);
    var i: usize = @intCast(usize, 0);
    while (i < self.len) : (i += @intCast(usize, 1)) {
        dst[i] = self.items[i];
    }
    self.items = dst;
    self.capacity = cap;
}

pub fn debugSymbolListAppend(self: *DebugSymbolList, value: DebugSymbol) void {
    debugSymbolListEnsure(self, self.len + @intCast(usize, 1));
    self.items[self.len] = value;
    self.len += @intCast(usize, 1);
}

pub fn debugSymbolFindFn(self: *DebugSymbolList, module_id: u32, name: []const u8, interner: *interner_mod.StringInterner) ?DebugSymbol {
    var i: usize = @intCast(usize, 0);
    while (i < self.len) : (i += @intCast(usize, 1)) {
        var s = self.items[i];
        if (s.kind != @intCast(u8, 0)) continue;
        if (s.module_id != module_id) continue;
        if (strCompare(interner_mod.stringInternerGet(interner, s.name_id), name) == 0) return s;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Map writer
// ---------------------------------------------------------------------------

pub const DebugOutFile = struct {
    store: spill_mod.SpillStore,
    count: u32,
};

fn debugOutOpen(out: *DebugOutFile, path: []const u8, alloc: *Sand, magic: []const u8) void {
    out.store = spill_mod.spillStoreInit();
    var mode: [*]const u8 = "w+b";
    spill_mod.spillOpen(&out.store, spill_mod.SpillBackend.disk, path, alloc, mode);
    out.count = @intCast(u32, 0);
    spill_mod.spillWriteAt(&out.store, out.store.cur, magic);
    var ver: [4]u8 = undefined;
    ver[0] = @intCast(u8, VERSION & @intCast(u32, 0xFF));
    ver[1] = @intCast(u8, (VERSION >> @intCast(u32, 8)) & @intCast(u32, 0xFF));
    ver[2] = @intCast(u8, (VERSION >> @intCast(u32, 16)) & @intCast(u32, 0xFF));
    ver[3] = @intCast(u8, (VERSION >> @intCast(u32, 24)) & @intCast(u32, 0xFF));
    spill_mod.spillWriteAt(&out.store, out.store.cur, ver[0..]);
    var zero: [4]u8 = [4]u8{ 0, 0, 0, 0 };
    spill_mod.spillWriteAt(&out.store, out.store.cur, zero[0..]);
    spill_mod.spillWriteAt(&out.store, out.store.cur, zero[0..]);
}

fn debugOutWriteU16(out: *DebugOutFile, value: u16) void {
    var b: [2]u8 = undefined;
    b[0] = @intCast(u8, @intCast(u32, value) & @intCast(u32, 0xFF));
    b[1] = @intCast(u8, (@intCast(u32, value) >> @intCast(u32, 8)) & @intCast(u32, 0xFF));
    spill_mod.spillWriteAt(&out.store, out.store.cur, b[0..]);
}

fn debugOutWriteU32(out: *DebugOutFile, value: u32) void {
    var b: [4]u8 = undefined;
    b[0] = @intCast(u8, value & @intCast(u32, 0xFF));
    b[1] = @intCast(u8, (value >> @intCast(u32, 8)) & @intCast(u32, 0xFF));
    b[2] = @intCast(u8, (value >> @intCast(u32, 16)) & @intCast(u32, 0xFF));
    b[3] = @intCast(u8, (value >> @intCast(u32, 24)) & @intCast(u32, 0xFF));
    spill_mod.spillWriteAt(&out.store, out.store.cur, b[0..]);
}

fn debugOutWriteBytes(out: *DebugOutFile, bytes: []const u8) void {
    if (bytes.len == @intCast(usize, 0)) return;
    spill_mod.spillWriteAt(&out.store, out.store.cur, bytes);
}

// str16 of a+b without a temporary concatenation buffer.
fn debugOutWriteStr16Pair(out: *DebugOutFile, a: []const u8, b: []const u8) void {
    var total: usize = a.len + b.len;
    if (total > @intCast(usize, 65535)) total = @intCast(usize, 65535);
    var la = a.len;
    if (la > total) la = total;
    var lb = total - la;
    debugOutWriteU16(out, @intCast(u16, total));
    debugOutWriteBytes(out, a[0..la]);
    if (lb > b.len) lb = b.len;
    debugOutWriteBytes(out, b[0..lb]);
}

fn debugOutWriteStr16(out: *DebugOutFile, s: []const u8) void {
    var len = s.len;
    if (len > @intCast(usize, 65535)) len = @intCast(usize, 65535);
    debugOutWriteU16(out, @intCast(u16, len));
    debugOutWriteBytes(out, s[0..len]);
}

fn debugOutClose(out: *DebugOutFile, magic: []const u8) void {
    var total: u32 = out.store.cur;
    spill_mod.spillSeek(&out.store, @intCast(u32, 0));
    debugOutWriteBytes(out, magic);
    debugOutWriteU32(out, VERSION);
    debugOutWriteU32(out, out.count);
    debugOutWriteU32(out, total);
    spill_mod.spillClose(&out.store);
}

pub const DebugMapWriter = struct {
    syms: DebugOutFile,
    lines: DebugOutFile,
    cnames: DebugOutFile,
    enabled: u8,
    group_open: u8,
    group_count_offset: u32,
    group_run_count: u32,
    last_src_line: u32,
    last_out_start: u32,
    last_out_count: u32,
    has_last: u8,
};

pub fn debugMapWriterInit() DebugMapWriter {
    return DebugMapWriter{
        .syms = DebugOutFile{ .store = spill_mod.spillStoreInit(), .count = @intCast(u32, 0) },
        .lines = DebugOutFile{ .store = spill_mod.spillStoreInit(), .count = @intCast(u32, 0) },
        .cnames = DebugOutFile{ .store = spill_mod.spillStoreInit(), .count = @intCast(u32, 0) },
        .enabled = @intCast(u8, 0),
        .group_open = @intCast(u8, 0),
        .group_count_offset = @intCast(u32, 0),
        .group_run_count = @intCast(u32, 0),
        .last_src_line = @intCast(u32, 0),
        .last_out_start = @intCast(u32, 0),
        .last_out_count = @intCast(u32, 0),
        .has_last = @intCast(u8, 0),
    };
}

pub fn debugMapWriterOpen(self: *DebugMapWriter, alloc: *Sand, syms_path: []const u8, lines_path: []const u8, cnames_path: []const u8) void {
    debugOutOpen(&self.syms, syms_path, alloc, magicSyms());
    debugOutOpen(&self.lines, lines_path, alloc, magicLines());
    debugOutOpen(&self.cnames, cnames_path, alloc, magicCnames());
    self.enabled = @intCast(u8, 1);
}

pub fn debugMapWriterBeginLineGroup(self: *DebugMapWriter, src_file: []const u8, out_base: []const u8) void {
    if (self.enabled == @intCast(u8, 0)) return;
    debugOutWriteStr16(&self.lines, src_file);
    var cext: []const u8 = ".c";
    debugOutWriteStr16Pair(&self.lines, out_base, cext);
    self.group_count_offset = self.lines.store.cur;
    debugOutWriteU32(&self.lines, @intCast(u32, 0));
    self.group_run_count = @intCast(u32, 0);
    self.has_last = @intCast(u8, 0);
    self.group_open = @intCast(u8, 1);
}

fn debugMapFlushLast(self: *DebugMapWriter) void {
    if (self.has_last == @intCast(u8, 0)) return;
    debugOutWriteU32(&self.lines, self.last_src_line);
    debugOutWriteU32(&self.lines, self.last_out_start);
    debugOutWriteU32(&self.lines, self.last_out_count);
    self.group_run_count += @intCast(u32, 1);
    self.has_last = @intCast(u8, 0);
}

pub fn debugMapWriterAddRun(self: *DebugMapWriter, src_line: u32, out_start: u32, out_count: u32) void {
    if (self.enabled == @intCast(u8, 0) or self.group_open == @intCast(u8, 0) or out_count == @intCast(u32, 0)) return;
    if (self.has_last != @intCast(u8, 0) and self.last_src_line == src_line and self.last_out_start + self.last_out_count == out_start) {
        self.last_out_count += out_count;
        return;
    }
    debugMapFlushLast(self);
    self.last_src_line = src_line;
    self.last_out_start = out_start;
    self.last_out_count = out_count;
    self.has_last = @intCast(u8, 1);
}

pub fn debugMapWriterEndLineGroup(self: *DebugMapWriter) void {
    if (self.enabled == @intCast(u8, 0) or self.group_open == @intCast(u8, 0)) return;
    debugMapFlushLast(self);
    var end = self.lines.store.cur;
    spill_mod.spillSeek(&self.lines.store, self.group_count_offset);
    debugOutWriteU32(&self.lines, self.group_run_count);
    spill_mod.spillSeek(&self.lines.store, end);
    self.lines.count += self.group_run_count;
    self.group_open = @intCast(u8, 0);
}

fn debugModuleStem(mangler: *nm_mod.NameMangler, interner: *interner_mod.StringInterner, module_reg: *mr_mod.ModuleRegistry, module_id: u32) []const u8 {
    var mods = mr_mod.moduleRegistryGetModules(module_reg);
    var path_str = interner_mod.stringInternerGet(interner, mods[@intCast(usize, module_id)].path_id);
    return nm_mod.nameManglerMintModuleStem(mangler, path_str);
}

fn debugSymbolSrcFile(sym: DebugSymbol, source_man: *sm_mod.SourceManager) []const u8 {
    return sm_mod.sourceManagerGetFileName(source_man, sym.src_file_id);
}

fn debugSymbolName(sym: DebugSymbol, interner: *interner_mod.StringInterner) []const u8 {
    return interner_mod.stringInternerGet(interner, sym.name_id);
}

fn debugSymbolLess(a: DebugSymbol, b: DebugSymbol, source_man: *sm_mod.SourceManager, interner: *interner_mod.StringInterner) bool {
    var af = debugSymbolSrcFile(a, source_man);
    var bf = debugSymbolSrcFile(b, source_man);
    var c = strCompare(af, bf);
    if (c < 0) return true;
    if (c > 0) return false;
    if (a.src_line < b.src_line) return true;
    if (a.src_line > b.src_line) return false;
    var an = debugSymbolName(a, interner);
    var bn = debugSymbolName(b, interner);
    return strCompare(an, bn) < 0;
}

fn debugCnameLess(a: DebugSymbol, b: DebugSymbol, interner: *interner_mod.StringInterner) bool {
    var an = debugSymbolName(a, interner);
    var bn = debugSymbolName(b, interner);
    var c = strCompare(an, bn);
    if (c < 0) return true;
    if (c > 0) return false;
    if (a.module_id < b.module_id) return true;
    if (a.module_id > b.module_id) return false;
    return a.kind < b.kind;
}

// Finalize `.syms` + `.cnames`, then patch every header and close. Symbol
// arrays are sorted here (small: one record per fn/global, never per inst).
pub fn debugMapWriterClose(self: *DebugMapWriter, alloc: *Sand, symbols: []DebugSymbol, source_man: *sm_mod.SourceManager, mangler: *nm_mod.NameMangler, interner: *interner_mod.StringInterner, module_reg: *mr_mod.ModuleRegistry, registry: *type_mod.TypeRegistry) void {
    if (self.enabled == @intCast(u8, 0)) return;

    // --- .syms: sorted by (src_file, src_line, name) ---
    var sym_copy: []DebugSymbol = undefined;
    if (symbols.len > @intCast(usize, 0)) {
        var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, @sizeOf(DebugSymbol)) * symbols.len, @intCast(usize, 4)) catch unreachable;
        var dst = @ptrCast([*]DebugSymbol, raw);
        var ci: usize = @intCast(usize, 0);
        while (ci < symbols.len) : (ci += @intCast(usize, 1)) { dst[ci] = symbols[ci]; }
        sym_copy = dst[0..symbols.len];
        var i: usize = @intCast(usize, 1);
        while (i < sym_copy.len) : (i += @intCast(usize, 1)) {
            var key = sym_copy[i];
            var j: usize = i;
            while (j > @intCast(usize, 0)) {
                if (!debugSymbolLess(key, sym_copy[j - @intCast(usize, 1)], source_man, interner)) break;
                sym_copy[j] = sym_copy[j - @intCast(usize, 1)];
                j -= @intCast(usize, 1);
            }
            sym_copy[j] = key;
        }
    }
    var si: usize = @intCast(usize, 0);
    while (si < symbols.len) : (si += @intCast(usize, 1)) {
        var s = sym_copy[si];
        var nm = debugSymbolName(s, interner);
        var mstem = debugModuleStem(mangler, interner, module_reg, s.module_id);
        var sf = debugSymbolSrcFile(s, source_man);
        var out = &self.syms;
        var kb: [1]u8 = undefined;
        kb[0] = s.kind;
        debugOutWriteBytes(out, kb[0..]);
        debugOutWriteU32(out, s.src_line);
        debugOutWriteStr16(out, nm);
        debugOutWriteStr16(out, mstem);
        debugOutWriteStr16(out, sf);
        out.count += @intCast(u32, 1);
    }

    // --- .cnames: sorted by src_name ---
    var cn_copy: []DebugSymbol = undefined;
    if (symbols.len > @intCast(usize, 0)) {
        var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, @sizeOf(DebugSymbol)) * symbols.len, @intCast(usize, 4)) catch unreachable;
        var dst = @ptrCast([*]DebugSymbol, raw);
        var ci: usize = @intCast(usize, 0);
        while (ci < symbols.len) : (ci += @intCast(usize, 1)) { dst[ci] = symbols[ci]; }
        cn_copy = dst[0..symbols.len];
        var i: usize = @intCast(usize, 1);
        while (i < cn_copy.len) : (i += @intCast(usize, 1)) {
            var key = cn_copy[i];
            var j: usize = i;
            while (j > @intCast(usize, 0)) {
                if (!debugCnameLess(key, cn_copy[j - @intCast(usize, 1)], interner)) break;
                cn_copy[j] = cn_copy[j - @intCast(usize, 1)];
                j -= @intCast(usize, 1);
            }
            cn_copy[j] = key;
        }
    }
    var cn: usize = @intCast(usize, 0);
    while (cn < symbols.len) : (cn += @intCast(usize, 1)) {
        var s = cn_copy[cn];
        var src_nm = debugSymbolName(s, interner);
        var mangled: []const u8 = src_nm;
        if (s.kind == @intCast(u8, 0)) {
            if (s.is_extern == @intCast(u8, 0)) {
                var mid = nm_mod.nameManglerMangle(mangler, s.name_id, @intCast(u8, 0), s.module_id);
                mangled = interner_mod.stringInternerGet(interner, mid);
            }
        } else {
            var gmid = nm_mod.nameManglerMangleGlobal(mangler, registry, s.name_id, s.module_id, s.type_id);
            mangled = interner_mod.stringInternerGet(interner, gmid);
        }
        debugOutWriteStr16(&self.cnames, src_nm);
        debugOutWriteStr16(&self.cnames, mangled);
        self.cnames.count += @intCast(u32, 1);
    }

    debugOutClose(&self.syms, magicSyms());
    debugOutClose(&self.cnames, magicCnames());
    debugOutClose(&self.lines, magicLines());
    self.enabled = @intCast(u8, 0);
}
