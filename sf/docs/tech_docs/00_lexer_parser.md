# 00 — Lexer & Parser [updated: 2026-08-15 — F-AST: AST store pre-sized from import-closure token count (discovery pass `moduleScanDiscover` + `astStoreEnsureNodesCapacity`/`astStoreEnsureExtraChildrenCapacity`, in-place-or-copy); prior 2026-08-14 — F-PARSER+F-PARSEARENA: struct/union/enum/error-set/fn-type member buffers are now growable arena arrays (was `[64]u32` stack, ASan overflow on >64 members); parser stack arena `p_arena_buf` enlarged 4096→16384 B; prior — F-TOKEN: two-pass exact-size token array (count_only lexer pass suppresses diagnostics/intern/string_buf); prior 2026-08-07 — labeled_stmt stores label name in payload; prior varargs `...` in fn params (bit0 flag); fn-pointer `...` rejected]

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `TokenKind` variants | 92 | 0..91, `err_token(91)` for error recovery |
| Keywords | 36 | `const, var, fn, pub, extern, export, test, struct, enum, union, if, else, while, for, switch, return, break, continue, defer, errdefer, try, catch, orelse, error, and, or, true, false, null, undefined, unreachable, void, bool, noreturn, c_char, anytype` |
| `AstKind` variants | 97 (0..96) | `err=0` through `c_include=96`. **[FIXED] `mod_assign=74` (was 56, collided with `swt_ex=56`)** (F5, ast.zig:58) |
| `AstNode` size | 24 bytes | Not packed — zig0 rejects packed structs with union fields (token.zig:115-117) |
| Prec levels | 15 | `none(0)` .. `postfix(14)` (parser.zig:1784-1800) |
| Debug markers | ~15+ | Parser: `PF:`, `BOP:tk`, `PSWE:n`, `PCB:E/T`, `PSTK:k`, `PIF:c`, `PBX:S/T/K`, `PLEN:l`, `ZZZ_*`; lexer: bare `LEX` (only for `"neighbors"`); **`LEX:n/k` in traces is from `lower.zig:448`, not the lexer** (P9) |

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
| `parserPushU32` | 497 | private | `[inference: append via u32ArrayListAppendInner into Parser.allocator (parser arena)]` | Growable u32 list append for member/field/param collectors (F-PARSER). |
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
| `parserParseFnType` | 994 | private | `[inference: fn(params) ret_type]` | Function type. `...` (varargs) in fn-pointer params → error `"varargs not allowed in function pointer types"` (`parser.zig:1004-1012`). Params collected via `parserPushU32` growable arena array (no `[64]u32` cap). |
| `parserParseErrorSetDecl` | 1027 | private | `[inference: error{ Tag1, Tag2 }]` | Error set declaration (no params). |
| `parserParseErrorSetDeclBody` | 1032 | private | `[inference: { identifier, ... } payload]` | Error set body parsing. Members collected via `parserPushU32` growable arena array. |
| `parserParseStructType` | 1056 | private | `[inference: struct { name: type, ... }]` | Struct type (anonymous). Fields collected via `parserPushU32` growable arena array (no `[64]u32` cap). |
| `parserParseEnumType` | 1086 | private | `[inference: enum[(backing)] { tag[=expr], ... }]` | Enum type (anonymous). Members collected via `parserPushU32` growable arena array (was `members_buf[64]` ASan overflow). |
| `parserParseUnionType` | 1126 | private | `[inference: union[(enum)] { name[:type], ... }]` | Union type (anonymous). Fields collected via `parserPushU32` growable arena array (was `fields_buf[64]` ASan overflow). |
| `parserParseTypeName` | 1174 | private | `[inference: identifier[.field]* → field_access chain]` | Qualified type name `Module.Type`. |
| `parserParseStatement` | 1192 | pub | `[inference: dispatch on keyword/identifier/lbrace/semicolon → 20+ statement forms]` | Statement parser. Dispatches to var/pub/extern/fn/if/while/for/switch/return/break/continue/defer/errdefer/test/struct/enum/union/block/labeled/expr. **Debug:** writes `PSTK:k<tok_kind>` marker. |
| `parserEmitErrorNode` | 1225 | pub | `[inference: diagnostic + err AstNode]` | Emits error node for error recovery. |
| `parserParseModuleRoot` | 1232 | pub | `[inference: top-level decl loop, error recovery with parserSynchronize]` | Top-level module parser. Collects decls into `decl_buf`, wraps in `module_root` node. On parse error, emits error node + synchronize. |
| `parserParseExprStmt` | 1255 | private | `[inference: expr ;]` | Expression statement. |
| `parserParseLabeledStmt` | 1261 | private | `[inference: label : stmt]` | Labeled statement. **[F1, 2026-08-07] Stores the label name in the node payload:** `astStoreAddNode(..., labeled_stmt, inner, 0, 0, label_tok.value.string_id)` at parser.zig:1285-1287 (was hardcoded `0`). `child_0` = the wrapped statement. |
| `parserParseLabeledBlockExpr` | 1271 | private | `[inference: ident : { ... }]` | Labeled block (expression context). **[F1, 2026-08-07] Same payload fix:** `label_tok.value.string_id` stored at parser.zig:1299-1300 (was hardcoded `0`). `child_0` = the block body. |
| `parserParseVarDecl` | 1284 | private | `[inference: [pub] [extern] const/var name [:type] [=init] ;]` | Variable declaration. Flags: bit0=mutable, bit1=pub, bit2=extern. Handles `c_include` inline (returns the include node directly). Debug: `V`, `v`, `PDVx` markers. |
| `parserParsePubDecl` | 1321 | private | `[inference: pub fn|const|var|test|extern]` | Public declaration dispatcher. |
| `parserParseExternDecl` | 1333 | private | `[inference: extern ["lib"] fn|const|var]` | Extern declaration dispatcher. |
| `parserParseFnDecl` | 1346 | private | `[inference: [pub] [extern] fn name(params) [:ret_type] {body} or ;]` | Function declaration. Parses params, return type, body or forward decl `;`. Creates `FnProto` in store. Flags: bit1=pub, bit2=extern, bit5=test, **bit0=variadic** (`...` in the param list sets `flags |= 0x01` and stops param parsing — `parser.zig:1378-1382`). Debug: `Fv`, `P:<param_count>`, `Fk` markers. |
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
| `parserParseContainerDecl` | 1684 | private | `[inference: struct/enum/union name { ... } — named container declaration]` | Named struct/enum/union. Handles enum backing type `enum(u8)`, union(enum), identifier name. Fields/members collected via `parserPushU32` growable arena array. |
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
| `AstKind` (enum u8) | 1 | 97 variants (0..96). [FIXED] `mod_assign=74`, distinct from `swt_ex=56` (F5). |
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
| `builtin_call` | Extra children packed `(start << 16) \| count` for args; **builtin name ID is in `child_0`** (parser.zig:611) |
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
| `astStoreEnsureNodesCapacity` | 289 | pub | `[inference: in-place realloc if arena-tail (sandReallocInPlace), else copy]` | Pre-sizes the `nodes` array to `new_capacity` (min 8). Tries `sandReallocInPlace` first; falls back to copy-into-bump. `[updated: 2026-08-15 — F-AST]` |
| `astStoreEnsureExtraChildrenCapacity` | 313 | pub | `[inference: in-place realloc if arena-tail, else copy]` | Pre-sizes the `extra_children` array to `new_capacity` (min 8). Tries `sandReallocInPlace` first; falls back to copy-into-bump. `[updated: 2026-08-15 — F-AST]` |
| `astStoreAddNode` | 337 | pub | `[inference: span_len = end - start, append to nodes array, return index]` | Creates and stores an `AstNode`. Returns node index (u32). |
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
│  Debug markers: PF:, BOP:tk, PSTK:k, etc.             │
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

