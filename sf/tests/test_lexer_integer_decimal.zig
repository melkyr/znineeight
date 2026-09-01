const Allocator = @import("../src/allocator.zig").Allocator;
const StringInterner = @import("../src/string_interner.zig").StringInterner;
const DiagnosticCollector = @import("../src/diagnostics.zig").DiagnosticCollector;
const SourceManager = @import("../src/source_manager.zig").SourceManager;
const Lexer = @import("../src/lexer.zig").Lexer;
const TokenKind = @import("../src/token.zig").TokenKind;
const assert_true = @import("../src/test_runner.zig").assert_true;
const assert_eq_u64 = @import("../src/test_runner.zig").assert_eq_u64;

const BumpAlloc = struct {
    buf: []u8,
    pos: u32,
    iface: Allocator,

    fn init(buf: []u8) BumpAlloc {
        var result = BumpAlloc{
            .buf = buf,
            .pos = 0,
            .iface = undefined,
        };
        result.iface = Allocator{
            .context = @ptrCast(*void, &result),
            .alloc_fn = bumpAllocFn,
            .free_fn = bumpFreeFn,
            .resize_fn = bumpResizeFn,
        };
        return result;
    }

    fn allocator(self: *BumpAlloc) *Allocator {
        return &self.iface;
    }
};

fn bumpAllocFn(ctx: *void, byte_count: usize, alignment: u32) ![]u8 {
    var self = @ptrCast(*BumpAlloc, ctx);
    var mask = alignment - 1;
    var aligned_pos = (self.pos + mask) & ~mask;
    if (aligned_pos + byte_count > self.buf.len) {
        return error.OutOfMemory;
    }
    var result = self.buf[@intCast(usize, aligned_pos)..@intCast(usize, aligned_pos + byte_count)];
    self.pos = @intCast(u32, aligned_pos + byte_count);
    return result;
}

fn bumpFreeFn(ctx: *void, bytes: []u8) void {
    _ = ctx;
    _ = bytes;
}

fn bumpResizeFn(ctx: *void, bytes: []u8, new_count: usize) !bool {
    _ = ctx;
    _ = bytes;
    _ = new_count;
    return false;
}

pub fn test_lexer_integer_decimal() void {
    const source = "42";
    var backing_buf: [4096]u8 = undefined;
    var bump = BumpAlloc.init(backing_buf[0..]);
    var alloc = bump.allocator();
    var interner = StringInterner.init(alloc, 4) catch @panic("init");
    var sm = SourceManager.init(alloc);
    var diag = DiagnosticCollector.init(alloc, &sm);
    var lexer = Lexer.init(source, &interner, &diag);
    const tok = lexer.nextToken();
    assert_true(tok.kind == TokenKind.integer_literal, "kind");
    assert_eq_u64(42, tok.value.int_val, "value");
}
