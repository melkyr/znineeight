# 00 — Lexer & Parser [updated: 2026-09-22 — Task 9B (a, m1240 ruling 5): assignment is excluded from every condition position — `parserParseIfExpr`, `parserParseSwitchExpr`, `parserParseIfStmt`, `parserParseWhileStmt` parse the condition at `Prec.prec_orelse` (was `Prec.assignment`/`Prec.none`), and `parserParseGroupedExpr` parses the parenthesized inner expression at `Prec.prec_orelse`, so `if (a = 3)` / `while (a = 0)` / `switch (a = 3)` / `var x = (a = 3);` are parse errors (error[2000]) matching official Zig] [updated: 2026-09-20 — refresh against current source: 112 AstKind variants, disk-backed AstStore, streaming parser, packed/volatile/calling-convention/`enum(uN)` grammar, dump-tooling coverage; line references and dated evidence removed]

> Covers: `token.zig`, `lexer.zig`, `parser.zig`, `ast.zig`, `print_decomposition.zig`, `dump_ast.zig`, `dump_tokens.zig`, `ast_dump_main.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `TokenKind` variants | 108 | 0..107, `err_token(107)` for error recovery |
| Keywords | 38 | `const, var, fn, pub, extern, export, test, struct, enum, union, packed, if, else, while, for, switch, return, break, continue, defer, errdefer, try, catch, orelse, error, and, or, true, false, null, undefined, unreachable, void, bool, noreturn, c_char, anytype, volatile` |
| `AstKind` variants | 112 (0..111) | `err=0` through `sat_shl_assign=111`. `mod_assign=74`, distinct from `swt_ex=56` |
| `AstNode` size | 24 bytes | Not a packed struct (2-byte pad at offset 2); the AST payload is a store side-table, not a field |
| Prec levels | 15 | `none(0)` .. `postfix(14)` |
| Debug markers | ~15+ | Parser: `PF:`, `BOP:tk`, `PSWE:n`, `PCB:E/T/B`, `PSTK:k`, `PIF:c`, `PBX:S/T/K`, `PLEN:l`, `ZZZ_*`; lexer: bare `LEX` (only for `"neighbors"`); `LEX:n/k` in traces comes from `lower.zig`, not the lexer |


---

## token.zig (`sf/src/token.zig`)

Defines the token universe: `TokenKind` enum (108 kinds), `Token` struct (24 bytes), keyword table.

### Types

| Type | Description |
|------|-------------|
| `TokenKind` (enum u16) | 108 variants: single-char and 2-char operators (`shl`, `shr`), compound assign (`plus_eq`..`shr_eq`), wrap (`plus_pct`/`minus_pct`/`star_pct` + `_eq`) and saturating (`plus_pipe`/`minus_pipe`/`star_pipe`/`shl_pipe` + `_eq`) families, dot forms (`dot_dot`, `dot_dot_dot`, `dot_lbrace`, `dot_star`), 38 keywords (`kw_const`..`kw_volatile`), `c_include_builtin`, `eof`, `err_token(107)` |
| `SyncContext` (enum u8) | 5 recovery contexts: `stmt_list`, `expression`, `switch_prong`, `fn_body`, `module_root` |
| `TokenValue` (union) | `int_val(u64)`, `float_val(f64)`, `string_id(u32)`, `none(void)` |
| `Token` (struct) | 24 bytes: `kind(TokenKind,u16)`, `span_start(u32)`, `span_len(u16)`, `value(TokenValue,union)`. **FIXME (`token.zig`):** the desired packed layout (16 bytes) is rejected by zig0 because `TokenValue` is a union. Restore when zig1 self-hosts. |
| `KeywordEntry` (struct) | `name([]const u8)`, `kind(TokenKind)` |

### Functions

| Function | Scope | Description |
|----------|-------|-------------|
| `initKeywordTable` | pub | Initializes the global `keyword_table` with 38 keyword entries (`sandAlloc`'d, manually unrolled per entry); sets `keyword_count`. Called once at startup. |
| `lookupKeyword` | pub | Linear search of `keyword_table` for `text` via `mem_eql`; returns `?TokenKind` or null. |

---

## lexer.zig (`sf/src/lexer.zig`)

Scanner: source text → `Token` stream. Single-pass, character-by-character. All state in `Lexer`.

### Types

| Type | Description |
|------|-------------|
| `Lexer` | Fields: `source([]const u8)`, `pos(usize)`, `line(u32)`, `col(u32)`, `file_id(u32)`, `interner(*StringInterner)`, `diag(*DiagnosticCollector)`, `string_buf(*U8ArrayList)`, `count_only(bool)` |

### Functions

| Function | Scope | Description |
|----------|-------|-------------|
| `lexerInit` | pub | Creates a `Lexer` from source, file_id, interner, diag, alloc; allocates `string_buf` via sand. `count_only` starts `false`. |
| `lexerNextToken` | pub | Main scan loop. Skips WS/comments, reads one char, dispatches to single-char tokens, compound operators (`..`, `...`, `.{}`, `.*`, `==`, `=>`, `!=`, `<<`, `>>`, `<<\|`, `<=`, `>=`, `+=`..`^=`, and the `%`/`\|` wrap/saturating forms, each with `lexerMatch`), `@` → builtin identifier (only when followed by alpha) or bare-`@` error, `"` → `lexerScanString`, `'` → `lexerScanChar`, alpha/`_` → `lexerScanIdentifierOrKeyword`, digit → `lexerScanNumber`, else → error token + `ERR_1005`. All diagnostics/interns are suppressed when `count_only`. |
| `lexerAdvance` | private | Consumes one byte. Returns `0` at EOF. Updates `line`/`col`. |
| `lexerPeek` / `lexerPeekN` | private | Lookahead 1 / N without consuming (0 at EOF). |
| `lexerIsAtEnd` | private | EOF predicate (`pos >= source.len`). |
| `lexerMatch` | private | If peek == expected, advance and return true; else false. |
| `lexerSkipWSC` | private | Skips whitespace and `//` line comments and nested `/* */` block comments (depth tracking). Emits `ERR_1001` on an unterminated block comment. |
| `lexerMakeToken` | private | Constructs a `Token` from the current position (`span_len = pos - start`). |
| `lexerMakeErrorToken` | private | Constructs `err_token` with `span_len = 1`. |
| `lexerScanString` | private | Scans `"..."`, accumulating decoded bytes into `string_buf` and interning the result. Emits `ERR_1000` on newline/EOF before the closing quote. |
| `lexerScanChar` | private | Scans `'x'` or `'\n'`; emits `ERR_1002` for empty `''` and for a missing closing `'`. |
| `lexerScanNumber` | private | Scans integer/float literals. Base detection (hex `0x`/`0X`, binary `0b`/`0B`, octal `0o`/`0O`); `_` separators; decimal `.` fraction; `e`/`E` exponent with optional sign (scanned after the optional fraction, so `1.0e300`/`1.5e-3` keep their exponent); integer overflow via `isU64MaxLiteral` + `WARN_1011`. |
| `lexerScanIdentifierOrKeyword` | private | Scans `[a-zA-Z_][a-zA-Z0-9_]*`; single `_` → `underscore`; keyword lookup; otherwise an `identifier`. Emits a bare `LEX` to stderr when the identifier is exactly `"neighbors"` (debug hook). |
| `lexerScanBuiltinIdentifier` | private | Scans `@` + alphanumerics; `@cInclude` (9 chars) → `c_include_builtin`, else `builtin_identifier`. |
| `isAlpha` / `isDigit` / `isAlphaNum` | private | Character-class predicates (`_` counts as alpha). |
| `hexDigitValue` | private | Hex char → 0-15, `0xFF` on invalid. |
| `lexerParseHexEscape` | private | Parses `\xHH` (up to 2 hex digits); emits `ERR_1003` if no digits follow `\x`. |
| `lexerParseEscapeSequence` | private | Parses `\n`,`\t`,`\r`,`\\`,`\"`,`\'`,`\0`,`\x`; unrecognized escapes emit `WARN_1010` and return the raw char. |
| `isDigitInBase` | private | Range check per base 2/8/10/16. |
| `parseU64` | private | Parses text to `u64` (skips base prefix, handles `_`), clamping overflow to `0xFFFF_FFFF_FFFF_FFFF`. |
| `parseF64` | private | Hand-written float parser: sign, integer part, optional fraction, `e`/`E` exponent with a naive `10^exp` loop. No IEEE edge cases. The fraction loop decrements `i` before breaking on `e`/`E`, so a decimal-point mantissa followed by an exponent parses with its exponent. |
| `isU64MaxLiteral` | private | Distinguishes a true max-u64 literal from overflow. |
| `assertEqBool` / `assertEqU32` / `assertEqU8` / `assertEqTokenKind` | private | Inline test assertions (stderr output on mismatch). |
| `formatU32` | private | Simple u32→string formatter for test output. |
| `lexerRunAllTests` | pub | Test harness: runs 9 test groups + external `lexer_tests.runLexerUnitTests`. |
| `lexerTestSanityCheck` | pub | Sanity check — always fails (intentional panic). |
| `lexerTestHelpers` / `lexerTestSkipWhitespaceAndComments` / `lexerTestOperators` / `lexerTestScanNumber` / `lexerTestScanString` / `lexerTestScanChar` / `lexerTestIdentifierKeywords` / `lexerTestBuiltinIdentifier` / `lexerTestDiagnostics` | private | The 9 inline test groups (cursor primitives, whitespace/comments, operators, numbers, strings, chars, identifiers/keywords, builtins, error tokens). |

