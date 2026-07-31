# 00 — Lexer & Parser

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `TokenKind` variants | 92 | 0..91, `err_token(91)` for error recovery |
| Keywords | 36 | `const, var, fn, pub, extern, export, test, struct, enum, union, if, else, while, for, switch, return, break, continue, defer, errdefer, try, catch, orelse, error, and, or, true, false, null, undefined, unreachable, void, bool, noreturn, c_char, anytype` |
| `AstKind` variants | 97 (0..96) | `err=0` through `c_include=96`. **BUG: `swt_ex=56` collides with `mod_assign=56`** (ast.zig:76) |
| `AstNode` size | 24 bytes | Not packed — zig0 rejects packed structs with union fields (token.zig:115-117) |
| Prec levels | 15 | `none(0)` .. `postfix(14)` (parser.zig:1784-1800) |
| Debug markers | ~15+ | `LEX`, `PF:`, `BOP:tk`, `PSWE:n`, `PCB:E/T`, `PSTK:k`, `PIF:c`, `PBX:S/T/K`, `PLEN:l`, `ZZZ_*` |

---

## token.zig (`sf/src/token.zig`, 185 lines)

Defines the token universe: `TokenKind` enum (92 kinds), `Token` struct (24 bytes), keyword table.

### Types

| Type | Description |
|------|-------------|
| `TokenKind` (enum u16) | 92 variants: 2-char operators (`shl`, `shr`), compound assign (`plus_eq`..`shr_eq`), dot forms (`dot_dot`, `dot_dot_dot`, `dot_lbrace`, `dot_star`), 36 keywords (`kw_const`..`kw_anytype`), `c_include_builtin`, `eof`, `err_token` |
| `SyncContext` (enum u8) | 5 recovery contexts: `stmt_list`, `expression`, `switch_prong`, `fn_body`, `module_root` |
| `TokenValue` (union) | `int_val(u64)`, `float_val(f64)`, `string_id(u32)`, `none(void)` |
| `Token` (struct) | 24 bytes: `kind(TokenKind,u16)`, `span_start(u32)`, `span_len(u16)`, `value(TokenValue,union)`. **FIXME (token.zig:115-117):** Desired packed layout (16 bytes) rejected by zig0 because `TokenValue` has a union field. Restore when zig1 self-hosts. |
| `KeywordEntry` (struct) | `name([]const u8)`, `kind(TokenKind)` |

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `initKeywordTable` | 133 | pub | `[inference: source text allocates 36-entry table from sand allocator]` | Initializes global `keyword_table` with 36 keyword entries. Manually unrolled assignment per entry. Called once at startup. |
| `lookupKeyword` | 178 | pub | `[inference: linear scan O(k) where k=36, returns first match]` | Linear search of `keyword_table` for `text` via `mem_eql`. Returns `?TokenKind` or null. |

---

## lexer.zig (`sf/src/lexer.zig`, 942 lines)

Scanner: source text → `Token` stream. Single-pass, character-by-character. All state in `Lexer` struct.

### Types