> **Two-pass exact-size token array `[updated: 2026-08-14 — F-TOKEN]`** — `moduleRegistryParseModule`
> (`import_resolver.zig:21-38`) lexes each module twice: PASS 1 is a **count-only** lexer pass
> (`Lexer.count_only = true`, `lexer.zig`) that suppresses **all** diagnostics, interning, and
> `string_buf` writes (it is a pure token count; PASS 2 then performs every side effect in exactly
> the pre-change source order, so output stays byte-identical); the token array is then `sandAlloc`'d
> at exactly `token_count × 24` B (no ×2 doubling, no dead bump copies). The module source is read
> directly into the perm arena (`import_resolver.zig:87`, `readFile(path_s, reg.alloc)`) and the
> source manager takes ownership of that slice (no scratch→perm copy), removing the in-scratch source
> transient. Together these close the import scratch OOM (c89_emit.zig 73,912 tokens → 1,773,888 B
> exact array; lower.zig 79,606 → 1,910,544 B).

> **AST-store pre-sizing `[updated: 2026-08-15 — F-AST]`** — before the parse loop,
> `moduleRegistryResolveImports` (`import_resolver.zig:132-145`) runs a side-effect-free import-closure
> discovery (`moduleScanDiscover`, `import_resolver.zig:27`) that walks the import graph via a path
> stack + seen-set, lexes each file only to find `@import("...")` builtins, resolves targets via the
> module resolver (interning resolved paths in parse order — no module creation, no diagnostics, no
> AST writes), and sums the closure token count. The AST store is then pre-sized in **one** allocation
> to a token-count heuristic — `nodes` ≈ `total_tokens × 6/10`, `extra_children` ≈ `total_tokens/4`
> (`astStoreEnsureNodesCapacity` / `astStoreEnsureExtraChildrenCapacity`, `ast.zig:289/:313`, which try
> `sandReallocInPlace` first and fall back to copy). Measured ratios are stable per token across the
> gate programs (~0.51-0.55 nodes/token, ~0.18-0.22 extra-children/token) unlike per-line ratios
> (~3.8 rogue_mud vs ~6.6 self-compile), so the arrays land near their final size and the
> copy-into-bump ×2 growth waste is eliminated. Verified: 4 MD5 gates byte-identical; corpus 253
> OK=247/FAIL=2/GG=4; rogue_mud `mod=` 506K→370K; self-compile module arena top segment 16M→8M.