**Debug markers in lexer:** when the identifier text is exactly `"neighbors"`, the lexer writes a bare `LEX` to stderr. This is a debug/tracing hook.


---

## parser.zig (`sf/src/parser.zig`)

Recursive-descent parser with **Pratt-style precedence climbing** for expressions. Source text →
streamed tokens (from `lexer.zig`) → `AstStore` (AST node tree). The parser can also run over a
pre-lexed token slice (`parserInit`), but the module path uses the streaming form
(`parserInitStreaming`).

### Types

| Type | Description |
|------|-------------|
| `ParserError` | `UnexpectedToken` |
| `ParseToken` | Lightweight token: `kind`, `span_start`, `span_len` (no `TokenValue`) |
| `Parser` | Core parser state. `use_lex` selects streaming (`*Lexer`) vs token-slice mode. Holds a 3-token lookahead window (`la`, `la_len`), `source_ptr`/`source_len`, `pos`, `store`, `interner`, `diag`, `allocator`, growable `child_buf_*`/`decl_buf_*` u32 lists, `last_end`/`last_tok`/`last_tok_valid`, `builtin_import_id`, `catch_capture(u32)`, `expr_depth(u32)`, `module_reg`, `import_scratch`, `current_module_id`, `file_id`. |
| `Prec` (enum u8) | 15 precedence levels: `none(0)`, `assignment(1)`, `prec_orelse(2)`, `prec_catch(3)`, `bool_or(4)`, `bool_and(5)`, `comparison(6)`, `bit_or(7)`, `bit_xor(8)`, `bit_and(9)`, `shift(10)`, `additive(11)`, `multiply(12)`, `prefix(13)`, `postfix(14)` |
| `OpInfo` | `prec(Prec)` + `right_assoc(bool)` |
| `CALL_CONV_CDECL` / `CALL_CONV_STDCALL` / `CALL_CONV_INVALID` | u8 calling-convention codes (0/1/2) |