| Type | Line | Description |
|------|------|-------------|
| `Lexer` | 18 | Fields: `source([]const u8)`, `pos(usize)`, `line(u32)`, `col(u32)`, `file_id(u32)`, `interner(*StringInterner)`, `diag(*DiagnosticCollector)`, `string_buf(*U8ArrayList)` |

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `lexerInit` | 29 | pub | `[inference: sand alloc for string_buf, U8ArrayList init]` | Creates `Lexer` from source, file_id, interner, diag, alloc. Allocates `string_buf` via sand. |
| `lexerNextToken` | 45 | pub | `[inference: skipWS → char dispatch → ~30 switch arms]` | Main scan loop. Skips WS/comments, reads one char, dispatches to single-char tokens (45 cases), compound operators (`..`, `...`, `.{}`, `.*`, `==`, `=>`, `!=`, `<<`, `>>`, `<=`, `>=`, `+=`..`^=`, each with `lexerMatch`), `@` → `lexerScanBuiltinIdentifier`, `"` → `lexerScanString`, `'` → `lexerScanChar`, alpha/`_` → `lexerScanIdentifierOrKeyword`, digit → `lexerScanNumber`, else → error token + diagnostic `ERR_1005`. |
| `lexerAdvance` | 155 | private | `[inference: bounds check, mem read, line/col tracking]` | Consumes one byte. Returns `0` at EOF. Updates `line`/`col`. |
| `lexerPeek` | 168 | private | `[inference: bounds check, returns 0 at EOF]` | Lookahead 1 without consuming. |
| `lexerPeekN` | 173 | private | `[inference: bounds check, returns 0 at EOF]` | Lookahead N without consuming. |
| `lexerIsAtEnd` | 179 | private | `[inference: pos >= source.len]` | EOF predicate. |
| `lexerMatch` | 183 | private | `[inference: conditional consume]` | If peek == expected, advance+return true; else false. |
| `lexerSkipWSC` | 189 | private | `[inference: loops skipping space/tab/nl/cr//comments/*/comments]` | Skips whitespace and comments. **Nested block comment** support (depth tracking, `/*/*/` counting). Emits `ERR_1001` on unterminated block comments. |
| `lexerMakeToken` | 233 | private | `[inference: span_len = pos - start]` | Constructs `Token` from current position. |
| `lexerMakeErrorToken` | 243 | private | `[inference: fixed span_len=1]` | Constructs `err_token` with span_len=1. |
| `lexerScanString` | 253 | private | `[inference: string_buf reused, escape seqs processed, interner dedup]` | Scans `"..."`. Accumulates decoded bytes into `string_buf`. Processes escape sequences via `lexerParseEscapeSequence`. Interns decoded content via `interner`. Emits `ERR_1000` on unterminated string (newline/EOF before `"`). |
| `lexerScanChar` | 291 | private | `[inference: single char or escape, u32 val]` | Scans `'x'` or `'\n'`. Handles empty `''` with `ERR_1002`. Emits `ERR_1002` on missing closing `'`. |
| `lexerScanNumber` | 320 | private | `[inference: base detection(0x/0b/0o), digit scan with _ sep, float parsing, overflow check]` | Scans integer/float literals. Base detection (hex `0x`, binary `0b`, octal `0o`). Integer overflow detection via `isU64MaxLiteral` + `WARN_1011`. Float via decimal `.` and scientific `e`/`E` notation. |
| `lexerScanIdentifierOrKeyword` | 377 | private | `[inference: char loop, keyword lookup, single `_` check, DEBUG `LEX` marker]` | Scans `[a-zA-Z_][a-zA-Z0-9_]*`. Single `_` → `underscore` token. Keyword lookup → keyword token. **DEBUG (lexer.zig:396-399):** If identifier is exactly "neighbors", writes `LEX` to stderr. |
| `lexerScanBuiltinIdentifier` | 404 | private | `[inference: @ + alphanum scan, special case @cInclude]` | Scans `@sizeOf`, `@import`, etc. If text is `@cInclude` (9 chars), returns `c_include_builtin`. |
| `isAlpha` | 420 | private | `[inference: char range checks, '_' included]` | `[a-zA-Z_]` |
| `isDigit` | 424 | private | `[inference: char range '0'..'9']` | `[0-9]` |
| `isAlphaNum` | 428 | private | `[inference: isAlpha or isDigit]` | `[a-zA-Z0-9_]` |
| `hexDigitValue` | 432 | private | `[inference: char→nybble, returns 0xFF on invalid]` | Converts hex char to 0-15. |
| `lexerParseHexEscape` | 439 | private | `[inference: up to 2 hex digits, ERR_1003 if 0]` | Parses `\xHH`. Emits `ERR_1003` if no hex digits follow `\x`. |
| `lexerParseEscapeSequence` | 456 | private | `[inference: dispatch on '\n','\t','\r','\\','\"','\'','\0','\x', else WARN_1010]` | Parses escape sequences. Unrecognized escapes emit `WARN_1010` and return the raw char. |
| `isDigitInBase` | 482 | private | `[inference: switch on base 2/8/10/16]` | Range check per base. |
| `parseU64` | 492 | private | `[inference: base prefix skip, digit loop, overflow detection]` | Parses `[]const u8` to `u64`. Handles `_` separators. Clamps overflow to `0xFFFF_FFFF_FFFF_FFFF`. |
| `parseF64` | 536 | private | `[inference: sign, int part, frac part, scientific exp, E notation loop]` | Hand-written float parser. No IEEE edge cases. Scientific exponent uses naive `10^exp` loop. |
| `isU64MaxLiteral` | 596 | private | `[inference: reparses as hex, compares to 0xFFFF_FFFF_FFFF_FFFF]` | Distinguishes true max-u64 from overflow. |
| `assertEqBool` | 602 | private | `[inference: test helper, stderr output on mismatch]` | Inline test assertion. |
| `assertEqU32` | 621 | private | `[inference: test helper, stderr output on mismatch]` | Inline test assertion. |
| `assertEqU8` | 638 | private | `[inference: test helper, stderr output on mismatch]` | Inline test assertion. |
| `assertEqTokenKind` | 649 | private | `[inference: test helper, stderr output on mismatch]` | Inline test assertion. |
| `formatU32` | 660 | private | `[inference: reverse-digit, null-terminated buf, slice return]` | Simple u32→string formatter for test output. |
| `lexerRunAllTests` | 679 | pub | `[inference: sequential test runner, all test groups]` | Test harness: runs 10 test groups + external `lexer_tests.runLexerUnitTests`. |
| `lexerTestSanityCheck` | 696 | pub | `[inference: intentional panic]` | Sanity check — always fails. |
| `lexerTestHelpers` | 702 | private | `[inference: tests lexerAdvance/Peek/PeekN/IsAtEnd/Match]` | Tests cursor primitives. |
| `lexerTestSkipWhitespaceAndComments` | 739 | private | `[inference: tests lexerSkipWSC]` | Tests whitespace skipping. |
| `lexerTestOperators` | 752 | private | `[inference: tests delimiter token kinds]` | Tests `()[]{}`, `+-*/%&|^~!?;:,`, compound operators. |
| `lexerTestScanNumber` | 794 | private | `[inference: tests decimal/hex/binary/octal/float/int parsing]` | Tests number scanning. |
| `lexerTestScanString` | 834 | private | `[inference: tests basic string, escape, unterminated]` | Tests string scanning. |
| `lexerTestScanChar` | 857 | private | `[inference: tests basic char, escape, empty]` | Tests char scanning. |
| `lexerTestIdentifierKeywords` | 880 | private | `[inference: tests underscore/ident/keyword dispatch]` | Tests identifier/keyword resolution. |
| `lexerTestBuiltinIdentifier` | 908 | private | `[inference: tests @sizeOf and bare @]` | Tests builtin identifier scanning. |
| `lexerTestDiagnostics` | 926 | private | `[inference: tests backtick and @`` error tokens]` | Tests error token emission. |

