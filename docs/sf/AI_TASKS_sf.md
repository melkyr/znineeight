# AI Agent Tasks for Z98 Self-Hosted Compiler (`zig1`)

This document outlines a granular, step-by-step roadmap for an AI agent to implement the **self-hosted Z98 compiler** (`zig1`), written in Z98 and compiled by `zig0`. Tasks are organized by milestone, focusing on **Initial Infrastructure**, **Lexer**, and **Parser/AST** phases only.

---

## Phase 0: The Self-Hosted Compiler (Z98)

### Milestone 0: Core Infrastructure for `zig1`

#### Allocator & Memory Foundation
1.  **Task 1:** Set up directory structure for `zig1` source (`lib/`, `src/`, `tests/`, `docs/`).
2.  **Task 2:** Implement `ArenaAllocator` wrapper with `permanent`, `module`, and `scratch` arena hierarchy.
3.  **Task 3:** Add `TrackingAllocator` wrapper to enforce `--max-mem=16M` limit with peak tracking.
4.  **Task 4:** Create `initCompilerAlloc()` function to initialize three-arena hierarchy (Z98 constraint: no global aggregate constants).
5.  **Task 5:** Implement `Allocator` interface with `alloc`, `free`, `resize` methods compatible with Z98.

#### String Interning & Source Management
6.  **Task 6:** Implement `StringInterner` with FNV-1a hash, open addressing, and arena-backed storage.
7.  **Task 7:** Add `intern()` and `get()` methods to `StringInterner` with collision chaining.
8.  **Task 8:** Implement `SourceManager` with `SourceFile` struct tracking filename, content, and line offsets.
9.  **Task 9:** Add `getLocation(file_id, offset)` binary search for offset→line/col conversion.
10. **Task 10:** Create `SourceManager.addFile()` to register new source files with precomputed line offsets.

#### Diagnostics & Error Handling
11. **Task 11:** Define `Diagnostic` struct with `level`, `file_id`, `span_start`, `span_end`, `message`.
12. **Task 12:** Implement `DiagnosticCollector` with `ArrayList(Diagnostic)` and `hasErrors()` method.
13. **Task 13:** Add `addDiagnostic()` method that records errors without `abort()` (unified error model).
14. **Task 14:** Implement basic diagnostic printing: source line extraction with caret pointer.
15. **Task 15:** Create minimal `assert_*` test primitives (`assert_true`, `assert_eq_u32`, `assert_eq_str`) for Z98.

#### Token & Lexer Foundation
16. **Task 16:** Define `Token` struct (16 bytes): `kind: u16`, `span_start: u32`, `span_len: u16`, `value: TokenValue`.
17. **Task 17:** Define `TokenValue` union: `int_val: u64`, `float_val: f64`, `string_id: u32`, `none: void`.
18. **Task 18:** Create `TokenKind` enum with all 88+ token kinds (literals, operators, keywords, builtins).
19. **Task 19:** Implement keyword table lookup: linear scan of ~35 entries to map identifier → keyword token.
20. **Task 20:** Write initial `main.zig` entry point with CLI parsing skeleton (`--dump-tokens`, `--dump-ast`, `--max-mem`).

#### Test Harness Infrastructure
21. **Task 21:** Create `test_runner.zig` with batch execution pattern and result aggregation (`passed/failed/skipped`).
22. **Task 22:** Implement `parseTestSource()` helper: lex + parse a string into AST for unit testing.
23. **Task 23:** Add `--test-mode` flag for deterministic name mangling (counter-based, not hash-based).
24. **Task 24:** Create initial `build.bat`/`build.sh` scripts for compiling `zig1` with `zig0`.
25. **Task 25:** Write first unit test: `test_lexer_integer_decimal` verifying `42` → `.integer_literal, value=42`.

---

### Milestone 1: Lexer Implementation

#### TokenKind Enum & Basic Scanning
26. **Task 26:** Complete `TokenKind` enum with all literal kinds: `integer_literal`, `float_literal`, `string_literal`, `char_literal`.
27. **Task 27:** Add operator token kinds: arithmetic (`+`, `-`, `*`, `/`, `%`), bitwise (`&`, `|`, `^`, `~`, `<<`, `>>`), comparison (`==`, `!=`, `<`, `<=`, `>`, `>=`).
28. **Task 28:** Add assignment operator kinds: `plus_eq`, `minus_eq`, `star_eq`, `slash_eq`, `percent_eq`, `ampersand_eq`, etc.
29. **Task 29:** Add delimiter kinds: `lparen`, `rparen`, `lbracket`, `rbracket`, `lbrace`, `rbrace`, `semicolon`, `colon`, `comma`, `dot`.
30. **Task 30:** Add special token kinds: `at_sign`, `underscore`, `question_mark`, `bang`, `fat_arrow`, `dot_dot`, `dot_dot_dot`, `dot_lbrace`, `dot_star`.