> **Growable member/field buffers + parser arena `[updated: 2026-08-14 — F-PARSER+F-PARSEARENA]`** —
> the five parser member-list collectors that were fixed `[64]u32` stack buffers
> (`parserParseStructType`, `parserParseEnumType`, `parserParseUnionType`,
> `parserParseContainerDecl` field/member lists) plus the same-class `parserParseFnType`
> `param_buf` and `parserParseErrorSetDeclBody` `member_buf` are now arena-backed growable arrays.
> New helper `parserPushU32` (`parser.zig:497`) appends through the shared
> `u32ArrayListAppendInner` (dynamic ×2 growth) into the parser's sand arena
> (`Parser.allocator`, the per-module `p_arena`), with copy on realloc. The `[64]u32` overflow
> class is gone — modules with >64 struct fields / enum members / union fields / error-set members /
> fn-type params no longer ASan stack-buffer-overflow (`parserParseEnumType` / `parserParseUnionType`
> were the observed sites on ast.zig/parser.zig/main.zig). `parserParseBlock` keeps its original
> stack `local_buf[64]` + `child_buf` spill (already overflow-safe; unchanged to avoid extra arena
> pressure). The parser stack arena `p_arena_buf` (`import_resolver.zig:39`) is enlarged
> **4096 → 16384 B** (16 KB per-module stack frame, auto-reclaimed on return — zero BSS/static-arena
> impact); this removes the `OOM: total=4096` parser-arena failure on large modules. **Known limits
> (out of scope):** lower.zig/main.zig still exceed 16 KB parser-arena peak (lower.zig ≈17.7 KB);
> c89_emit.zig additionally hits a pre-existing `u16` `span_len` overflow (`ast.zig:290`,
> `span_len: u16 = @intCast(u16, span_end - span_start)`), masked by the former 4096 OOM — both are
> deferred (do NOT enlarge `p_arena_buf` beyond 16 KB per task ruling).

