const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const sm_mod = @import("../source_manager.zig");
const SourceManager = sm_mod.SourceManager;
const Lexer = @import("../lexer.zig").Lexer;
const token_mod = @import("../token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;

pub const LexerTestHarness = struct {
    buf: [4096]u8,
    sand: Sand,
    interner: StringInterner,
    source_man: SourceManager,
    diag: DiagnosticCollector,
    lexer: Lexer,
};

pub fn lexerTestHarnessInit(h: *LexerTestHarness, source: []const u8, file_id: u32) void {
    h.sand = alloc_mod.sandInit(h.buf[0..]);
    h.interner = interner_mod.stringInternerInit(&h.sand, 4);
    h.source_man = sm_mod.sourceManagerInit(&h.sand);
    h.diag = diag_mod.diagnosticCollectorInit(&h.sand, &h.source_man, &h.interner);
    h.lexer = Lexer.init(source, file_id, &h.interner, &h.diag, &h.sand);
}

pub fn lexerTestHarnessNextKind(h: *LexerTestHarness) TokenKind {
    return h.lexer.nextToken().kind;
}