### Functions

| Function | Scope | Description |
|----------|-------|-------------|
| `parserInitCommon` | private | Shared constructor; sets streaming mode off, pre-interns `@import`, zeroes buffers. |
| `parserInit` | pub | Creates a `Parser` over a pre-lexed `Token` slice. Initializes `child_buf`/`decl_buf` lazily. |
| `parserInitStreaming` | pub | Creates a `Parser` over a `*Lexer` (`use_lex = true`); tokens are pulled on demand. |
| `parserSetModuleContext` | pub | Attaches the module registry, current module id, and file id for `@import` resolution. |
| `parserSetImportScratch` | pub | Attaches the import scratch arena used by `@import` resolution. |
| `parserTokenText` | pub | Reconstructs source text from a `ParseToken` span. |
| `parserPullOne` | private | Fills the lookahead window: pulls from the lexer (streaming) or the token slice; marks EOF. |
| `parserConsumeCurrent` | private | Drops the front lookahead token, records `last_tok`, pulls the next. |
| `parserPeek` / `parserPeekN` | pub | Current token / lookahead N without consuming (bounds-clamped). |
| `parserAdvance` | pub | Consumes the current token, updates `last_end`. |
| `tokenKindLabel` | private | Display label for common `TokenKind`s in error messages; falls back to "token". |
| `parserExpect` | pub | Consumes and returns the token if the kind matches; else diagnostic `2000` + `error.UnexpectedToken`. |
| `parserAddError` | pub | Emits a parse diagnostic with code `2000`. |
| `parserAddErrorCode` | pub | Emits a parse diagnostic with an explicit code (used for `3045`). |
| `parserSynchronize` | pub | Error recovery: skips tokens until `;`, `}`, `fn`, `const`, `var`, `pub`, `test`, or EOF. |
| `parserParseExprPrec` | pub | **Core expression parser.** Pratt precedence climbing: `parserParsePrimary` → `parserParsePostfixChain`, then loops on infix operators via `getInfixInfo`. Handles `catch`/`orelse` RHS specially; calls `parserAddBinary`. Recursion guard panics above depth 12. |
| `parserAddBinary` | private | Maps an operator token to an `AstKind` (plain, compound, wrap `+%`/`-%`/`*%`, saturating `+\|`/`-\|`/`*\|`/`<<\|`, assign, comparison, bool) and emits `BOP:tk<tok_kind> ak<ast_kind>`. |
| `parserParsePrimary` | pub | Primary dispatch: literals, identifiers, `bool`/`c_char`/`void` type keywords, builtins, `@cInclude`, `error`, prefix unary (`-`, `-%`, `!`, `~`, `&`, `try`), grouped `(expr)`, `.{}`/`.Tag`, `if`/`switch` expressions, array/ptr/optional/extern-fn/fn/struct/enum/union/packed types, `return`/`break`/`continue`, blocks. |
| `parserParsePostfixChain` | pub | Postfix chain: `.*`, `.field`, `[index]`/slice, `(args)`, `{init}`. |
| `parserParseDotAccess` | private | `.field` (field_access) or `.*` (deref). |
| `parserParseIndexOrSlice` | private | `a[i]`, `a[i..j]`, `a[i..]`. |
| `parserParseFnCall` | private | Function call; zero-arg shortcut, args packed via `astStoreAddExtraChildren`. |
| `parserParseCatchRHS` | private | RHS of `catch`; optional `\|err\|` payload capture. |
| `parserParseOrelseRHS` | private | RHS of `orelse` (block or expr). |
| `parserParseFieldInitListNamed` | private | `.field = value, ...` initializer list. |
| `parserParseStructInit` | private | `Struct{ .x = 1, ... }`. |
| `u32ArrayListAppendInner` | private | Growable u32 array append (×2 growth, sand alloc). |
| `parserPushU32` | private | Append through `u32ArrayListAppendInner` into the parser arena (member/field/param collectors). |
| `parserParseIntLiteral` / `parserParseCharLiteral` | private | Integer / char literal nodes from `TokenValue.int_val`. |
| `parserParseFloatLiteral` | private | Float literal node; emits `PF:<val>` marker. |
| `parserParseStringLiteral` | private | String literal node from `TokenValue.string_id`. |
| `parserParseBoolLiteral` | private | Bool literal (`true`→flags=1, `false`→flags=0). |
| `parserParseSingleToken` | private | Generic single-token leaf (`null`, `undefined`, `unreachable`). |
| `parserParseIdentExpr` | private | Identifier expression; re-interns the token text. |
| `parserParsePrefixUnary` | private | Prefix `-`, `-%`, `!`, `~`, `&`; operand parsed at `Prec.prefix`. |
| `parserParseGroupedExpr` | private | Parenthesized `(expr)` at `Prec.prec_orelse`. `[updated: 2026-09-22 — Task 9B (m1240 ruling 5): the inner precedence is `Prec.prec_orelse` (was `Prec.assignment`), so a parenthesized assignment expression (`var x = (a = 3);`) is rejected at the `)` expect — assignment is a statement, not an expression, matching official Zig.]` |
| `parserParseBuiltinCall` | private | `@builtin(args)`; detects `@import` by interned ID; type args by prefix tokens (`*`, `[`, `?`, `!`, `fn`, `struct`, `enum`, `union`, `error`, `anytype`); args packed as extra children with the builtin name id in `child_0`. |
| `parserParseImportExpr` | private | `@import("path")`; resolves the module through `module_reg`/`import_scratch` when attached. |
| `parserParseCInclude` | private | `@cInclude("header.h")`; payload = header name id. |
| `parserParseErrorLiteral` | private | `error.Tag` or `error{...}`; may build an error-union type. |
| `parserParseTryExpr` | private | `try expr` at `Prec.prefix`. |
| `parserParseAnonymousLiteral` | private | `.{}` / `.{...}` → `struct_init` if named fields, else `tuple_literal`. |
| `parserParseEnumLiteral` | private | `.TagName` → `enum_literal`. |
| `parserParseArrayLiteral` | private | `[T]{a, b, c}` array literal. |
| `parserParseIfExpr` | private | Expression-context `if (cond) [\|capture\|] then [else else]`; supports optional-capture `\|name\|` in value position (`if_expr` payload = capture node, 0 when absent). `[updated: 2026-09-22 — Task 9B (a): the condition is parsed at `Prec.prec_orelse` (was `Prec.assignment`), excluding assignment from condition positions; `if (a = 3)` fails at the `)` expect with error[2000].]` |
| `parserParseSwitchExpr` | pub | `switch(cond) { prongs }`; emits `PSWE:n<payload> p<payload>`. `[updated: 2026-09-22 — Task 9B (a): the condition is parsed at `Prec.prec_orelse` (was `Prec.assignment`), so `switch (a = 3)` is a parse error.]` |
| `parserParseSwitchProng` | private | One prong: `else` or case items with `..`/`...` ranges, `=> [\|capture\|] body`. Debug: `PCB:T/E/B/n/S`, `CPT:n`, `PPL:n`. |
| `parserParseType` | pub | Type-expression dispatch: ptr/bracket/optional/error-union/extern-fn/fn/error-set/struct/enum/union/packed/anytype/type-name + trailing `!` error-union. `anytype` returns node 0. |
| `parserParsePtrQualifiers` | private | Consumes leading `const`/`volatile` qualifiers (bit0=const, bit1=volatile). |
| `parserParsePtrType` | private | `*[const] [volatile] T` single pointer. |
| `parserParseBracketType` | private | `[*c]T` (many-ptr, with qualifiers), `[]T`/`[]const T` slice, `[N]T` array. |
| `parserParseOptionalType` | private | `?T`. |
| `parserParseErrorUnionType` | private | `!T` (payload side). |
| `parserParseExternFnType` | private | `extern ["conv"] fn(...) ...`; classifies the convention (`c`/`cdecl`/`stdcall`); unknown → `3045`, defaults to cdecl. |
| `parserParseFnType` | private | `fn(params) ret` function type; `...` in fn-pointer params → `"varargs not allowed in function pointer types"`. Params growable; `fn_type` flags bit0=stdcall. |
| `parserParseErrorSetDecl` / `parserParseErrorSetDeclBody` | private | `error{ Tag1, Tag2 }`; members growable. |
| `parserParseStructType` | private | `struct { name: type, ... }`; `is_packed` sets flags bit4; fields growable. |
| `parserParseEnumType` | private | `enum[(backing)] { tag[=expr], ... }`; optional backing type in `child_0`; members growable. |
| `parserParseUnionType` | private | `union[(enum)] { name[:type], ... }`; tagged flag bit0, packed flag bit4; `packed` + `(enum)` rejected; fields growable. |
| `parserParseTypeName` | private | Identifier with `.field` chain → `field_access`. |
| `parserParseStatement` | pub | Statement dispatch (var/pub/extern/export/fn/if/while/for/switch/return/break/continue/defer/errdefer/test/struct/enum/union/block/labeled/expr). Emits `PSTK:k<kind>`. |
| `parserEmitErrorNode` | pub | Diagnostic + `err` node for error recovery. |
| `parserParseModuleRoot` | pub | Top-level decl loop into `decl_buf`, wrapped in `module_root`; on error emits an `err` node and synchronizes. |
| `parserParseExprStmt` | private | Expression statement (`expr ;`). |
| `parserParseLabeledStmt` / `parserParseLabeledBlockExpr` | private | `label: stmt` / `label: { ... }`; `labeled_stmt` payload = label name id. |
| `parserParseVarDecl` | private | `[pub] [extern] [export] const/var name [:type] [=init] ;`. Flags: bit0=mutable, bit1=pub, bit2=extern, bit3=export. Handles `@cInclude` init inline. Debug: `V`, `v`, `PDVx`. |
| `parserParsePubDecl` | private | `pub fn/const/var/test/extern/export` dispatcher. |
| `parserParseExternDecl` | private | `extern ["conv"] fn/const/var`; classifies the convention, unknown → `3045`. |
| `parserParseExportDecl` | private | `export fn/const/var`. |
| `parserParseFnDecl` | private | `[pub] [extern] [export] fn name(params) [:ret] {body} or ;`. Flags: bit0=variadic, bit1=pub, bit2=extern, bit3=export, bit5=test. Stores `FnProto` (with `call_conv`). Debug: `Fv`, `P:<n>`, `Fk`, `DP:child_buf_stale`. |
| `parserClassifyCallConv` | private | Maps `"c"`/`"cdecl"`/`"stdcall"` to a convention code, else `CALL_CONV_INVALID`. |
| `parserParseIfStmt` | private | Statement-context `if (cond) [\|capture\|] then [else ...] ;`. Debug: `PIF:c/k/c1/k1/c2/k2`, `PIF:b...k...`. Rejects `;` before `else`. `[updated: 2026-09-22 — Task 9B (a): the condition is parsed at `Prec.prec_orelse` (was `Prec.none`), excluding assignment from condition positions.]` |
| `parserParseWhileStmt` | private | `while (cond) [\|capture\|] [:(continue_expr)] body ;`. Debug: `PTC2:e`, `ZZZ_*`. `[updated: 2026-09-22 — Task 9B (a): the condition is parsed at `Prec.prec_orelse` (was `Prec.none`), excluding assignment from condition positions.]` |
| `parserParseForStmt` | private | `for (range) [\|elem, idx\|] body ;`; range `..` wrapped in `range_exclusive`; `child_2` = index name id. |
| `parserParseSwitchStmt` | private | Parses a switch expression and wraps it in `expr_stmt`. |
| `parserParseReturnExpr` / `parserParseReturnStmt` | private | `return [expr]` / plus `;`. |
| `parserParseBreakExpr` / `parserParseBreakStmt` | private | `break [:label]` / plus `;`; `break_stmt` payload = label id. |
| `parserParseContinueExpr` / `parserParseContinueStmt` | private | `continue [:label]` / plus `;`; `continue_stmt` payload = label id. |
| `parserParseDeferStmt` / `parserParseErrdeferStmt` | private | `defer` / `errdefer` statement. |
| `parserParseTestDecl` | private | `test ["name"] { ... }`; `test_decl` payload = name id (0 if unnamed). |
| `parserParseContainerDecl` | private | Named `struct`/`enum`/`union` container decl; handles `enum(backing)` and `union(enum)`; `child_0` = name id, `child_1` = enum backing type, payload = field/member range. |
| `parserParseBlock` | private | `{ stmts }`; first 64 stmts in a stack buffer, overflow to `child_buf`. Debug: `PBX:S/T/K/L/B/P`, `PLEN:l...p...`. |
| `precToInt` / `precFromInt` | pub | `Prec` ↔ u8. |
| `getInfixInfo` | pub | Maps operator tokens to `OpInfo` (precedence + associativity); right-assoc for assignment/`orelse`/`catch`. |