---

## Debugging

### CLI Flags (referenced in pipeline) — [updated: 2026-08-01]

| Flag | Effect |
|------|--------|
| `--dump-types` | Dumps type info after type resolution (DEAD — declared at main.zig:774, never matched in parseArgs) |
| `--dump-lir` | Dumps LIR after lowering (DEAD — declared at main.zig:775, never matched in parseArgs) |
| `--dump-c89` | Dumps generated C89 |

> **P9 correction:** the main pipeline (`main.zig` `parseArgs`, main.zig:744-873) does **NOT**
> implement `--dump-tokens` or `--dump-ast`. Token/AST dumping lives in separate harness binaries
> (`dump_tokens.zig`, `ast_dump_main.zig`), not in zig1's CLI. Previous versions of this table were
> inaccurate.

### Lexer Debug Markers

| Marker | File | Trigger |
|--------|------|---------|
| `LEX` | lexer.zig:398 | When identifier text is exactly `"neighbors"` |

> **P9 clarification:** the `LEX:n<node>k<kind>` markers seen in `--markers` traces are emitted by
> **`lower.zig:448`** (`lowerExpr` entry), NOT the lexer. The lexer's own marker is a bare `LEX`
> (no `:n…k…` suffix) and fires only for the identifier `"neighbors"` — which appears in none of
> the 4 examples (`[markers]`: 0 bare `LEX` per trace).

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

2. **AstKind collision** (ast.zig:58,76): [FIXED — F5] Previously `AstKind.swt_ex = 56` collided with `AstKind.mod_assign = 56`. Now `mod_assign = 74` (free discriminant between `for_stmt=73` and `swt_prong=75`), `swt_ex` unchanged at 56. All 97 discriminants are unique.

3. **`nodes` size overestimate** (ast.zig:404): `astStoreComputeMemory` uses 28 bytes per node, but `AstNode` is 24 bytes. Discrepancy of 4 bytes per node.

4. **`lexerScanIdentifierOrKeyword` re-interns** (parser.zig:543): Parser re-interms identifier text rather than using `TokenValue.string_id` directly. Redundant but ensures consistency.

5. **No IEEE float edge cases**: `parseF64` uses naive multiplication loops for scientific notation — potential precision issues on extreme exponents.

---

## 6. Empirical Deep-Dive: Lexer + Parser for 4 Examples (P9)

> Evidence methods: `[fprintf]` = instrumented debug zig1 (bootstrap recipe, `/tmp/z9`; `fprintf` added
> to generated `import_resolver.c` `moduleRegistryParseModule` + `parser.c` `parserSynchronize`;
> byte-identical `--dump-c89` vs P0 baselines: mud `87954d75…`, gol `9cc38ab9…`, lisp `6a8ca449…`,
> json `9492e3b3…`), `[markers]` = P0 `--markers` traces (`/tmp/dd/*.mrk`) + instrumented reruns,
> `[gdb]` = breakpoints on generated C. Examples:
> `examples/z98/{mud_server,game_of_life,json_parser,lisp_interpreter_curr}/main.zig` (+ module files).
> Tokens counts include the trailing `eof` token (1 per module). AST node counts exclude node 0
> (the `err` sentinel); `IRN:n` markers (import_resolver.zig:157) include it (+1).