#### Keyword Recognition
31. **Task 31:** Add declaration keywords: `kw_const`, `kw_var`, `kw_fn`, `kw_pub`, `kw_extern`, `kw_export`, `kw_test`.
32. **Task 32:** Add type keywords: `kw_struct`, `kw_enum`, `kw_union`, `kw_void`, `kw_bool`, `kw_noreturn`, `kw_c_char`.
33. **Task 33:** Add control flow keywords: `kw_if`, `kw_else`, `kw_while`, `kw_for`, `kw_switch`, `kw_return`, `kw_break`, `kw_continue`.
34. **Task 34:** Add defer/error keywords: `kw_defer`, `kw_errdefer`, `kw_try`, `kw_catch`, `kw_orelse`, `kw_error`.
35. **Task 35:** Add boolean/logical keywords: `kw_and`, `kw_or`, `kw_true`, `kw_false`, `kw_null`, `kw_undefined`, `kw_unreachable`.

#### Lexer Core Implementation
36. **Task 36:** Implement `Lexer` struct with `source: []const u8`, `pos: usize`, `line: u32`, `col: u32`.
37. **Task 37:** Implement `advance()`, `peek()`, `isAtEnd()`, `match(char)` helper methods with bounds checking.
38. **Task 38:** Implement `skipWhitespaceAndComments()`: skip spaces, tabs, newlines, `//` and `/* */` comments.
39. **Task 39:** Implement single-character token dispatch: `(`, `)`, `[`, `]`, `{`, `}`, `;`, `:`, `,`, `.`, `@`, `?`, `!`, `~`.
40. **Task 40:** Implement dot variant handling: `.`, `..`, `...`, `.{`, `.*` with lookahead.

#### Operator Lexing
41. **Task 41:** Implement arithmetic operator lexing: `+`, `-`, `*`, `/`, `%` with `= ` variants (`+=`, `-=`, etc.).
42. **Task 42:** Implement bitwise operator lexing: `&`, `|`, `^`, `~` with `= ` variants.
43. **Task 43:** Implement shift operator lexing: `<<`, `>>` with `= ` variants (`<<=`, `>>=`).
44. **Task 44:** Implement comparison operator lexing: `==`, `!=`, `<`, `<=`, `>`, `>=`.
45. **Task 45:** Implement assignment operator lexing: `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`.

#### Literal Lexing
46. **Task 46:** Implement `scanInteger()`: decimal, hex (`0x`), binary (`0b`), octal (`0o`) with underscore separators.
47. **Task 47:** Implement `scanFloat()`: decimal point, scientific notation (`e-5`), with proper value parsing.
48. **Task 48:** Implement `scanString()`: handle escape sequences (`\n`, `\t`, `\\`, `\"`), store via `StringInterner`.
49. **Task 49:** Implement `scanChar()`: single character with escape support, store codepoint as `u64`.
50. **Task 50:** Implement identifier scanning: `[a-zA-Z_][a-zA-Z0-9_]*`, with keyword table lookup.

#### Builtin & Error Handling
51. **Task 51:** Implement `scanBuiltinIdentifier()`: `@` followed by identifier → `.builtin_identifier`.
52. **Task 52:** Implement error token: unrecognized character → `.err_token` with span tracking.
53. **Task 53:** Implement `makeToken(kind)`, `makeErrorToken()` helpers with span calculation.
54. **Task 54:** Add lexer unit tests: `test_lexer_hex`, `test_lexer_binary`, `test_lexer_string_escape`, `test_lexer_comment_nested`.
55. **Task 55:** Add lexer unit tests: `test_lexer_operator_chain`, `test_lexer_dot_variants`, `test_lexer_builtin`, `test_lexer_error_recovery`.

#### Lexer Integration & Verification
56. **Task 56:** Implement `Lexer.nextToken()` main loop integrating all scanning logic.
57. **Task 57:** Add `--dump-tokens` flag support: output one token per line with kind, span, value.
58. **Task 58:** Write differential test: compare `zig0 --dump-tokens` vs `zig1 --dump-tokens` for reference programs.
59. **Task 59:** Verify lexer handles `eval.zig` tokens correctly (deeply nested switches, builtins, casts).
60. **Task 60:** Final lexer validation: all 88+ `TokenKind` values covered, no unreachable code, memory under budget.

---

### Milestone 2: Parser & AST Implementation