**Debug markers in lexer (lexer.zig:396-399):** When the identifier text is exactly `"neighbors"` (9 chars, `n e i g h b o r s`), the lexer writes `LEX` to stderr. This is a debug/tracing hook.

---

## parser.zig (`sf/src/parser.zig`, 1842 lines)

Recursive-descent parser with **Pratt-style precedence climbing** for expressions. Source text → Token array (from lexer) → `AstStore` (AST node tree).

### Types

| Type | Line | Description |
|------|------|-------------|
| `ParserError` | 1 | `UnexpectedToken` |
| `ParseToken` | 25 | Lightweight token: `kind`, `span_start`, `span_len` (no `TokenValue`) |
| `Parser` | 31 | Core parser state: token array (`tokens_ptr`, `tokens_len`), source, position, `AstStore*`, child/decl buffers, `catch_capture(u32)`, `expr_depth(u32)`, module registry |
| `Prec` (enum u8) | 1784 | 15 precedence levels: `none(0)`, `assignment(1)`, `prec_orelse(2)`, `prec_catch(3)`, `bool_or(4)`, `bool_and(5)`, `comparison(6)`, `bit_or(7)`, `bit_xor(8)`, `bit_and(9)`, `shift(10)`, `additive(11)`, `multiply(12)`, `prefix(13)`, `postfix(14)` |
| `OpInfo` | 1810 | `prec(Prec)` + `right_assoc(bool)` |

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `parserInit` | 56 | pub | `[inference: interns "@import", inits Parser from token/source slices]` | Creates `Parser`. Initializes `child_buf`, `decl_buf` to undefined (allocated lazily). Pre-interns `@import` for builtin detection. |
| `parserSetModuleContext` | 86 | pub | `[inference: sets module_reg, current_module_id, file_id]` | Attaches module registry context for `@import` resolution. |
| `parserTokenText` | 92 | pub | `[inference: slice from source_ptr using ParseToken span]` | Reconstructs source text from token span. |
| `parserPeek` | 98 | pub | `[inference: bounds clamp to last token]` | Returns current token without consuming. Clamps to last token at EOF. |
| `parserPeekN` | 103 | pub | `[inference: peek with offset n, bounds clamp]` | Lookahead N tokens. |
| `parserAdvance` | 109 | pub | `[inference: consume token, update last_end]` | Consumes current token, advances `pos`, updates `last_end`. |
| `tokenKindLabel` | 116 | private | `[inference: match on common TokenKinds, returns display strings]` | String label for error messages. Covers `;(){}[],.:|`, identifiers/literals, and 9 keywords. Falls back to "token". |
| `parserExpect` | 143 | pub | `[inference: kind check, auto-consume, diagnostic on mismatch]` | Consumes and returns token if kind matches; else emits diagnostic `2000` + returns `error.UnexpectedToken`. |
| `parserAddError` | 160 | pub | `[inference: wraps diag_collectorAdd with error code 2000]` | Emits parse error diagnostic. |
| `parserSynchronize` | 165 | pub | `[inference: skips tokens until sync set {;,},fn,const,var,pub,test,eof}]` | Error recovery: advances past tokens until a statement boundary. |
| `parserParseExprPrec` | 179 | pub | `[inference: Pratt prec climbing; primary → postfix → infix loop; depth limit 12]` | **Core expression parser.** Recursion guard at depth >12 (panic). Calls `parserParsePrimary` → `parserParsePostfixChain`, then loops on infix operators via `getInfixInfo`. Handles `catch` and `orelse` specially (custom RHS parse). Calls `parserAddBinary` for normal binary ops. |
| `parserAddBinary` | 230 | private | `[inference: TokenKind→AstKind mapping via switch; debug marker BOP:tk/ak]` | Maps operator token to `AstKind` (30+ mappings). Emits `BOP:tk<tok_kind> ak<ast_kind>` debug marker. |
| `parserParsePrimary` | 284 | pub | `[inference: 30+ dispatch arms for literals, idents, prefixes, grouping, blocks, etc.]` | Primary expression dispatch. Handles all literal types, identifiers, type keywords (`bool`, `c_char`, `void` → ident), builtins, `@cInclude`, `error`, prefix unary (`-`, `!`, `~`, `&`, `try`), grouped `(expr)`, struct/enum/union type literals, `return`/`break`/`continue`, blocks. |
| `parserParsePostfixChain` | 331 | pub | `[inference: loops: .*, .field, [index], (args), {init}]` | Postfix operator chain: deref, field access, index/slice, fn call, struct init. |
| `parserParseDotAccess` | 355 | private | `[inference: consumes '.' + ident or '.' + '*', creates field_access or deref]` | `.field` or `.*` access. |
| `parserParseIndexOrSlice` | 371 | private | `[inference: [expr] or [expr..expr] or [expr..]]` | Index `a[i]` or slice `a[i..j]` / `a[i..]`. |
| `parserParseFnCall` | 394 | private | `[inference: zero-arg shortcut, varargs via child_buf]` | Function call `f(args...)`. Zero-arg returns early. Varargs packed via `astStoreAddExtraChildren`. |
| `parserParseCatchRHS` | 418 | private | `[inference: optional |capture|, then block or expr]` | RHS of `catch`. Handles `|err|` capture syntax. |
| `parserParseOrelseRHS` | 440 | private | `[inference: block or expr]` | RHS of `orelse`. |
| `parserParseFieldInitListNamed` | 447 | private | `[inference: .field = value, .field2 = value2, ...]` | Named field initializer list for struct init. |
| `parserParseStructInit` | 472 | private | `[inference: base + field init list]` | Struct init `Struct{ .x = 1, .y = 2 }`. |
| `u32ArrayListAppendInner` | 480 | private | `[inference: dynamic growth 2x, sand alloc]` | Growable u32 array append (replicated from growable_array). |
| `parserParseIntLiteral` | 497 | private | `[inference: int_val from TokenValue, astStoreAddIntLiteral]` | Integer literal node. |
| `parserParseFloatLiteral` | 503 | private | `[inference: debug marker PF:, astStoreAddFloatLiteral]` | Float literal node. **Debug marker:** writes `PF:<float_val>\n` to stderr. |
| `parserParseStringLiteral` | 514 | private | `[inference: string_id from TokenValue, astStoreAddStringLiteral]` | String literal node. |
| `parserParseCharLiteral` | 520 | private | `[inference: int_val from TokenValue, astStoreAddCharLiteral]` | Char literal node. |
| `parserParseBoolLiteral` | 526 | private | `[inference: true→flags=1, false→flags=0]` | Bool literal node. |
| `parserParseSingleToken` | 534 | private | `[inference: generic single-token AST leaf]` | Null/undefined/unreachable literals. |
| `parserParseIdentExpr` | 540 | private | `[inference: re-interns TokenValue.string_id for consistency]` | Identifier expression. Re-interms text (not using `value.string_id` directly). |
| `parserParsePrefixUnary` | 548 | private | `[inference: consume op, parse operand at Prec.prefix]` | Prefix unary: `-expr`, `!expr`, `~expr`, `&expr`. |
| `parserParseGroupedExpr` | 556 | private | `[inference: (expr) at Prec.assignment]` | Parenthesized expression. |
| `parserParseBuiltinCall` | 565 | private | `[inference: @import special case, type-vs-expr arg detection, extra children packing]` | Builtin call `@builtin(args)`. Detects `@import` by interned ID. Type args detected by prefix tokens (`*`, `[`, `?`, `!`, `fn`, `struct`, `enum`, `union`, `error`, `anytype`). |
| `parserParseImportExpr` | 614 | private | `[inference: @import("path") with optional module resolution]` | Import expression. Resolves module via `module_reg` if available. |
| `parserParseCInclude` | 651 | private | `[inference: @cInclude("header.h")]` | C include directive. |
| `parserParseErrorLiteral` | 680 | private | `[inference: error.identifier or error{...}]` | Error literal or error set declaration. |
| `parserParseTryExpr` | 694 | private | `[inference: try expr at Prec.prefix]` | Try expression. |
| `parserParseAnonymousLiteral` | 702 | private | `[inference: .{...} → struct_init if named fields, tuple_literal else]` | Anonymous struct/tuple literal. |
| `parserParseEnumLiteral` | 728 | private | `[inference: .identifier → enum_literal]` | Enum literal `.TagName`. |
| `parserParseArrayLiteral` | 736 | private | `[inference: bracket type + brace init]` | Array literal `[T]{a, b, c}`. |
| `parserParseIfExpr` | 766 | private (but referenced pub in parsePrimary) | `[inference: if(cond) then-expr [else else-expr]]` | If-expression (expression-context). No capture syntax here (see `parserParseIfStmt`). |
| `parserParseSwitchExpr` | 786 | pub | `[inference: switch(cond) { prongs }]` | Switch expression. Collects prongs via `parserParseSwitchProng`. **Debug:** writes `PSWE:n<payload>` markers. |
| `parserParseSwitchProng` | 818 | private | `[inference: case items (with optional .. range), => [|capture|] body]` | Single switch prong. Handles `else =>`, ranges (`..` exclusive, `...` inclusive), capture syntax `|name|`. Debug: `PCB:T/E/B/n/S`, `CPT:n`, `PPL:n` markers. |
| `parserParseType` | 905 | pub | `[inference: dispatch to ptr/bracket/optional/error-union/fn/error/struct/enum/union/anytype/typename + postfix !error-union]` | Type expression parser. Handles all type forms. `anytype` returns node 0. |
| `parserParsePtrType` | 928 | private | `[inference: * [const] base_type]` | Single-pointer type. |
| `parserParseBracketType` | 943 | private | `[inference: [*c]T, []T, [N]T]` | Bracket type: many-pointer `[*c]T`, slice `[]T`, array `[N]T`. |
| `parserParseOptionalType` | 978 | private | `[inference: ?T]` | Optional type. |
| `parserParseErrorUnionType` | 986 | private | `[inference: !T]` | Error union type (payload side). |
| `parserParseFnType` | 994 | private | `[inference: fn(params) ret_type]` | Function type. |
| `parserParseErrorSetDecl` | 1027 | private | `[inference: error{ Tag1, Tag2 }]` | Error set declaration (no params). |
| `parserParseErrorSetDeclBody` | 1032 | private | `[inference: { identifier, ... } payload]` | Error set body parsing. |
| `parserParseStructType` | 1056 | private | `[inference: struct { name: type, ... }]` | Struct type (anonymous). |
| `parserParseEnumType` | 1086 | private | `[inference: enum[(backing)] { tag[=expr], ... }]` | Enum type (anonymous). |
| `parserParseUnionType` | 1126 | private | `[inference: union[(enum)] { name[:type], ... }]` | Union type (anonymous). |
| `parserParseTypeName` | 1174 | private | `[inference: identifier[.field]* → field_access chain]` | Qualified type name `Module.Type`. |
| `parserParseStatement` | 1192 | pub | `[inference: dispatch on keyword/identifier/lbrace/semicolon → 20+ statement forms]` | Statement parser. Dispatches to var/pub/extern/fn/if/while/for/switch/return/break/continue/defer/errdefer/test/struct/enum/union/block/labeled/expr. **Debug:** writes `PSTK:k<tok_kind>` marker. |
| `parserEmitErrorNode` | 1225 | pub | `[inference: diagnostic + err AstNode]` | Emits error node for error recovery. |
| `parserParseModuleRoot` | 1232 | pub | `[inference: top-level decl loop, error recovery with parserSynchronize]` | Top-level module parser. Collects decls into `decl_buf`, wraps in `module_root` node. On parse error, emits error node + synchronize. |
| `parserParseExprStmt` | 1255 | private | `[inference: expr ;]` | Expression statement. |
| `parserParseLabeledStmt` | 1261 | private | `[inference: label : stmt]` | Labeled statement. |
| `parserParseLabeledBlockExpr` | 1271 | private | `[inference: ident : { ... }]` | Labeled block (expression context). |
| `parserParseVarDecl` | 1284 | private | `[inference: [pub] [extern] const/var name [:type] [=init] ;]` | Variable declaration. Flags: bit0=mutable, bit1=pub, bit2=extern. Handles `c_include` inline (returns the include node directly). Debug: `V`, `v`, `PDVx` markers. |
| `parserParsePubDecl` | 1321 | private | `[inference: pub fn|const|var|test|extern]` | Public declaration dispatcher. |
| `parserParseExternDecl` | 1333 | private | `[inference: extern ["lib"] fn|const|var]` | Extern declaration dispatcher. |
| `parserParseFnDecl` | 1346 | private | `[inference: [pub] [extern] fn name(params) [:ret_type] {body} or ;]` | Function declaration. Parses params, return type, body or forward decl `;`. Creates `FnProto` in store. Flags: bit1=pub, bit2=extern, bit5=test. Debug: `Fv`, `P:<param_count>`, `Fk` markers. |
| `parserParseIfStmt` | 1420 | private | `[inference: if(cond) [|capture|] then [else if/else/block/expr] ;]` | If statement (statement-context, with capture syntax). Debug: extensive `PIF:c/k/c1/k1/c2/k2` markers. |
| `parserParseWhileStmt` | 1486 | private | `[inference: while(cond) [|capture|] [:(expr)] body ;]` | While loop. Supports error capture, continue expression. Debug: `zzz_*` markers. |
| `parserParseForStmt` | 1537 | private | `[inference: for(range) [|elem,index|] body ;]` | For loop. Range supports `..` syntax. Element/index capture via `|elem, idx|`. |
| `parserParseSwitchStmt` | 1586 | private | `[inference: parses switch-expr, wraps in expr_stmt]` | Switch statement (wraps switch expression in `expr_stmt`). |
| `parserParseReturnExpr` | 1590 | private | `[inference: return [expr]]` | Return expression (no semicolon consumed). |
| `parserParseBreakExpr` | 1604 | private | `[inference: break [:label]]` | Break expression (no semicolon). |
| `parserParseContinueExpr` | 1621 | private | `[inference: continue [:label]]` | Continue expression (no semicolon). |
| `parserParseReturnStmt` | 1638 | private | `[inference: return_expr + semicolon]` | Return statement. |
| `parserParseBreakStmt` | 1643 | private | `[inference: break_expr + semicolon]` | Break statement. |
| `parserParseContinueStmt` | 1648 | private | `[inference: continue_expr + semicolon]` | Continue statement. |
| `parserParseDeferStmt` | 1653 | private | `[inference: defer stmt]` | Defer statement (generic, used for both `defer` and `errdefer`). |
| `parserParseErrdeferStmt` | 1664 | private | `[inference: errdefer stmt]` | Errdefer statement. |
| `parserParseTestDecl` | 1667 | private | `[inference: test "name" { ... }]` | Test declaration (name is optional string literal). |
| `parserParseContainerDecl` | 1684 | private | `[inference: struct/enum/union name { ... } — named container declaration]` | Named struct/enum/union. Handles enum backing type `enum(u8)`, union(enum), identifier name. |
| `parserParseBlock` | 1745 | private | `[inference: { stmts } with local_buf[64] fast path and child_buf overflow]` | Block `{ stmts }`. Optimized: first 64 stmts in stack buffer, overflow to `child_buf`. Debug: `PBX:S/T/K/L/B/P`, `PLEN:l` markers. |
| `precToInt` | 1802 | pub | `[inference: enumToInt]` | Precedence → u8. |
| `precFromInt` | 1806 | pub | `[inference: intToEnum]` | u8 → precedence. |
| `getInfixInfo` | 1815 | pub | `[inference: TokenKind → OpInfo mapping, 8 precedence groups, right-assoc for assign/orelse/catch]` | Maps operator tokens to precedence + associativity. Assignment ops (including compound) are right-assoc at `assignment(1)`. `orelse` right-assoc at `(2)`. `catch` right-assoc at `(3)`. All others left-assoc. |

