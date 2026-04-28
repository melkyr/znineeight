pub const BufferedWriter = struct {
    buffer: [4096]u8,
    pos: usize,
    output: *Writer,

    pub fn init(output: *Writer) BufferedWriter {}
    pub fn write(self: *BufferedWriter, data: []const u8) !void {}
    pub fn writeByte(self: *BufferedWriter, byte: u8) !void {}
    pub fn writeIndent(self: *BufferedWriter, indent: u32) !void {}
    pub fn flush(self: *BufferedWriter) !void {}
};

pub const Writer = struct {
    writeFn: fn (self: *Writer, data: []const u8) !void,

    pub fn write(self: *Writer, data: []const u8) !void {}
};

pub const NameMangler = struct {
    interner: *StringInterner,
    counter: u32,
    test_mode: bool,

    pub fn init(interner: *StringInterner) NameMangler {}
    pub fn mangleName(self: *NameMangler, name_id: u32, kind: u8, module_id: u32) !u32 {}
    fn fnv1a(data: []const u8) u32 {}
};

pub const C89Emitter = struct {
    writer: BufferedWriter,
    indent: u32,
    registry: *TypeRegistry,
    interner: *StringInterner,
    mangler: *NameMangler,
    switch_cases: std.ArrayList(SwitchCase),
    call_args: std.ArrayList(u32),
    diag: *DiagnosticCollector,
    allocator: *Allocator,

    pub fn init(registry: *TypeRegistry, interner: *StringInterner, mangler: *NameMangler, diag: *DiagnosticCollector, allocator: *Allocator) C89Emitter {}
    pub fn emitModule(self: *C89Emitter, module_id: u32, funcs: []const LirFunction) !void {}
    pub fn emitFunctionSignature(self: *C89Emitter, func: *LirFunction) !void {}
    pub fn emitFunctionBody(self: *C89Emitter, func: *LirFunction) !void {}
    pub fn emitBlock(self: *C89Emitter, block: *BasicBlock, func: *LirFunction) !void {}
    pub fn emitInst(self: *C89Emitter, inst: *LirInst, func: *LirFunction) !void {}
    pub fn emitCompatHeader(self: *C89Emitter) !void {}
    pub fn emitRuntime(self: *C89Emitter) !void {}
};

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = @import("type_registry.zig").TypeId;
const StringInterner = @import("string_interner.zig").StringInterner;
const LirFunction = @import("lir.zig").LirFunction;
const LirInst = @import("lir.zig").LirInst;
const BasicBlock = @import("lir.zig").BasicBlock;
const SwitchCase = @import("lir.zig").SwitchCase;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const Allocator = @import("allocator.zig").Allocator;