#### AST Core Structures
61. **Task 61:** Define `AstKind` enum with all 88 node kinds (error, declarations, literals, expressions, control flow, types).
62. **Task 62:** Define `AstNode` packed struct (24 bytes): `kind: u8`, `flags: u8`, `span_start: u32`, `span_end: u32`, `child_0/1/2: u32`, `payload: u32`.
63. **Task 63:** Document `flags` byte encoding: bit0=is_const, bit1=is_pub, bit2=is_extern, bit4=has_capture, etc.
64. **Task 64:** Define payload field semantics per `AstKind`: index into `int_values`, `identifiers`, `extra_children`, etc.
65. **Task 65:** Implement `AstStore` struct with `ArrayList(AstNode)` and parallel payload arrays.

#### AstStore Payload Management
66. **Task 66:** Implement `addNode()` helper: create `AstNode`, append to `nodes`, return index.
67. **Task 67:** Implement `addExtraChildren()`: pack `(start << 16) | count` into `u32`, append to flat `extra_children` array.
68. **Task 68:** Implement `getExtraChildren()`: unpack payload, return `[]const u32` slice into `extra_children`.
69. **Task 69:** Implement literal helpers: `addIntLiteral()`, `addFloatLiteral()`, `addIdentifier()` with interning.
70. **Task 70:** Define `FnProto` struct: `name_id: u32`, `params_start/count: u16`, `return_type_node: u32`.

#### Parser Foundation
71. **Task 71:** Define `Parser` struct: `tokens: []const Token`, `pos: usize`, `store: *AstStore`, `interner: *StringInterner`, `diag: *DiagnosticCollector`.
72. **Task 72:** Implement token access helpers: `peek()`, `peekN(n)`, `advance()`, `expect(kind)`, `tokenText(tok)`.
73. **Task 73:** Implement error handling: `addError(tok, msg)`, `synchronize()` to recovery points (`;`, `}`, `fn`, `const`, etc.).
74. **Task 74:** Define `Prec` enum with 14 precedence levels: `none`, `assignment`, `orelse`, `catch`, `bool_or`, `bool_and`, `comparison`, `bit_or`, `bit_xor`, `bit_and`, `shift`, `additive`, `multiply`, `prefix`, `postfix`.
75. **Task 75:** Implement `getInfixInfo(TokenKind)`: return `OpInfo{prec, right_assoc}` or `null` for non-infix tokens.

#### Precedence Climbing Expression Parser
76. **Task 76:** Implement `parseExprPrec(min_prec: Prec)`: iterative binary loop with bounded recursion for atoms.
77. **Task 77:** Implement `parsePrimary()`: dispatch on token kind to literals, identifiers, builtins, prefix ops, grouping, aggregates, control-flow expressions.
78. **Task 78:** Implement `parsePostfixChain(base)`: handle `.field`, `.*`, `[index]`, `[start..end]`, `(args)` in loop.
79. **Task 79:** Implement special RHS parsing: `parseCatchRHS()` and `parseOrelseRHS()` for capture and block handling.
80. **Task 80:** Add expression unit tests: `test_binary_precedence`, `test_right_assoc_orelse`, `test_postfix_chain`, `test_try_expr`.

#### Statement & Declaration Parsing
81. **Task 81:** Implement `parseStatement()`: dispatch on token to var/fn/pub/test decls, if/while/for/switch stmts, return/break/continue/defer.
82. **Task 82:** Implement `parseVarDecl()`: handle `const`/`var`, optional type annotation, optional initializer, flags for is_pub/is_const.
83. **Task 83:** Implement `parseFnDecl()`: parse signature (params, return type), body block or extern stub, flags for is_pub/is_extern.
84. **Task 84:** Implement `parseBlock()`: `{ stmt* }` with child list via `extra_children`.
85. **Task 85:** Implement `parseIfStmt()` and `parseIfExpr()`: condition, then-body/expr, optional else, optional capture `|val|`.

#### Control Flow & Switch Parsing
86. **Task 86:** Implement `parseWhileStmt()`: condition, body, optional continue expr, optional capture, optional label.
87. **Task 87:** Implement `parseForStmt()`: iterable (slice or range), body, item capture, optional index capture.
88. **Task 88:** Implement `parseSwitchExpr()`: condition, prong list via `extra_children`, mandatory `else` or exhaustiveness.
89. **Task 89:** Implement `parseSwitchProng()`: case items (literals, ranges), optional `|capture|`, `=>`, body expr/block.
90. **Task 90:** Add control flow tests: `test_if_capture`, `test_while_continue`, `test_for_range`, `test_switch_prong_capture`.

#### Type Expression Parsing
91. **Task 91:** Implement `parseType()`: handle primitives (`i32`, `void`, etc.), `*T`, `[*]T`, `[]T`, `[N]T`, `?T`, `!T`, `fn(...)R`.
92. **Task 92:** Implement pointer type parsing: `*`, `*const`, `[*]`, `[*]const`, `[]`, `[]const` with const flag in node.
93. **Task 93:** Implement aggregate type parsing: `struct { fields }`, `enum { members }`, `union { variants }`, `union(enum)`.
94. **Task 94:** Implement error set parsing: `error { Tag1, Tag2 }` with member names in `extra_children`.
95. **Task 95:** Add type parsing tests: `test_type_ptr_const`, `test_type_slice`, `test_type_optional`, `test_type_error_union`.