Feature notes: type aliases are ordinary `const Name = Type;` declarations (a `var_decl` with
bit0=const and a type/init child) — there is no dedicated alias `AstKind`; they are resolved in the
front pass (see `03_type_resolution.md`). String literals are interned at lex time and stored as a
`string_literal` node holding a `string_values` index; the parser attaches no type — string-literal
typing happens in semantic analysis. Enum backing (`enum(uN)`) is parsed into the `enum_decl`
`child_0`; integer widths are assigned in type resolution. Switch ranges become
`range_exclusive`/`range_inclusive` nodes inside a `swt_prong`.

### Precedence Table

| Level | Name | Operators | Assoc |
|-------|------|-----------|-------|
| 0 | `none` | (sentinel) | — |
| 1 | `assignment` | `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `<<=`, `>>=`, `&=`, `\|=`, `^=`, `+%=`, `-%=`, `*%=`, `+\|=`, `-\|=`, `*\|=`, `<<\|=` | right |
| 2 | `prec_orelse` | `orelse` | right |
| 3 | `prec_catch` | `catch` | right |
| 4 | `bool_or` | `or` | left |
| 5 | `bool_and` | `and` | left |
| 6 | `comparison` | `==`, `!=`, `<`, `<=`, `>`, `>=` | left |
| 7 | `bit_or` | `\|` | left |
| 8 | `bit_xor` | `^` | left |
| 9 | `bit_and` | `&` | left |
| 10 | `shift` | `<<`, `>>`, `<<\|` | left |
| 11 | `additive` | `+`, `-`, `+%`, `-%`, `+\|`, `-\|` | left |
| 12 | `multiply` | `*`, `/`, `%`, `*%`, `*\|` | left |
| 13 | `prefix` | (unary: `-`, `-%`, `!`, `~`, `&`, `try`) | — |
| 14 | `postfix` | (chain: `.`, `[]`, `()`, `{}`) | — |

### Debug Markers in Parser

| Marker | Function | Description |
|--------|----------|-------------|
| `PF:<val>` | parserParseFloatLiteral | Float literal value being parsed |
| `BOP:tk<tok_kind> ak<ast_kind>` | parserAddBinary | Binary operator mapping |
| `PSWE:n<payload> p<payload>` | parserParseSwitchExpr | Switch expr node + payload |
| `PCB:T/E/B/n/S` | parserParseSwitchProng | Prong parse: token kind, else, item count, flags |
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

## ast.zig (`sf/src/ast.zig`)

AST node storage and traversal. Node and value storage is **disk-backed**: fixed-size
node/payload blocks and append-only value pools are written through to spill files and faulted
back in through a small resident window.

### Types

| Type | Description |
|------|-------------|
| `AstKind` (enum u8) | 112 variants (0..111). `mod_assign=74`, distinct from `swt_ex=56`. |
| `AstNode` (struct) | 24 bytes: `kind(AstKind/u8)`, `flags(u8)`, `span_len(u32)`, `span_start(u32)`, `child_0/1/2(u32)`. Offsets 0,1,4,8,12,16,20. The payload is no longer a field — it lives in the store's parallel payload block. |
| `FnProto` (struct) | `name_id(u32)`, `params_start(u32)`, `params_count(u16)`, `call_conv(u8)`, `return_type_node(u32)` |
| `AstStore` (struct) | Disk-backed node blocks + parallel payload blocks; `AstValuePool` for `extra_children`, `extra_ranges`, `identifiers`, `int_values`; in-memory growable arrays for `float_values`, `string_values`, `fn_protos`; `block_table`, 8 resident `slots`, and the node `spill`. |
| `AstValuePool` (struct) | Write-once append-only disk-backed pool (4- or 8-byte elements) with a resident tail block and an 8-slot fault-in cache; used by `identifiers`, `int_values`, `extra_children`, `extra_ranges`. |
| `NodeBlockInfo` (struct) | `disk_off(u32)`, `resident(u8)`, `slot(u32)` for one node block. |

Block constants: `AST_BLOCK_SHIFT=12`, `AST_BLOCK_NODES=4096`, `AST_BLOCK_NODE_BYTES=98304`,
`AST_BLOCK_PAYLOAD_BYTES=16384`, `AST_BLOCK_REC_SIZE=114688`, `AST_SPILL_MAX_BLOCKS=18724`,
`AST_WINDOW_SLOTS=8`, `AST_HEAD_SLOT=0`; `VALUE_POOL_BLOCK_BYTES=4096`, `VALUE_POOL_SLOTS=8`.

### Payload Semantics (stored in `store.payload`, parallel to `nodes`)

| AstKind | Payload Usage |
|---------|---------------|
| `int_literal`, `char_literal` | Index into `int_values` |
| `float_literal` | Index into `float_values` |
| `string_literal` | Index into `string_values` (interned string ID) |
| `ident_expr` | Index into `identifiers` (interned string ID) |
| `fn_decl` | Index into `fn_protos` |
| `var_decl`, `field_decl`, `param_decl`, `field_access`, `enum_literal`, `error_literal`, `test_decl`, `c_include` | Name string ID |
| `labeled_stmt`, `break_stmt`, `continue_stmt` | Label name ID (0=unlabeled) |
| `if_capture`, `while_capture`, `for_stmt` | Capture name ID (`for_stmt` also stores the index name ID in `child_2`) |
| `import_expr` | Path string ID |
| `builtin_call` | Builtin name ID is in `child_0`; payload = extra-children range index |
| `fn_call`, `block`, `struct_decl`, `enum_decl`, `union_decl`, `swt_ex`, `tuple_literal`, `struct_init`, `array_init`, `module_root`, `swt_prong`, `error_set_decl` | Extra-children range index into `extra_ranges` (0 = no children) |

The extra-children range pool stores a packed `(start << 32) | count` with `start` as u32
(69,026+ ranges on self-compile exceed u16); slot 0 is reserved as the 0 sentinel so a payload of
0 means "no range". `nodeHasExtraChildren` reports the 12 kinds that use the pool; `builtin_call`
is handled separately by `astStoreNodePayloadPacked`/`astStoreNodeExtraChildCount`.

### AstNode Layout

```
Offset  Size  Field
0       1     kind (AstKind/u8)
1       1     flags (u8; kind-overloaded)
2       2     pad
4       4     span_len (u32)
8       4     span_start (u32)
12      4     child_0 (u32)
16      4     child_1 (u32)
20      4     child_2 (u32)
        = 24 bytes total (32-bit layout)