### Precedence Table (parser.zig:1784-1800, 1815-1842)

| Level | Name | Operators | Assoc |
|-------|------|-----------|-------|
| 0 | `none` | (sentinel) | — |
| 1 | `assignment` | `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `<<=`, `>>=`, `&=`, `|=`, `^=` | right |
| 2 | `prec_orelse` | `orelse` | right |
| 3 | `prec_catch` | `catch` | right |
| 4 | `bool_or` | `or` | left |
| 5 | `bool_and` | `and` | left |
| 6 | `comparison` | `==`, `!=`, `<`, `<=`, `>`, `>=` | left |
| 7 | `bit_or` | `\|` | left |
| 8 | `bit_xor` | `^` | left |
| 9 | `bit_and` | `&` | left |
| 10 | `shift` | `<<`, `>>` | left |
| 11 | `additive` | `+`, `-` | left |
| 12 | `multiply` | `*`, `/`, `%` | left |
| 13 | `prefix` | (unary: `-`, `!`, `~`, `&`, `try`) | — |
| 14 | `postfix` | (chain: `.`, `[]`, `()`, `{}`) | — |

### Debug Markers in Parser

| Marker | Function | Description |
|--------|----------|-------------|
| `PF:<val>` | parserParseFloatLiteral | Float literal value being parsed |
| `BOP:tk<tok_kind> ak<ast_kind>` | parserAddBinary | Binary operator mapping |
| `PSWE:n<payload> p<payload>` | parserParseSwitchExpr | Switch expr node + payload |
| `PCB:T/E/<n/S>` | parserParseSwitchProng | Prong parse: Token kind, Else, + n/S sub-markers |
| `CPT:n<capture>` | parserParseSwitchProng | Capture name in prong |
| `PPL:n<payload>` | parserParseSwitchProng | Items payload value |
| `PSTK:k<kind>` | parserParseStatement | Statement token kind |
| `VARC`, `VARV` | parserParseStatement | Variable decl type marker |
| `PIF:c/k/c1/k1/c2/k2` | parserParseIfStmt | If condition children/kind debug |
| `PIF:b<node>k<kind>` | parserParseIfStmt | Then-body node/kind |
| `PBX:S/T/K/L/B/P` | parserParseBlock | Block stmt count, token kind, node kind, length, saved len, span |
| `PLEN:l<len>p<payload>` | parserParseBlock | Block length and payload |
| `PTC2:e<val>` | parserParseWhileStmt | While continue expr |
| `V`, `v`, `PDVx` | parserParseVarDecl | Variable decl progress |
| `Fv`, `P:<n>`, `Fk` | parserParseFnDecl | Fn decl progress |
| `DP:child_buf_stale` | parserParseFnDecl | Warning if child_buf not cleared |
| `ZZZ_*` | parserParseWhileStmt | Internal debug string literals |

---

## ast.zig (`sf/src/ast.zig`, 412 lines)

AST node storage and traversal.

### Types

| Type | Line | Description |
|------|------|-------------|
| `AstKind` (enum u8) | 1 | 97 variants (0..96). **BUG (ast.zig:76):** `swt_ex=56` collides with `mod_assign=56`. |
| `AstNode` (struct) | 101 | 24 bytes: `kind(u8)`, `flags(u8)`, `span_len(u16)`, `span_start(u32)`, `child_0/1/2(u32)`, `payload(u32)`. Offsets: 0,1,2,4,8,12,16,20. Verification string at line 113. |
| `FnProto` (struct) | 115 | `name_id(u32)`, `params_start(u16)`, `params_count(u16)`, `return_type_node(u32)` |
| `AstStore` (struct) | 212 | 8 parallel arrays: `nodes([]AstNode)`, `extra_children([]u32)`, `identifiers([]u32)`, `int_values([]u64)`, `float_values([]f64)`, `string_values([]u32)`, `fn_protos([]FnProto)`, `allocator(*Sand)` |

### AstNode Payload Semantics (ast.zig:251-265)

| AstKind | Payload Usage |
|---------|---------------|
| `int_literal`, `char_literal` | Index into `int_values` |
| `float_literal` | Index into `float_values` |
| `string_literal` | Index into `string_values` (interned string ID) |
| `ident_expr` | Index into `identifiers` (interned string ID) |
| `fn_decl` | Index into `fn_protos` |
| `fn_call`, `block`, `struct_decl`, `enum_decl`, `union_decl`, `swt_ex`, `tuple_literal`, `struct_init`, `array_init`, `module_root`, `swt_prong`, `error_set_decl` | Extra children packed: `(start << 16) \| count` |
| `builtin_call` | Interned string ID of builtin name |
| `var_decl`, `field_decl`, `param_decl`, `field_access`, `enum_literal`, `error_literal` | Name ID |
| `labeled_stmt`, `break_stmt`, `continue_stmt` | Label name ID (0=unlabeled) |
| `import_expr` | Path string ID |
| `if_capture`, `while_capture`, `for_stmt` | Capture name ID |

### AstNode Layout

```
Offset  Size  Field
0       1     kind (AstKind/u8)
1       1     flags (u8: bit0=const, bit1=pub, bit2=extern, bit3=export, bit4=has_capture, bit5=index_capture, bit6=inclusive, bit7=mutable)
2       2     span_len (u16)
4       4     span_start (u32)
8       4     child_0 (u32)
12      4     child_1 (u32)
16      4     child_2 (u32)
20      4     payload (u32)
        = 24 bytes total (32-bit layout)