#### Module & Import Parsing
96. **Task 96:** Implement `parseImportExpr()`: `@import("path.zig")` → `.import_expr` with path string ID.
97. **Task 97:** Implement `parseModuleRoot()`: top-level decl list via `extra_children`, entry point for parsing.
98. **Task 98:** Add import tests: `test_import_basic`, `test_qualified_access` (parser only, resolution deferred).
99. **Task 99:** Implement error recovery in parser: emit `.err` node, skip to sync point, continue parsing.
100. **Task 100:** Write parser integration tests: parse `mandelbrot.zig`, `game_of_life.zig`, verify AST structure via `--dump-ast`.

#### AST Traversal & Verification
101. **Task 101:** Implement `visitPreOrder(alloc, store, root, callback)`: iterative DFS with explicit `ArrayList(u32)` stack.
102. **Task 102:** Implement `nodeHasExtraChildren(kind)`: switch to identify kinds using variable-length child lists.
103. **Task 103:** Add AST traversal tests: verify all nodes visited, child order preserved, extra children handled.
104. **Task 104:** Implement `--dump-ast` flag: canonical S-expression output for differential testing.
105. **Task 105:** Run AST comparison: `zig0 --dump-ast` vs `zig1 --dump-ast` for all reference programs.

#### Parser Hardening & Memory Validation
106. **Task 106:** Add recursion depth guard to `parseExprPrec`: max ~12 levels (precedence levels), panic if exceeded.
107. **Task 107:** Verify AST memory budget: ~221 KB per 2000-line module, ~1.5 MB total for compiler source.
108. **Task 108:** Add parser unit tests for error recovery: missing semicolon, unexpected token, multiple errors.
109. **Task 109:** Verify parser handles Z98 critical patterns: 7-level switch nesting, TCO `while(true)+continue`, pervasive `@intCast`.
110. **Task 110:** Final parser validation: all `AstKind` values covered, no pointer captures, immutable AST after parsing.

---

## 🎯 Key Implementation Constraints for `zig1`

| Constraint | Workaround | Notes |
|------------|------------|-------|
| No generics | Concrete hash maps (`U32ToU32Map`, `U64ToU32Map`) | Hand-specialized for each use case |
| No `@enumToInt` | Manual `toInt()`/`fromInt()` helpers | Switch-based or direct cast |
| Global aggregate constants | `pub var` + `initCompilerAlloc()` | Z98 bootstrap limitation |
| No pointer captures | Unwrap optional before use | `if (opt != null) { var p = &opt.value; }` |
| Strict `i32` ↔ `usize` | `@intCast` everywhere | Very common in compiler code |
| Switch requires `else` | Always add `else => unreachable` | Z98 subset rule |
| No method syntax | Free functions: `foo(self, ...)` | Standard Zig style |

---

## 🧪 Testing Strategy for Milestones 0-2

```bash
# Layer 1: Unit tests (fast)
./test_lexer          # 30+ lexer tests
./test_parser_expr    # 25+ expression tests  
./test_parser_stmt    # 20+ statement tests
./test_parser_types   # 15+ type expression tests

# Layer 2: AST comparison (differential)
for f in tests/reference/*.zig; do
    ./zig0 --dump-ast "$f" > /tmp/z0.txt
    ./zig1 --dump-ast "$f" > /tmp/z1.txt
    diff /tmp/z0.txt /tmp/z1.txt || echo "FAIL: $f"
done

# Layer 3: Memory gate
./zig1 --max-mem=16M --print-peak-mem lib/main.zig -o /tmp/out/
# Verify peak < 16MB
```

---

## 📋 Success Criteria for Milestones 0-2

✅ **Milestone 0**: Three-arena allocator, string interner, source manager, diagnostics, test harness all functional under 16MB.

✅ **Milestone 1**: Lexer produces correct `Token` stream for all Z98 syntax; `--dump-tokens` matches `zig0` output for reference programs.

✅ **Milestone 2**: Parser builds immutable, flat AST; `--dump-ast` canonical output matches `zig0` for all reference programs; memory usage within budget.

✅ **Integration**: `zig1` can parse its own source code (`lib/main.zig` + dependencies) without errors or memory violations.

---

> **Next Phase Preview**: Milestone 3 will cover Type System (TypeRegistry, Kahn's algorithm, concrete hash maps) and Semantic Analysis (symbol tables, comptime eval, coercion tables).
