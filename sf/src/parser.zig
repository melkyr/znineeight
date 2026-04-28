pub const Prec = enum(u8) {
    none = 0,
    assignment = 1,
    prec_orelse = 2,
    prec_catch = 3,
    bool_or = 4,
    bool_and = 5,
    comparison = 6,
    bit_or = 7,
    bit_xor = 8,
    bit_and = 9,
    shift = 10,
    additive = 11,
    multiply = 12,
    prefix = 13,
    postfix = 14,
};

pub const OpInfo = struct {
    prec: Prec,
    right_assoc: bool,
};

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    store: *AstStore,
    interner: *StringInterner,
    diag: *DiagnosticCollector,

    pub fn init(tokens: []const Token, store: *AstStore, interner: *StringInterner, diag: *DiagnosticCollector) Parser {}
    pub fn parseModuleRoot(self: *Parser) !u32 {}
    fn peek(self: *Parser) Token {}
    fn peekN(self: *Parser, n: usize) Token {}
    fn advance(self: *Parser) Token {}
    fn expect(self: *Parser, kind: TokenKind) !Token {}
    fn addDiagnostic(self: *Parser, level: u8, tok: Token, msg: []const u8) !void {}
    fn synchronize(self: *Parser) void {}
    fn parseStatement(self: *Parser) !u32 {}
    fn parseVarDecl(self: *Parser) !u32 {}
    fn parseFnDecl(self: *Parser) !u32 {}
    fn parseBlock(self: *Parser) !u32 {}
    fn parseExprPrec(self: *Parser, min_prec: Prec) !u32 {}
    fn parsePrimary(self: *Parser) !u32 {}
    fn parsePostfixChain(self: *Parser, base: u32) !u32 {}
    fn parseIfStmt(self: *Parser) !u32 {}
    fn parseWhileStmt(self: *Parser) !u32 {}
    fn parseForStmt(self: *Parser) !u32 {}
    fn parseSwitchExpr(self: *Parser) !u32 {}
    fn parseReturn(self: *Parser) !u32 {}
    fn parseBreak(self: *Parser) !u32 {}
    fn parseContinue(self: *Parser) !u32 {}
    fn parseDefer(self: *Parser) !u32 {}
    fn parseTestDecl(self: *Parser) !u32 {}
    fn parseTryExpr(self: *Parser) !u32 {}
    fn parseCatchRHS(self: *Parser, min_prec: Prec) !u32 {}
    fn parseOrelseRHS(self: *Parser, min_prec: Prec) !u32 {}
    fn parseType(self: *Parser) !u32 {}
    fn parsePubDecl(self: *Parser) !u32 {}
    fn parseLabeledStmt(self: *Parser) !u32 {}
    fn parseExprStmt(self: *Parser) !u32 {}
};

pub fn getInfixInfo(kind: TokenKind) ?OpInfo {}

const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const AstStore = @import("ast.zig").AstStore;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