```

`flags` is generic (bit0=const, bit1=pub, bit2=extern, bit3=export, bit4=has_capture,
bit5=has_index_capture, bit6=inclusive, bit7=mutable) but overloaded per node kind by the parser:
`fn_decl` uses bit0=variadic, bit1=pub, bit2=extern, bit3=export, bit5=test; `fn_type` uses
bit0=stdcall; `struct_decl`/`union_decl` use bit4=packed (union also bit0=tagged); `swt_prong`
uses bit0=else, bit4=has_capture; `ptr_type`/`many_ptr_type` use bit0=const, bit1=volatile, and
`slice_type` uses bit0=const.

### Functions

| Function | Scope | Description |
|----------|-------|-------------|
| `astStoreInit` | pub | Creates the store. Node 0 is always `AstKind.err` (null sentinel); reserves extra-range slot 0 as the 0 sentinel; initializes the value pools, the resident window, and the default spill paths. |
| `astStoreSetSpillPath` / `astStoreSetValuePoolSpillPath` | pub | Override the node spill path / a named value-pool spill path (0=identifiers, 1=int_values, 2=extra_children, 3=extra_ranges). |
| `astStoreCloseSpill` | pub | Closes the node spill and all four value-pool spills. |
| `astStoreAddNode` | pub | Appends an `AstNode` + payload; returns the node index. `span_len = span_end - span_start`. |
| `astStoreNodeAt` / `astStoreNodePayload` | pub | Read a node / its payload, faulting the block into a resident slot if needed. |
| `astStoreNodePayloadPacked` | pub | Returns the `extra_ranges` value for extra-child kinds and `builtin_call`, else the raw payload. |
| `astStoreAddExtraChildren` | pub | Appends a child list to `extra_children` and a packed `(start<<32\|count)` range to `extra_ranges`; returns the range index. |
| `astStoreGetExtraChildCount` / `astStoreGetExtraChildAt` / `astStoreGetExtraChildrenCopy` | pub | Unpack a payload's range and read children. |
| `astStoreNodeExtraChildCount` / `astStoreNodeExtraChildAt` / `astStoreNodeExtraChildrenCopy` | pub | Same, keyed by node index. |
| `astStoreExtraChildAtRaw` / `astStoreExtraRangeAt` | pub | Raw pool reads by index. |
| `astStoreAddIntLiteral` / `astStoreAddCharLiteral` | pub | Append to `int_values` and create the literal node. |
| `astStoreAddFloatLiteral` | pub | Append to `float_values` and create the node; emits `AS:<val>` when markers are enabled. |
| `astStoreAddStringLiteral` | pub | Append to `string_values` and create the node. |
| `astStoreAddIdentifier` | pub | Append to `identifiers` and create an identifier-kind node. |
| `astStoreAddFnProto` | pub | Append to `fn_protos`; returns the index. |
| `astStoreIdentifier` / `astStoreIntValue` | pub | Dereference a node payload to its interned identifier / integer value. |
| `nodeHasExtraChildren` | pub | True for the 12 kinds backed by `extra_children`. |
| `nodeChildIsNode` | pub | Per-kind filter for which fixed child slots hold node indices (e.g. `builtin_call` child_0, `swt_prong` child_1, `for_stmt` child_2, container-decl child_0 are name IDs, not nodes). |
| `nodeHasNodeExtraChildren` | pub | `nodeHasExtraChildren` minus `error_set_decl` (whose pool holds tag name IDs). |
| `visitPreOrder` | pub | Explicit stack[512] pre-order walk; pushes node-extra children first (reverse), then child_2/1/0 (non-zero and `nodeChildIsNode` only). |
| `astStoreComputeMemory` | pub | Sums resident block records, the block table, and the in-memory arrays/value-pool windows. |

Private helpers: `u32ArrayListAppendInner`, `u64ArrayListAppendInner`, `f64ArrayListAppendInner`,
`fnProtoArrayListAppendInner` (in-memory growth); `valuePoolInit`/`valuePoolOpen`/`valuePoolAppend`/
`valuePoolGetValue`/`valuePoolClose`/`valuePoolCacheSlot`/`valuePoolResident` (pool storage);
`astStoreNodeAppend`/`astBlockSpillHead`/`astBlockAdvanceHead`/`astBlockFaultIn`/`astSlotAcquire`/
`astSlotEnsureNodeCap`/`astSlotEnsurePayloadCap` (block storage).


## Tooling

Four auxiliary modules support AST/token inspection and `@format`-style validation. They are
standalone harnesses/libraries, not part of zig1's CLI (see Debugging).

| File | Public surface | Purpose |
|------|----------------|---------|
| `print_decomposition.zig` | `PrintDecompEntry{ fmt_node_idx(u32), spec_count(u8) }`, `printDecompParseAndValidate(store, interner, diag, node_idx) ?PrintDecompEntry` | Recognizes a `fn_call` with exactly 2 args whose first arg is a `string_literal` format string and second is a `tuple_literal`; counts `{}` format specifiers (private `printDecompScanFormat`, ignoring `{{`/`}}`), and emits `"format string argument count mismatch"` (diagnostic level 1, code 0) when the spec count differs from the tuple field count. |
| `dump_ast.zig` | `dumpAst(store, root, interner)` | Pre-order AST printer: emits indented `(kind ...)` lines and prints names/values for literals, identifiers, and flagged nodes. Private `astKindToString` maps every `AstKind`; `nodeGetNameId` reads the name id for the name-carrying kinds. |
| `dump_tokens.zig` | `dumpTokens(lex, interner)` | Prints one token per line: `kind span_start span_len [value]` (integer/char as u64, float via `formatF64`, string/identifier/builtin as a quoted interned string). Private `tokenKindToString` lists the literal/builtin/keyword/eof/err kinds (`kw_anytype`, `kw_volatile`, and `c_include_builtin` are not listed). |
| `ast_dump_main.zig` | `main(argc, argv)` | Standalone entry point: reads a file, lexes once to count tokens, lexes again into an exact `Token` array, parses with `parserParseModuleRoot`, and calls `dumpAst`. Uses a fixed 2 MiB sand buffer. |

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
    │  streamed on demand (no intermediate token
    │  array on the module parse path)
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
│  Disk-backed node blocks + parallel payload blocks; │
│  value pools for extra_children / extra_ranges /    │
│  identifiers / int_values; in-memory float / string │
│  / fn_protos arrays.                                │
│  nodeHasExtraChildren, nodeChildIsNode, visitPreOrder│
└─────────────────────────────────────────────────────┘
    │
    ▼
AST tree (root node index = module_root node)
```