### 6.1 Token Streams (Q1)

Per-module token counts `[fprintf]` (P9M output; module ids per P3's import order, paths via the
registry): totals incl. eof.

| Example | Module (mod id) | Tokens | AST nodes |
|---------|-----------------|--------|-----------|
| mud_server (4 modules, **1819 tokens**) | main.zig (0) | 1625 | 843 |
| | util.zig (2) | 144 | 80 |
| | std.zig (1) | 10 | 3 |
| | std_debug.zig (3) | 40 | 17 |
| game_of_life (3 modules, **1621 tokens**) | main.zig (0) | 1545 | 774 |
| | std.zig (1) | 10 | 3 |
| | std_debug.zig (2) | 66 | 29 |
| lisp_interpreter_curr (10 modules, **7311 tokens**) | main.zig (0) | 1509 | 810 |
| | sand.zig (1) | 205 | 104 |
| | value.zig (2) | 409 | 223 |
| | token.zig (3) | 600 | 355 |
| | parser.zig (4) | 335 | 178 |
| | env.zig (5) | 280 | 143 |
| | eval.zig (6) | 2243 | 1137 |
| | builtins.zig (7) | 1231 | 655 |
| | util.zig (8) | 306 | 150 |
| | deep_copy.zig (9) | 193 | 98 |
| json_parser (3 modules, **2841 tokens**) | main.zig (0) | 580 | 292 |
| | file.zig (1) | 418 | 192 |
| | json.zig (2) | 1843 | 1083 |

Top-5 TokenKinds per example `[fprintf]` (kind ids per token.zig:5-98; aggregated across modules):

| Example | #1 | #2 | #3 | #4 | #5 |
|---------|----|----|----|----|----|
| mud_server | identifier(492) | lparen(133) | rparen(133) | semicolon(118) | comma(108) |
| game_of_life | identifier(400) | comma(160) | integer_literal(111) | rparen(110) | lparen(110) |
| lisp_interpreter_curr | identifier(2061) | dot(535) | lparen(456) | rparen(456) | comma(434) |
| json_parser | identifier(773) | lparen(245) | rparen(245) | semicolon(212) | dot(128) |

`identifier` is #1 in every example (23–31% of tokens); `lparen`/`rparen` are always near-tied
(balanced delimiters). No `percent_eq` token (kind 42, `%=`) appears anywhere — see Q5.

### 6.2 AST Trees (Q2)

| Example | Total AST nodes | incl. sentinel (IRN:n) | Max depth (module) | Most-frequent AstKind |
|---------|-----------------|------------------------|--------------------|-----------------------|
| mud_server | **943** | 944 | **23** (main.zig) | `ident_expr` (309) |
| game_of_life | **806** | 807 | **15** (main.zig) | `ident_expr` (271) |
| lisp_interpreter_curr | **3853** | 3854 | **41** (eval.zig) | `ident_expr` (1128) |
| json_parser | **1567** | 1568 | **15** (main.zig) | `ident_expr` (521) |

- Depth measured `[fprintf]` via a recursive traversal from the module_root node (root = depth 0);
  cross-checked vs `IRN:n`/`IRV:n` markers `[markers]` (import_resolver.zig:145-158) — totals agree
  modulo the node-0 sentinel.
- Max-depth per module (lisp, largest): eval.zig 41, main.zig 21, util.zig 16, builtins.zig 14,
  parser.zig 12, token.zig 11; the shallow `std.zig` stubs are depth 2 everywhere.
- `ident_expr` dominates in all 4 (identifier-heavy sources); `fn_call`/`field_access`/`block`
  follow in the bigger examples. lisp is the deepest (nested switch/expression chains in `eval`).

### 6.3 Precedence Climbing: `a + b * c` vs `(a + b) * c` (Q3)