```

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `u32ArrayListAppendInner` | 127 | private | `[inference: 2x growth, sand alloc]` | Growable u32 array append (duplicated from parser module). |
| `astNodeArrayListAppendInner` | 144 | private | `[inference: 2x growth, sand alloc for AstNode]` | Growable AstNode array append. |
| `u64ArrayListAppendInner` | 161 | private | `[inference: 2x growth, sand alloc for u64]` | Growable u64 array append. |
| `f64ArrayListAppendInner` | 178 | private | `[inference: 2x growth, sand alloc for f64]` | Growable f64 array append. |
| `fnProtoArrayListAppendInner` | 195 | private | `[inference: 2x growth, sand alloc for FnProto]` | Growable FnProto array append. |
| `astStoreInit` | 267 | pub | `[inference: allocates null node at index 0, initializes 7 parallel arrays]` | Creates empty `AstStore`. Node 0 is always `AstKind.err` (null sentinel). |
| `astStoreAddNode` | 289 | pub | `[inference: span_len = end - start, append to nodes array, return index]` | Creates and stores an `AstNode`. Returns node index (u32). |
| `astStoreAddExtraChildren` | 301 | pub | `[inference: append to extra_children, pack (start<<16\|count)]` | Stores variable-length child list. Returns packed `(start << 16) \| count` payload. |
| `astStoreGetExtraChildren` | 311 | pub | `[inference: unpack payload, slice extra_children]` | Retrieves extra children from payload. |
| `astStoreAddIntLiteral` | 317 | pub | `[inference: appends to int_values, calls astStoreAddNode]` | Creates int literal node. |
| `astStoreAddCharLiteral` | 323 | pub | `[inference: appends to int_values, calls astStoreAddNode]` | Creates char literal node. |
| `astStoreAddFloatLiteral` | 329 | pub | `[inference: appends to float_values, debug marker AS:]` | Creates float literal node. **Debug:** writes `AS:<val>\n` to stderr. |
| `astStoreAddStringLiteral` | 340 | pub | `[inference: appends to string_values, calls astStoreAddNode]` | Creates string literal node. |
| `astStoreAddIdentifier` | 346 | pub | `[inference: appends to identifiers, calls astStoreAddNode]` | Creates identifier node. |
| `astStoreAddFnProto` | 352 | pub | `[inference: appends to fn_protos, returns index]` | Stores function prototype metadata. |
| `nodeHasExtraChildren` | 358 | pub | `[inference: switch on 11 AstKinds returning true]` | Returns whether an `AstKind` uses `extra_children` storage. |
| `visitPreOrder` | 376 | pub | `[inference: explicit stack[512], pushes children in reverse order, callback per node]` | Pre-order traversal with explicit stack. Pushes extra children first (in reverse), then child_2, child_1, child_0 (non-zero only). |
| `astStoreComputeMemory` | 402 | pub | `[inference: sums nodes*28 + per-array sizes; note: nodes uses 28 not 24]` | Memory usage estimation. **Note:** node size hardcoded as 28 despite AstNode being 24 bytes — likely includes overhead estimate. |

---

## Data Flow

```
Source text ([]const u8)
    │
    ▼