> **Streaming module parse** — `moduleRegistryResolveImports` (`import_resolver.zig`) reads each
> module's source into the resolver's own pool-backed `src_arena` (reset per module) and calls
> `moduleRegistryParseModule`, which builds the parser with `parserInitStreaming` over a single
> streaming `Lexer` (`lexerInit`), rather than lexing twice into an exact-size token array. The
> parser keeps a small 3-token lookahead window (`Parser.la`) and pulls tokens from the lexer on
> demand; the module source is registered with the `SourceManager` by reference via
> `sourceManagerAddFileTransient` (no scratch→perm copy). The `Lexer.count_only` guard remains but
> no current caller sets it `true` (see Known Issues). The former import-closure AST-store
> pre-sizing (`moduleScanDiscover` + `astStoreEnsure*Capacity`) is gone: node and value storage is
> now disk-backed and grows block-by-block (see `ast.zig`).

> **Growable member/field buffers + parser arena** — the parser member-list collectors that were
> fixed `[64]u32` stack buffers (`parserParseStructType`, `parserParseEnumType`,
> `parserParseUnionType`, `parserParseContainerDecl` field/member lists) plus the same-class
> `parserParseFnType` `param_buf` and `parserParseErrorSetDeclBody` `member_buf` are arena-backed
> growable arrays. Helper `parserPushU32` appends through the shared `u32ArrayListAppendInner`
> (dynamic ×2 growth) into the parser's sand arena (`Parser.allocator`), with copy on realloc.
> `parserParseBlock` keeps its stack `local_buf[64]` + `child_buf` spill (already overflow-safe).
> The per-module parser arena is a pool-backed `GrowableSand` (`parser_arena` in
> `import_resolver.zig`), reset per module; it is no longer a fixed `p_arena_buf` stack buffer.