Repro `/tmp/z9/prec_repro.zig` (constructed for this task):
```zig
fn f() i32 {
    var a: i32 = 1;
    var b: i32 = 2;
    var c: i32 = 3;
    var x = a + b * c;
    var y = (a + b) * c;
    return x + y;
}
```

AST node dump `[fprintf]` (P9NODE, `k`=AstKind, `c0/c1/c2`=child indices, `p`=payload):
- `x = a + b * c` → node 15 = **add**(k33, c0=11, c1=14); node 14 = **mul**(k35, c0=12=b, c1=13=c).
  So `add(a, mul(b, c))` — `*` binds tighter than `+`.
- `y = (a + b) * c` → node 22 = **mul**(k35, c0=20, c1=21=c); node 20 = **paren_expr**(k32, c0=19);
  node 19 = **add**(k33, c0=17=a, c1=18=b). So `mul(paren(add(a,b)), c)` — parens re-order the tree.

`[markers]` `BOP:tk<kind>ak<astkind>` order confirms climbing (parser.zig:230-282): for `a + b * c`
the `BOP:tk22ak35` (star→mul) fires BEFORE `BOP:tk20ak33` (plus→add) — the `+`'s RHS is parsed at
`min_prec = multiply(12)` (left-assoc `+` bumps to `prec+1`, parser.zig:206), so `b * c` is consumed
inside the nested `parserParseExprPrec` call and the `mul` node is created before the `add` folds
up. For `(a + b) * c` the inner `add` is created first inside the paren, then `mul`.

Mechanism `[source]`: `parserParseExprPrec` (parser.zig:179-228) loops `getInfixInfo` (parser.zig:1815),
`next_min = prec+1` for left-assoc (parser.zig:202-207); `parserParseGroupedExpr` (parser.zig:556)
produces the `paren_expr` node (k32). Repro max AST depth (from module_root) = 7, well under the
expr-recursion depth-12 panic guard (parser.zig:181-183).

### 6.4 parserSynchronize (Q4)

`[fprintf]`: entry counter added to generated `parserSynchronize` (parser.zig:165) → **0 hits in all
4 examples** (P9SYNC count 0 each). No error recovery triggered anywhere.

- `[markers]`: no `error[2000]` parse diagnostics and no `ERR_1000-1005` lexer diagnostics in the
  P0 traces; every example compiled clean.
- Control test (instrumentation validity) `[fprintf]`: a malformed repro (`var x = ` then newline)
  produced 2 `P9SYNC:` hits + `error[2000]` — so the zero counts are real, not a no-op probe.

### 6.5 swt_ex=56 / mod_assign=74 Collision (Q5) — [FIXED by F5]

**Originally:** `swt_ex=56` collided with `mod_assign=56`. **F5 fix:** `mod_assign=74`; `swt_ex` unchanged at 56. All 97 discriminants now unique.

`[gdb]` + `[fprintf]` + `[markers]` (pre-fix investigation):

- No `%=` token (kind 42) in any token stream `[fprintf]` (P9TOK histograms) → `parserAddBinary`
  (parser.zig:257) never emits `mod_assign`.
- GDB break on generated `parserAddBinary` guarded `tok.kind==42`: **never hit** (lisp run).
  Break on `parserParseSwitchExpr` (parser.zig:786): **56 hits** (lisp) — every kind-56 node is a
  switch expression.
- Cross-check `[markers]`: `PSWE:` (switch-expr marker, parser.zig:814) counts == kind-56 AST node
  counts per example: mud 1==1, gol 3==3, lisp 56==56, json 2==2.

**Verdict: the `swt_ex`/`mod_assign` collision does NOT affect any of the 4 examples.** All 62
kind-56 nodes across the 4 examples are `swt_ex`. The hazard stays latent: any downstream
`switch` that distinguishes the two variants by enum value would misbehave, but no example
contains `%=` or relies on the distinction.

### 6.6 AstNode Payload Semantics (Q6)

Verified against actual AST usage `[fprintf]` (repro node + store-array dumps) and `[source]`
consumers:

| AstKind | Doc table claim | Actual usage | Verdict |
|---------|-----------------|--------------|---------|
| `int_literal`, `char_literal` | Index into `int_values` | prec_repro nodes p0/p1/p2 → `int_values` `{1,2,3}` | ✓ |
| `float_literal` | Index into `float_values` | f_repro nodes p0/p1 → `float_values` `{1.5,2.25}` | ✓ |
| `string_literal` | Index into `string_values` | payload_repro node p0 → `string_values[0]=24` | ✓ |
| `ident_expr` | Index into `identifiers` | identifiers array holds interned ids (5 5 26 5 5 25 …) | ✓ |
| `fn_decl` | Index into `fn_protos` | payload_repro nodes p0/p1 → `fn_protos` (g, f) | ✓ |
| `block` | Extra children packed | node 10 payload 65537 = `(1<<16)\|1` → `extra[1]=9` | ✓ |
| `module_root` | Extra children packed | node 30 payload 655364 = `(10<<16)\|4` → 4 top-level decls | ✓ |
| `fn_call` | Extra children packed | node 19 payload 196609 = `(3<<16)\|1` → `extra[3]=18` | ✓ |
| `builtin_call` | **"Interned string ID of builtin name"** | payload = packed extra children (args); builtin name ID is in **child_0** (parser.zig:611) | **✗ doc wrong** |
| `var_decl`, `param_decl` | Name ID | payloads 20-25 (std/s/t/x/y), 26/28 (x/p) — interned name ids | ✓ |
| `field_access` | Name ID | semantic_analyzer.zig:233-234 reads `node.payload` as field name id, base in child_0 | ✓ |
| `import_expr` | Path string ID | payload_repro node 1 p22 = interned path | ✓ |

- **Doc bug confirmed and fixed (table row above):** `builtin_call`'s payload is the packed
  extra-children index for its arguments, NOT the builtin name ID. `parserParseBuiltinCall`
  (parser.zig:565-611) packs args via `astStoreAddExtraChildren` (parser.zig:606-608) and passes the
  interned name id as `child_0` (parser.zig:611). Consumers confirm: semantic_analyzer.zig:1217 reads args from
  `node.payload`, semantic_analyzer.zig:1218 compares `node.child_0` to `size_of_name_id`. Same pattern verified
  in lower.zig:2381 and comptime_eval.zig:175.
- `parserParseVarDecl` (parser.zig:1318-1319) uses child_0=type, child_1=init, payload=name_id —
  matches doc.
- The `block`/`module_root`/`fn_call` packed-payload arithmetic `(start<<16)|count` confirmed
  against `astStoreAddExtraChildren` (ast.zig:301) and `astStoreGetExtraChildren` (ast.zig:311).

### 6.7 Doc gaps found during P9 (also fixed inline above/below)

1. **`--dump-tokens` / `--dump-ast` don't exist in the main pipeline** (was §5 CLI Flags): `main.zig`
   `parseArgs` (main.zig:744-873) only handles `--dump-types`/`--dump-lir`/`--dump-c89` (plus
   non-dump flags). Token/AST dumping lives in separate harnesses (`dump_tokens.zig`,
   `ast_dump_main.zig`), not in zig1's CLI. **Fix applied (see §5 table).**
2. **`builtin_call` payload row was wrong** (was §ast payload table) — fixed in §6.6.
3. **`LEX` marker attribution**: the doc lists `LEX` as a lexer marker (lexer.zig:396-399). It IS
   emitted there (for identifier `"neighbors"` only), but the `LEX:n<node>k<kind>` markers that
   flood the P0 traces come from **lower.zig:448** (`lowerExpr` entry), not the lexer. Clarified in
   §5. No example contains `neighbors`, so the lexer's own `LEX` never fires (`[markers]`: 0 bare
   `LEX` in all 4 traces).