┌─────────────────────────────────────────────────┐
│  Lexer (lexer.zig)                               │
│  ┌─────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ Skip    │→│ Char       │→│ Token       │ │
│  │ WS/Cmt  │  │ Dispatch   │  │ Construction│ │
│  └─────────┘  └──────────────┘  └─────────────┘ │
│  Helper: lexerScanString, lexerScanNumber, etc.   │
│  Diagnostics: ERR_1000-1005, WARN_1010-1011      │
└─────────────────────────────────────────────────┘
    │
    ▼
Token array ([]Token)
    │
    ▼
┌─────────────────────────────────────────────────────┐
│  Parser (parser.zig)                                │
│  ┌────────────┐  ┌───────────────┐  ┌────────────┐│
│  │ parserParse│→│ parserParse  │→│ parserParse││
│  │ ModuleRoot │  │ Statement     │  │ ExprPrec   ││
│  └────────────┘  └───────────────┘  └────────────┘│
│  Pratt climbing: getInfixInfo → precedence loop     │
│  Error recovery: parserSynchronize                  │
│  Debug markers: LEX, PF:, BOP:tk, PSTK:k, etc.     │
└─────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────┐
│  AstStore (ast.zig)                                 │
│  7 parallel arrays:                                 │
│  ┌───────┐ ┌────────────────┐ ┌──────────────────┐ │
│  │ nodes │ │ extra_children │ │ identifiers/int/  │ │
│  │(AstNode)│ │ (u32 packed)    │ │ float/string/fn  │ │
│  └───────┘ └────────────────┘ └──────────────────┘ │
│  nodeHasExtraChildren, visitPreOrder                 │
└─────────────────────────────────────────────────────┘
    │
    ▼