---

## Debugging

### CLI Flags (referenced in pipeline)

| Flag | Effect |
|------|--------|
| `--dump-types` | Dumps type info after type resolution (DEAD — declared in `main.zig` `parseArgs`, never matched) |
| `--dump-lir` | Dumps LIR after lowering (DEAD — declared in `main.zig` `parseArgs`, never matched) |
| `--dump-c89` | Dumps generated C89 |

> The main pipeline (`main.zig` `parseArgs`) does **not** implement `--dump-tokens` or `--dump-ast`.
> Token/AST dumping lives in the separate harness binaries (`dump_tokens.zig`, `ast_dump_main.zig`),
> not in zig1's CLI.

### Lexer Debug Markers

| Marker | File | Trigger |
|--------|------|---------|
| `LEX` | `lexer.zig` | When identifier text is exactly `"neighbors"` (written via `pal.stderr_write`) |

> The `LEX:n<node>k<kind>` markers seen in `--markers` traces are emitted by `lower.zig`
> (`lowerExpr` entry), NOT the lexer. The lexer's own marker is a bare `LEX` (no `:n…k…` suffix)
> and fires only for the identifier `"neighbors"`.

### Parser Debug Markers

See table in parser section above. All go to stderr via `pal.markerWrite`.

### AstStore Debug

| Marker | File | Trigger |
|--------|------|---------|
| `AS:<val>\n` | `ast.zig` | Float literal stored (only when `pal.isMarkersEnabled()`) |

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
| `2000` | Parse errors (via `parserAddError`) |
| `3045` | Unknown calling convention in `extern` (via `parserAddErrorCode`) |

---

## Known Issues / Bugs

1. **Token packed layout** (`token.zig`): the desired 16-byte packed `Token` is rejected by zig0 because `TokenValue` is a union; actual size is 24 bytes. Restore the packed layout once zig1 self-hosts.

2. **AstKind discriminant gap** (`ast.zig`): `mod_assign = 74` was moved off the value it originally collided with (`swt_ex = 56`); `swt_ex` stays at 56. All 112 discriminants (0..111) are now unique.

3. **Parser re-interns identifiers** (`parser.zig`): `parserParseIdentExpr` re-interns identifier text rather than reusing `TokenValue.string_id` directly. Redundant but keeps interned IDs consistent.

4. **No IEEE float edge cases**: `parseF64` uses naive multiplication/division loops for scientific notation — potential precision issues on extreme exponents. (The separate exponent-after-decimal-point drop — the fraction loop consumed the `e` — was fixed 2026-09-18 and pinned by `lexer_float_exponent_xmod`.)

5. **`Lexer.count_only` is a dead field**: `count_only` remains and guards every diagnostic, intern, and `string_buf` write, but no current caller ever sets it `true` — the two-pass count-only lexer pass was removed when module parsing moved to the streaming parser (see the streaming note under Data Flow).