AST tree (root node index = module_root node)
```

---

## Debugging

### CLI Flags (referenced in pipeline)

| Flag | Effect |
|------|--------|
| `--dump-tokens` | Dumps token stream after lexing |
| `--dump-ast` | Dumps AST tree after parsing |

### Lexer Debug Markers

| Marker | File | Trigger |
|--------|------|---------|
| `LEX` | lexer.zig:399 | When identifier text is exactly `"neighbors"` |

### Parser Debug Markers

See table in parser section above. All go to stderr via `pal.markerWrite`.

### AstStore Debug

| Marker | File | Trigger |
|--------|------|---------|
| `AS:<val>\n` | ast.zig:332-334 | Float literal stored |

### Diagnostic Error Codes (Lexer)

| Code | Constant | Description |
|------|----------|-------------|
| `ERR_1000` | `UNTERMINATED_STRING` | String literal not closed |
| `ERR_1001` | `UNTERMINATED_BLOCK_COMMENT` | `/*` without `*/` |
| `ERR_1002` | `INVALID_CHAR_LITERAL` | Empty char literal or missing close |
| `ERR_1003` | `INVALID_ESCAPE` | `\x` without hex digits |
| `ERR_1004` | `BARE_AT_SIGN` | `@` without builtin name |
| `ERR_1005` | `UNRECOGNIZED_CHAR` | Invalid character |
| `WARN_1010` | `UNRECOGNIZED_ESCAPE` | Unknown escape sequence |
| `WARN_1011` | `INTEGER_OVERFLOW` | Integer literal overflow |

### Parser Error Codes

| Code | Description |
|------|-------------|
| `2000` | All parse errors (via `parserAddError`) |

---

## Known Issues / Bugs

1. **Token packed layout** (token.zig:115-117): Desired 16-byte packed struct rejected by zig0 due to union field in `TokenValue`. Actual size: 24 bytes.

2. **AstKind collision** (ast.zig:56,76): `AstKind.swt_ex = 56` collides with `AstKind.mod_assign = 56`. Two enum variants share the same discriminant. This will cause incorrect AST kind matching for switch expressions vs. modulus-assign operators.

3. **`nodes` size overestimate** (ast.zig:404): `astStoreComputeMemory` uses 28 bytes per node, but `AstNode` is 24 bytes. Discrepancy of 4 bytes per node.

4. **`lexerScanIdentifierOrKeyword` re-interns** (parser.zig:543): Parser re-interms identifier text rather than using `TokenValue.string_id` directly. Redundant but ensures consistency.

5. **No IEEE float edge cases**: `parseF64` uses naive multiplication loops for scientific notation — potential precision issues on extreme exponents.
