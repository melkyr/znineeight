---

# AI Agent Tasks for Z98 Self-Hosted Compiler (`zig1`) – Extended Milestones 3–9

This document extends the existing task list for `zig1` implementation, covering the complete compiler pipeline from import resolution through C89 emission and static analysis.

---

## Phase 0: The Self-Hosted Compiler (Z98) – Continued
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

### Milestone 3: Import Resolution & Symbol Registration

#### Module Registry Foundation
111. **Task 111:** Define `ModuleState` enum: `pending`, `parsing`, `parsed`, `resolved`, `failed`.
112. **Task 112:** Define `ModuleEntry` struct: `id`, `path_id`, `state`, `ast_root`, `import_count`, `imports_start`, `symbol_table`, `type_offset`.
113. **Task 113:** Implement `ModuleRegistry` struct with `ArrayList(ModuleEntry)`, `import_edges: ArrayList(u32)`, `path_to_id: U32ToU32Map`.
114. **Task 114:** Implement `ModuleResolver` with search order: importing dir → `-I` flags → default `lib/`.
115. **Task 115:** Add `resolveImport(path_id, importer_id)` to locate file, intern absolute path, return `module_id`.

#### On-Demand Parsing & Import Queue
116. **Task 116:** Implement `ImportQueue` struct: `pending: ArrayList(u32)` with duplicate detection.
117. **Task 117:** Modify parser `parseImportExpr()` to queue discovered imports via `enqueue(module_id)`.
118. **Task 118:** Implement `resolveImports()` loop: pop module, parse if pending, queue newly discovered imports.
119. **Task 119:** Add per-module arena management: `module_arena` allocated at parse time, token arena reset after AST built.
120. **Task 120:** Implement import cycle detection: record import edges during parsing.

#### Topological Module Sorting (Kahn's Algorithm)
121. **Task 121:** Implement `sortModules()`: compute in-degrees from `import_edges`.
122. **Task 122:** Seed worklist with modules having `in_degree == 0`; sort worklist for determinism.
123. **Task 123:** Process worklist: mark module `.resolved`, decrement in-degree of importers, enqueue when zero.
124. **Task 124:** Detect cycles: any module with `in_degree > 0` after processing → mark `.failed`, emit `ERR_CIRCULAR_IMPORT`.
125. **Task 125:** Verify topological order: imported modules appear before importers.

#### Symbol Table Structures
126. **Task 126:** Define `SymbolKind` enum: `global`, `function`, `type_alias`, `module`, `test`.
127. **Task 127:** Define `Symbol` struct: `name_id`, `type_id` (0 initially), `kind`, `flags` (pub/extern/export/const), `decl_node`, `module_id`, `scope_depth`.
128. **Task 128:** Implement per-module `SymbolTable` with global scope only (Pass 3 uses scope 0).
129. **Task 129:** Implement `SymbolTable.insert(sym)` with duplicate detection (linear scan, small N).
130. **Task 130:** Create `SymbolRegistry` holding `[]SymbolTable` indexed by `ModuleId`.

#### Top-Level Symbol Registration
131. **Task 131:** Implement `registerModuleSymbols(module_id)`: iterate `module_root` extra children, dispatch on `AstKind`.
132. **Task 132:** Implement `registerVarDecl()`: create `Symbol` with `.global` kind, `flags` from node.
133. **Task 133:** Implement `registerFnDecl()`: create `Symbol` with `.function` kind, extract `name_id` from `FnProto`.
134. **Task 134:** Implement `registerTestDecl()`: create `Symbol` with `.test` kind, store body reference.
135. **Task 135:** Implement `registerTypeDecl()`: call `TypeRegistry.registerNamedType()` to create `unresolved_name` stub, then register `.type_alias` symbol.

#### Type Stub Creation & Dependency Graph
136. **Task 136:** Implement `TypeRegistry.registerNamedType(module_id, name_id, kind)`: create `Type` with `state=0` (unresolved), assign `TypeId`, insert into `name_cache`.
137. **Task 137:** Implement `addTypeDependencies(tid, node)`: walk struct/union fields, add edges to `DepGraph` for value-type fields.
138. **Task 138:** Define `isValueDependency(kind)`: true for struct/union/enum/array/optional/error_union, false for pointer/slice/fn.
139. **Task 139:** Build `DepGraph` with `edges: ArrayList(DepEntry)` and `in_degree: []u32` indexed by `TypeId`.
140. **Task 140:** Add registration unit tests: duplicate symbol detection, type stub creation, dependency edges.

#### Cross-Module Visibility & Import Tests
141. **Task 141:** Implement visibility flag checks: `pub` → visible to importers; default → private.
142. **Task 142:** Add qualified lookup preparation: store `module_id` in `Symbol` for cross-module resolution.
143. **Task 143:** Write integration tests: multi-module import chains, circular import detection, visibility enforcement.
144. **Task 144:** Verify deterministic `ModuleId` assignment and symbol registration order.
145. **Task 145:** Run memory gate: 50-module project, peak `permanent` + `module` arenas < 16 MB.

---

### Milestone 4: Type System & Type Resolution

#### TypeRegistry Foundation
146. **Task 146:** Define `TypeKind` enum with 39 kinds: primitives, compound types, `unresolved_name`, `type_type`, `module_type`, `null_type`, etc.
147. **Task 147:** Define `Type` struct: `kind`, `state` (0=unresolved,1=resolving,2=resolved), `flags`, `size`, `alignment`, `name_id`, `c_name_id`, `module_id`, `payload_idx`.
148. **Task 148:** Implement `TypeRegistry` with `ArrayList(Type)` and kind-specific payload arrays (`ptr_payloads`, `array_payloads`, etc.).
149. **Task 149:** Implement well-known primitive `TypeId`s: `TYPE_VOID=1`, `TYPE_BOOL=2`, …, `TYPE_INT_LIT=19`, `FIRST_USER_TYPE=20`.
150. **Task 150:** Register all primitives during `TypeRegistry.init()` with correct sizes/alignments.

#### Concrete Hash Maps (No Generics)
151. **Task 151:** Implement `U32ToU32Map`: open addressing with linear probing, `keys`, `values`, `occupied` arrays, `get()`/`put()` methods.
152. **Task 152:** Implement `U64ToU32Map`: same structure with `u64` keys.
153. **Task 153:** Add `ptr_cache: U64ToU32Map` keyed by `(base_tid << 1) | is_const`.
154. **Task 154:** Add `slice_cache: U64ToU32Map` keyed by `(elem_tid << 1) | is_const`.
155. **Task 155:** Add `optional_cache: U32ToU32Map`, `array_cache: U64ToU32Map`, `name_cache: U64ToU32Map`.

#### Type Creation (Deduplicated)
156. **Task 156:** Implement `getOrCreatePtr(base, is_const)`: check cache, create `PtrPayload`, append `Type` with `size=4, align=4`.
157. **Task 157:** Implement `getOrCreateSlice(elem, is_const)`: check cache, create `SlicePayload`, append `Type` with `size=8, align=4`.
158. **Task 158:** Implement `getOrCreateOptional(payload)`: defer size/align if payload unresolved, compute layout when resolved.
159. **Task 159:** Implement `getOrCreateArray(elem, length)`, `getOrCreateErrorUnion(payload, error_set)`.
160. **Task 160:** Add helper methods: `isNumeric()`, `isInteger()`, `isPointer()`, `getPointeeType()`.

#### Dependency Graph & Kahn's Type Resolution
161. **Task 161:** Finalize `DepGraph` after symbol registration: allocate `in_degree` array sized to `types.items.len`.
162. **Task 162:** Seed worklist with types having `in_degree == 0` and `state == 0` (unresolved).
163. **Task 163:** Implement `resolveTypeLayout(tid)`: compute size/alignment for struct/union/tagged_union/array/optional/error_union/tuple.
164. **Task 164:** Implement struct layout: iterate fields, align offsets, compute max alignment, final size.
165. **Task 165:** Implement tagged union layout: tag first, padding, union payload, overall alignment.

#### Cycle Detection & Error Handling
166. **Task 166:** After Kahn's algorithm, scan for types with `state != 2` and `in_degree > 0` → circular dependency.
167. **Task 167:** Emit `ERR_CIRCULAR_TYPE_DEPENDENCY`, mark cyclic types as `TYPE_VOID`.
168. **Task 168:** Implement `resolveTypeFromAst(node_idx)`: walk type expression AST, call appropriate `getOrCreate*`.
169. **Task 169:** Add unit tests: pointer/slice deduplication, struct layout, array stride, optional size.
170. **Task 170:** Add integration tests: forward reference resolution, cross-module type resolution, cycle detection.

---

### Milestone 5: Semantic Analysis & Comptime Evaluation

#### Resolved Type Table & Symbol Resolution
171. **Task 171:** Implement `ResolvedTypeTable`: side-table mapping `node_idx → TypeId` via `U32ToU32Map`.
172. **Task 172:** Implement `SemanticAnalyzer` struct with `expected_type_stack: ArrayList(TypeId)`.
173. **Task 173:** Implement `resolveExpr(node_idx)`: dispatch on `AstKind`, store result in `ResolvedTypeTable`.
174. **Task 174:** Implement identifier resolution: lookup in `SymbolTable`, return symbol's `type_id`.
175. **Task 175:** Implement field access resolution: for structs/unions, lookup field; for modules, cross-module symbol lookup.

#### Expression Type Checking
176. **Task 176:** Implement arithmetic operator type rules: numeric same-type, literal promotion, pointer arithmetic.
177. **Task 177:** Implement comparison operator rules: same-type numeric, optional null check, error set comparison.
178. **Task 178:** Implement `resolveFnCall()`: check argument count, push expected types, check assignability, record coercions.
179. **Task 179:** Implement `resolveTryExpr()`: verify operand is error union, propagate error context.
180. **Task 180:** Implement `resolveIfExpr()` and `resolveSwitchExpr()`: unify branch types, check exhaustiveness.

#### Coercion Table & Assignability
181. **Task 181:** Implement `isAssignable(source, target)`: check direct equality, integer literal fit, optional/error wrapping, pointer/slice const-qualifying.
182. **Task 182:** Implement `CoercionKind` enum: `none`, `wrap_optional`, `array_to_slice`, `int_widen`, etc.
183. **Task 183:** Implement `CoercionTable`: side-table mapping `node_idx → CoercionEntry` via `U32ToU32Map`.
184. **Task 184:** Add `classifyCoercion(source, target)`: determine `CoercionKind` based on type relationship.
185. **Task 185:** Integrate coercion recording: after resolving expression, if coercion needed, add to table.

#### Comptime Evaluation
186. **Task 186:** Implement `ComptimeEval` struct with `evaluate(node_idx) -> ?u64`.
187. **Task 187:** Implement constant folding for `@sizeOf` and `@alignOf`: resolve type argument, return size/alignment.
188. **Task 188:** Implement constant folding for integer arithmetic: `add`, `sub`, `mul`, `div`, `mod_op` on constants.
189. **Task 189:** Implement `@intCast` folding when both type and value are comptime-known.
190. **Task 190:** Implement `canLiteralFitInType(value, target)`: range check for integer literal coercion.

#### Constraint Checking & Diagnostics
191. **Task 191:** Verify switch exhaustiveness: for enum switches, ensure all variants covered or `else` present.
192. **Task 192:** Check `return` type compatibility: returned expression assignable to function return type.
193. **Task 193:** Check `break`/`continue` validity: inside loop, not across defer boundaries.
194. **Task 194:** Implement `std.debug.print` decomposition: parse format string, validate argument count, record decomposition.
195. **Task 195:** Add semantic analysis unit tests: type mismatch, undefined symbol, coercion, switch exhaustiveness.

---

### Milestone 6: Static Analyzers (Passes 6–9)

*Note: These passes run **after** semantic analysis and **before** LIR lowering. They operate per-function using the `scratch` arena.*

#### Shared Infrastructure for Flow-Sensitive Analysis
196. **Task 196:** Implement `StateMap` with delta-linked parent pointers: `entries: ArrayList(StateEntry)`, `parent: ?*StateMap`.
197. **Task 197:** Implement `StateMap.fork()`: O(1) child creation with parent pointer.
198. **Task 198:** Implement `StateMap.get(name_id)`: walk parent chain to find state.
199. **Task 199:** Implement `StateMap.set(name_id, state)`: local override only.
200. **Task 200:** Implement `mergeStates(parent, branch_a, branch_b, unknown_state)`: conservative join of divergent states.

#### Iterative Function Visitor
201. **Task 201:** Implement `walkBlock(ctx, state, block_idx, handler)`: iterative traversal of statements in control-flow order.
202. **Task 202:** Implement `visitStatement` dispatch for each analyzer (function pointer or switch).
203. **Task 203:** Add branch handling: for `if`, `while`, `switch`, fork state, walk branches, merge.
204. **Task 204:** Implement loop analysis: track modified variables, mark as `unknown` after loop exit.
205. **Task 205:** Add `defer_stack` tracking for scope exit processing.

#### SignatureAnalyzer (Pass 6)
206. **Task 206:** Implement `analyzeSignature(fn_node)`: check parameter/return types for C89 compatibility.
207. **Task 207:** Reject `void` parameter types → `ERR_VOID_PARAMETER`.
208. **Task 208:** Reject incomplete struct/union in signature → `ERR_INCOMPLETE_TYPE`.
209. **Task 209:** Reject `anytype` and opaque types → `ERR_ANYTYPE_NOT_SUPPORTED`.
210. **Task 210:** Warn on return types > 64 bytes → `WARN_LARGE_RETURN`.

#### NullPointerAnalyzer (Pass 7)
211. **Task 211:** Define `PtrState` enum: `uninit`, `is_null`, `safe`, `maybe`.
212. **Task 212:** Implement state transitions for assignments, null checks, captures, function calls.
213. **Task 213:** Implement `classifyExpr()` for nullability: address-of → `safe`, null literal → `is_null`, function call → `maybe`.
214. **Task 214:** Implement null guard detection: recognize `if (ptr != null)`, `if (opt) |val|`, `while (opt) |val|`.
215. **Task 215:** On dereference (`.*`, `[i]`), check pointer state: `is_null` → error, `uninit`/`maybe` → warning.
216. **Task 216:** Add unit tests: null guard refinement, optional capture, branch merging.

#### LifetimeAnalyzer (Pass 8)
217. **Task 217:** Define `Provenance` enum: `unknown`, `local`, `param`, `param_addr`, `global`, `heap`.
218. **Task 218:** Implement `resolveOrigin(expr)`: walk field/index to find base local variable.
219. **Task 219:** Implement `classifyProvenance()`: address-of local → `local`, address-of param → `param_addr`, function call → `heap`.
220. **Task 220:** On `return`, check provenance: `local` or `param_addr` → error (dangling pointer).
221. **Task 221:** On slice creation (`arr[0..n]`), check base origin: local array → warning.
222. **Task 222:** Add unit tests: returning &local, returning slice of local, parameter address.

#### DoubleFreeAnalyzer (Pass 9)
223. **Task 223:** Define `AllocState` enum: `untracked`, `allocated`, `freed`, `returned_val`, `transferred`, `unknown`.
224. **Task 224:** Implement allocation detection: recognize `arena_alloc` and `try arena_alloc` calls.
225. **Task 225:** Implement free detection: recognize `arena_free` call, extract pointer argument.
226. **Task 226:** Track state per pointer: on alloc → `allocated`; on free → `freed`; double free → error.
227. **Task 227:** On scope exit, check for unfreed pointers → leak warning.
228. **Task 228:** On pointer overwrite or function pass, mark as `transferred` or `returned_val`.
229. **Task 229:** Implement composite name tracking for struct fields (e.g., `container.ptr`).
230. **Task 230:** Add unit tests: double free, leak detection, ownership transfer, defer handling.

#### Static Analyzer Integration & Pipeline
231. **Task 231:** Create `runAllAnalyzers(ctx, module_root)`: iterate functions, run each analyzer, reset scratch arena between functions.
232. **Task 232:** Add CLI flags: `--no-null-check`, `--no-lifetime-check`, `--no-leak-check`, `--warn-all`, `--warn-error`.
233. **Task 233:** Integrate analyzer diagnostics into `DiagnosticCollector` with appropriate error/warning codes.
234. **Task 234:** Write integration tests: `eval.zig` (complex control flow), `mud.zig` (arena usage), `game_of_life.zig` (tagged unions).
235. **Task 235:** Verify static analyzers do not exceed per-function scratch memory budget (512 KB).

---

### Milestone 7: LIR Lowering

#### LIR Data Structures
236. **Task 236:** Define `LirInst` union: `decl_temp`, `assign`, `binary`, `branch`, `switch_br`, `call`, `ret`, etc. (see `AST_LIR_Lowering.md` Appendix A).
237. **Task 237:** Define `BasicBlock` struct: `id: u32`, `insts: ArrayList(LirInst)`, `is_terminated: bool`.
238. **Task 238:** Define `LirFunction` struct: `name_id`, `return_type`, `params: ArrayList(LirParam)`, `blocks: ArrayList(BasicBlock)`, `hoisted_temps: ArrayList(TempDecl)`.
239. **Task 239:** Define `LirLowerer` struct with `func: *LirFunction`, `current_bb: u32`, `temp_counter: u32`, `defer_stack`, `loop_stack`.
240. **Task 240:** Implement basic block creation: `createBlock()` returns `u32` block ID.

#### Expression Lowering
241. **Task 241:** Implement `lowerExpr(node_idx) -> u32` (returns temp ID).
242. **Task 242:** Implement literal lowering: `int_const`, `float_const`, `string_const`, `bool_const`, `null_const`.
243. **Task 243:** Implement binary/unary operator lowering: emit `binary`/`unary` LIR instructions.
244. **Task 244:** Implement field/index access lowering: `load_field`, `load_index`, `load`, `addr_of`.
245. **Task 245:** Implement function call lowering: lower callee and args, emit `call` instruction.

#### Control Flow Lowering
246. **Task 246:** Implement `if` lowering: `branch` to then/else blocks, merge with phi-like temp assignment.
247. **Task 247:** Implement `while` lowering: `loop_header`, condition branch, body, back-edge jump.
248. **Task 248:** Implement `for` lowering: range (init index, cond, increment) and slice (extract ptr/len, index loop).
249. **Task 249:** Implement `switch` lowering: extract tag, emit `switch_br` with case targets.
250. **Task 250:** Implement `break`/`continue`/`return` lowering with defer expansion.

#### Defer & Errdefer Expansion
251. **Task 251:** Implement `DeferAction` stack: push on `defer`/`errdefer` statements.
252. **Task 252:** Implement `expandDefers(target_depth, is_error_path)`: unwind stack, emit deferred statements.
253. **Task 253:** Integrate defer expansion at all exit points: `return`, `break`, `continue`, block end.
254. **Task 254:** Implement TCO pattern handling: `continue` inside `while(true)` skips outer defers.
255. **Task 255:** Add `try` lowering: `check_error`, branch to propagate (expand errdefers) or unwrap payload.

#### Coercion & Temporary Hoisting
256. **Task 256:** Implement `applyCoercion(src_temp, coercion)`: emit `wrap_optional`, `int_cast`, `make_slice`, etc.
257. **Task 257:** Implement temporary generation: `nextTemp(type_id)` appends to `hoisted_temps`.
258. **Task 258:** Implement `hoistTemps()`: move all `decl_temp` instructions to entry block.
259. **Task 259:** Implement `std.debug.print` lowering: emit `print_str` and `print_val` instructions.
260. **Task 260:** Add LIR lowering unit tests: basic arithmetic, control flow, defer, coercion.

---

### Milestone 8: C89 Code Emission

#### Emitter Foundation
261. **Task 261:** Implement `BufferedWriter` with 4KB buffer, `write()`, `writeIndent()`, `flush()`.
262. **Task 262:** Implement `C89Emitter` struct: `writer`, `indent`, `reg`, `interner`, `mangler`, `diag`.
263. **Task 263:** Implement `NameMangler` with FNV-1a hash, keyword detection, 31-char truncation.
264. **Task 264:** Implement `mangleName(name_id, kind, module_id)`: produce `zF_HASH_name` format.
265. **Task 265:** Generate `zig_compat.h` with `__int64`, `bool`, `true`/`false` definitions.

#### Type Emission (Phase 1)
266. **Task 266:** Implement topological sort of types for `zig_special_types.h` emission.
267. **Task 267:** Emit slice types: `typedef struct { T* ptr; unsigned int len; } zS_Slice_T;`.
268. **Task 268:** Emit optional types: `typedef struct { T value; int has_value; } zS_Opt_T;`.
269. **Task 269:** Emit error union types: `typedef struct { union { T payload; int err; } data; int is_error; } zS_EU_T;`.
270. **Task 270:** Emit tagged union types: `typedef struct { int tag; union { ... } payload; } zS_TU_Name;`.

#### Function Body Emission (Phase 2)
271. **Task 271:** Implement `emitFunctionSignature(fn)`: write return type, mangled name, parameters.
272. **Task 272:** Implement `emitHoistedDecls(fn)`: write `T __tmp_N;` for all hoisted temps.
273. **Task 273:** Implement block emission: iterate blocks in ID order, emit `z_bb_N:` labels.
274. **Task 274:** Implement instruction emission: map `LirInst` variants to C89 syntax (see mapping table).
275. **Task 275:** Implement `switch_br` emission: generate C89 `switch(cond) { case V: goto z_bb_N; default: ... }`.

#### Coercion & Runtime Helpers
276. **Task 276:** Emit `wrap_optional` as struct field assignments.
277. **Task 277:** Emit `int_cast` as C cast or `__bootstrap_checked_cast_*` call.
278. **Task 278:** Emit `make_slice` as struct construction `{ .ptr = p, .len = l }`.
279. **Task 279:** Emit `print_str`/`print_val` as `__bootstrap_print*` calls.
280. **Task 280:** Generate `zig_runtime.c` with panic handler, arena allocator, checked conversions.

#### Module Output & Integration
281. **Task 281:** Implement `emitModule(module)`: write `.c` and `.h` files.
282. **Task 282:** Write `build_target.bat`/`build_target.sh` scripts for C89 compilation.
283. **Task 283:** Implement `--dump-c89` flag for differential testing.
284. **Task 284:** Validate generated C89 compiles with `gcc -std=c89 -pedantic -Wall -Werror`.
285. **Task 285:** Run differential test: `zig0` vs `zig1` C89 output for reference programs.

---

### Milestone 9: Integration, Testing & Self-Hosting

#### Full Pipeline Integration
286. **Task 286:** Wire all passes together in `main.zig`: import resolution → symbol registration → type resolution → semantic analysis → static analyzers → LIR lowering → C89 emission.
287. **Task 287:** Implement phase gates: stop after semantic analysis if `hasErrors()`.
288. **Task 288:** Add CLI flags for all pipeline options: `--dump-tokens`, `--dump-ast`, `--dump-types`, `--dump-lir`, `--dump-c89`.
289. **Task 289:** Implement peak memory tracking across all arenas.
290. **Task 290:** Add `--max-mem=N` enforcement: panic if limit exceeded.

#### Reference Program Validation
291. **Task 291:** Compile `mandelbrot.zig` through full pipeline, verify C89 output runs correctly.
292. **Task 292:** Compile `game_of_life.zig`, verify output.
293. **Task 293:** Compile `mud.zig`, verify output.
294. **Task 294:** Compile `eval.zig` (Lisp interpreter), verify TCO and deep switches work.
295. **Task 295:** Run memory gate on all reference programs: peak < 16 MB.

#### Self-Hosting Bootstrap
296. **Task 296:** Compile `zig1` source with `zig0` → `zig1.exe`.
297. **Task 297:** Compile `zig1` source with `zig1.exe` → `zig2.exe`.
298. **Task 298:** Verify `fc /b zig1.exe zig2.exe` (byte-identical).
299. **Task 299:** Run full test suite with `zig1.exe`.
300. **Task 300:** Document build process, known limitations, and extensibility hooks.

---

## Pipeline Summary with Static Analyzer Placement

```
Source Files
    │
    ▼
[1. Lexing] ───► Tokens
    │
    ▼
[2. Parsing] ──► AST
    │
    ▼
[3. Import Resolution] ──► Module Graph
    │
    ▼
[4. Symbol Registration] ──► Symbol Tables + Type Stubs
    │
    ▼
[5. Type Resolution] (Kahn) ──► Resolved Types
    │
    ▼
[6. Semantic Analysis] ──► ResolvedTypeTable + CoercionTable
    │
    ▼
┌─────────────────────────────────────────────┐
│ [Pass 6] SignatureAnalyzer                  │
│ [Pass 7] NullPointerAnalyzer                │  ◄── Static Analyzers
│ [Pass 8] LifetimeAnalyzer                   │      (per-function, flow-sensitive)
│ [Pass 9] DoubleFreeAnalyzer                 │
└─────────────────────────────────────────────┘
    │
    ▼
[10. LIR Lowering] ──► LirFunction basic blocks
    │
    ▼
[11. LIR Optimization] (optional placeholder)
    │
    ▼
[12. C89 Emission] ──► .c / .h files
```

**Static analyzers run after semantic analysis** because they need fully resolved types and symbol information. They run **before LIR lowering** so that any detected errors prevent code generation (consistent with `hasErrors()` gate). They are per‑function and use the `scratch` arena, resetting between functions to stay within memory budget.We need to integrate the static analyzers into the pipeline and outline tasks for them. Based on the design documents, the static analyzers (Signature, NullPointer, Lifetime, DoubleFree) are passes 6-9 that run **after** type resolution and semantic analysis, but **before** LIR lowering. They are per-function flow-sensitive analyses that use the resolved type information and symbol tables to detect safety issues.

Let me produce a comprehensive extension of the AI Agent Tasks document covering Milestones 3 through 9, with detailed tasks for import resolution, symbol registration, type system, semantic analysis, static analyzers, LIR lowering, and C89 emission. I'll maintain the same format with numbered tasks and clear phase boundaries.

---

# AI Agent Tasks for Z98 Self-Hosted Compiler (`zig1`) – Extended Milestones 3–9

This document extends the existing task list for `zig1` implementation, covering the complete compiler pipeline from import resolution through C89 emission and static analysis.

---

## Phase 0: The Self-Hosted Compiler (Z98) – Continued

### Milestone 3: Import Resolution & Symbol Registration

#### Module Registry Foundation
111. **Task 111:** Define `ModuleState` enum: `pending`, `parsing`, `parsed`, `resolved`, `failed`.
112. **Task 112:** Define `ModuleEntry` struct: `id`, `path_id`, `state`, `ast_root`, `import_count`, `imports_start`, `symbol_table`, `type_offset`.
113. **Task 113:** Implement `ModuleRegistry` struct with `ArrayList(ModuleEntry)`, `import_edges: ArrayList(u32)`, `path_to_id: U32ToU32Map`.
114. **Task 114:** Implement `ModuleResolver` with search order: importing dir → `-I` flags → default `lib/`.
115. **Task 115:** Add `resolveImport(path_id, importer_id)` to locate file, intern absolute path, return `module_id`.

#### On-Demand Parsing & Import Queue
116. **Task 116:** Implement `ImportQueue` struct: `pending: ArrayList(u32)` with duplicate detection.
117. **Task 117:** Modify parser `parseImportExpr()` to queue discovered imports via `enqueue(module_id)`.
118. **Task 118:** Implement `resolveImports()` loop: pop module, parse if pending, queue newly discovered imports.
119. **Task 119:** Add per-module arena management: `module_arena` allocated at parse time, token arena reset after AST built.
120. **Task 120:** Implement import cycle detection: record import edges during parsing.

#### Topological Module Sorting (Kahn's Algorithm)
121. **Task 121:** Implement `sortModules()`: compute in-degrees from `import_edges`.
122. **Task 122:** Seed worklist with modules having `in_degree == 0`; sort worklist for determinism.
123. **Task 123:** Process worklist: mark module `.resolved`, decrement in-degree of importers, enqueue when zero.
124. **Task 124:** Detect cycles: any module with `in_degree > 0` after processing → mark `.failed`, emit `ERR_CIRCULAR_IMPORT`.
125. **Task 125:** Verify topological order: imported modules appear before importers.

#### Symbol Table Structures
126. **Task 126:** Define `SymbolKind` enum: `global`, `function`, `type_alias`, `module`, `test`.
127. **Task 127:** Define `Symbol` struct: `name_id`, `type_id` (0 initially), `kind`, `flags` (pub/extern/export/const), `decl_node`, `module_id`, `scope_depth`.
128. **Task 128:** Implement per-module `SymbolTable` with global scope only (Pass 3 uses scope 0).
129. **Task 129:** Implement `SymbolTable.insert(sym)` with duplicate detection (linear scan, small N).
130. **Task 130:** Create `SymbolRegistry` holding `[]SymbolTable` indexed by `ModuleId`.

#### Top-Level Symbol Registration
131. **Task 131:** Implement `registerModuleSymbols(module_id)`: iterate `module_root` extra children, dispatch on `AstKind`.
132. **Task 132:** Implement `registerVarDecl()`: create `Symbol` with `.global` kind, `flags` from node.
133. **Task 133:** Implement `registerFnDecl()`: create `Symbol` with `.function` kind, extract `name_id` from `FnProto`.
134. **Task 134:** Implement `registerTestDecl()`: create `Symbol` with `.test` kind, store body reference.
135. **Task 135:** Implement `registerTypeDecl()`: call `TypeRegistry.registerNamedType()` to create `unresolved_name` stub, then register `.type_alias` symbol.

#### Type Stub Creation & Dependency Graph
136. **Task 136:** Implement `TypeRegistry.registerNamedType(module_id, name_id, kind)`: create `Type` with `state=0` (unresolved), assign `TypeId`, insert into `name_cache`.
137. **Task 137:** Implement `addTypeDependencies(tid, node)`: walk struct/union fields, add edges to `DepGraph` for value-type fields.
138. **Task 138:** Define `isValueDependency(kind)`: true for struct/union/enum/array/optional/error_union, false for pointer/slice/fn.
139. **Task 139:** Build `DepGraph` with `edges: ArrayList(DepEntry)` and `in_degree: []u32` indexed by `TypeId`.
140. **Task 140:** Add registration unit tests: duplicate symbol detection, type stub creation, dependency edges.

#### Cross-Module Visibility & Import Tests
141. **Task 141:** Implement visibility flag checks: `pub` → visible to importers; default → private.
142. **Task 142:** Add qualified lookup preparation: store `module_id` in `Symbol` for cross-module resolution.
143. **Task 143:** Write integration tests: multi-module import chains, circular import detection, visibility enforcement.
144. **Task 144:** Verify deterministic `ModuleId` assignment and symbol registration order.
145. **Task 145:** Run memory gate: 50-module project, peak `permanent` + `module` arenas < 16 MB.

---

### Milestone 4: Type System & Type Resolution

#### TypeRegistry Foundation
146. **Task 146:** Define `TypeKind` enum with 39 kinds: primitives, compound types, `unresolved_name`, `type_type`, `module_type`, `null_type`, etc.
147. **Task 147:** Define `Type` struct: `kind`, `state` (0=unresolved,1=resolving,2=resolved), `flags`, `size`, `alignment`, `name_id`, `c_name_id`, `module_id`, `payload_idx`.
148. **Task 148:** Implement `TypeRegistry` with `ArrayList(Type)` and kind-specific payload arrays (`ptr_payloads`, `array_payloads`, etc.).
149. **Task 149:** Implement well-known primitive `TypeId`s: `TYPE_VOID=1`, `TYPE_BOOL=2`, …, `TYPE_INT_LIT=19`, `FIRST_USER_TYPE=20`.
150. **Task 150:** Register all primitives during `TypeRegistry.init()` with correct sizes/alignments.

#### Concrete Hash Maps (No Generics)
151. **Task 151:** Implement `U32ToU32Map`: open addressing with linear probing, `keys`, `values`, `occupied` arrays, `get()`/`put()` methods.
152. **Task 152:** Implement `U64ToU32Map`: same structure with `u64` keys.
153. **Task 153:** Add `ptr_cache: U64ToU32Map` keyed by `(base_tid << 1) | is_const`.
154. **Task 154:** Add `slice_cache: U64ToU32Map` keyed by `(elem_tid << 1) | is_const`.
155. **Task 155:** Add `optional_cache: U32ToU32Map`, `array_cache: U64ToU32Map`, `name_cache: U64ToU32Map`.

#### Type Creation (Deduplicated)
156. **Task 156:** Implement `getOrCreatePtr(base, is_const)`: check cache, create `PtrPayload`, append `Type` with `size=4, align=4`.
157. **Task 157:** Implement `getOrCreateSlice(elem, is_const)`: check cache, create `SlicePayload`, append `Type` with `size=8, align=4`.
158. **Task 158:** Implement `getOrCreateOptional(payload)`: defer size/align if payload unresolved, compute layout when resolved.
159. **Task 159:** Implement `getOrCreateArray(elem, length)`, `getOrCreateErrorUnion(payload, error_set)`.
160. **Task 160:** Add helper methods: `isNumeric()`, `isInteger()`, `isPointer()`, `getPointeeType()`.

#### Dependency Graph & Kahn's Type Resolution
161. **Task 161:** Finalize `DepGraph` after symbol registration: allocate `in_degree` array sized to `types.items.len`.
162. **Task 162:** Seed worklist with types having `in_degree == 0` and `state == 0` (unresolved).
163. **Task 163:** Implement `resolveTypeLayout(tid)`: compute size/alignment for struct/union/tagged_union/array/optional/error_union/tuple.
164. **Task 164:** Implement struct layout: iterate fields, align offsets, compute max alignment, final size.
165. **Task 165:** Implement tagged union layout: tag first, padding, union payload, overall alignment.

#### Cycle Detection & Error Handling
166. **Task 166:** After Kahn's algorithm, scan for types with `state != 2` and `in_degree > 0` → circular dependency.
167. **Task 167:** Emit `ERR_CIRCULAR_TYPE_DEPENDENCY`, mark cyclic types as `TYPE_VOID`.
168. **Task 168:** Implement `resolveTypeFromAst(node_idx)`: walk type expression AST, call appropriate `getOrCreate*`.
169. **Task 169:** Add unit tests: pointer/slice deduplication, struct layout, array stride, optional size.
170. **Task 170:** Add integration tests: forward reference resolution, cross-module type resolution, cycle detection.

---

### Milestone 5: Semantic Analysis & Comptime Evaluation

#### Resolved Type Table & Symbol Resolution
171. **Task 171:** Implement `ResolvedTypeTable`: side-table mapping `node_idx → TypeId` via `U32ToU32Map`.
172. **Task 172:** Implement `SemanticAnalyzer` struct with `expected_type_stack: ArrayList(TypeId)`.
173. **Task 173:** Implement `resolveExpr(node_idx)`: dispatch on `AstKind`, store result in `ResolvedTypeTable`.
174. **Task 174:** Implement identifier resolution: lookup in `SymbolTable`, return symbol's `type_id`.
175. **Task 175:** Implement field access resolution: for structs/unions, lookup field; for modules, cross-module symbol lookup.

#### Expression Type Checking
176. **Task 176:** Implement arithmetic operator type rules: numeric same-type, literal promotion, pointer arithmetic.
177. **Task 177:** Implement comparison operator rules: same-type numeric, optional null check, error set comparison.
178. **Task 178:** Implement `resolveFnCall()`: check argument count, push expected types, check assignability, record coercions.
179. **Task 179:** Implement `resolveTryExpr()`: verify operand is error union, propagate error context.
180. **Task 180:** Implement `resolveIfExpr()` and `resolveSwitchExpr()`: unify branch types, check exhaustiveness.

#### Coercion Table & Assignability
181. **Task 181:** Implement `isAssignable(source, target)`: check direct equality, integer literal fit, optional/error wrapping, pointer/slice const-qualifying.
182. **Task 182:** Implement `CoercionKind` enum: `none`, `wrap_optional`, `array_to_slice`, `int_widen`, etc.
183. **Task 183:** Implement `CoercionTable`: side-table mapping `node_idx → CoercionEntry` via `U32ToU32Map`.
184. **Task 184:** Add `classifyCoercion(source, target)`: determine `CoercionKind` based on type relationship.
185. **Task 185:** Integrate coercion recording: after resolving expression, if coercion needed, add to table.

#### Comptime Evaluation
186. **Task 186:** Implement `ComptimeEval` struct with `evaluate(node_idx) -> ?u64`.
187. **Task 187:** Implement constant folding for `@sizeOf` and `@alignOf`: resolve type argument, return size/alignment.
188. **Task 188:** Implement constant folding for integer arithmetic: `add`, `sub`, `mul`, `div`, `mod_op` on constants.
189. **Task 189:** Implement `@intCast` folding when both type and value are comptime-known.
190. **Task 190:** Implement `canLiteralFitInType(value, target)`: range check for integer literal coercion.

#### Constraint Checking & Diagnostics
191. **Task 191:** Verify switch exhaustiveness: for enum switches, ensure all variants covered or `else` present.
192. **Task 192:** Check `return` type compatibility: returned expression assignable to function return type.
193. **Task 193:** Check `break`/`continue` validity: inside loop, not across defer boundaries.
194. **Task 194:** Implement `std.debug.print` decomposition: parse format string, validate argument count, record decomposition.
195. **Task 195:** Add semantic analysis unit tests: type mismatch, undefined symbol, coercion, switch exhaustiveness.

---

### Milestone 6: Static Analyzers (Passes 6–9)

*Note: These passes run **after** semantic analysis and **before** LIR lowering. They operate per-function using the `scratch` arena.*

#### Shared Infrastructure for Flow-Sensitive Analysis
196. **Task 196:** Implement `StateMap` with delta-linked parent pointers: `entries: ArrayList(StateEntry)`, `parent: ?*StateMap`.
197. **Task 197:** Implement `StateMap.fork()`: O(1) child creation with parent pointer.
198. **Task 198:** Implement `StateMap.get(name_id)`: walk parent chain to find state.
199. **Task 199:** Implement `StateMap.set(name_id, state)`: local override only.
200. **Task 200:** Implement `mergeStates(parent, branch_a, branch_b, unknown_state)`: conservative join of divergent states.

#### Iterative Function Visitor
201. **Task 201:** Implement `walkBlock(ctx, state, block_idx, handler)`: iterative traversal of statements in control-flow order.
202. **Task 202:** Implement `visitStatement` dispatch for each analyzer (function pointer or switch).
203. **Task 203:** Add branch handling: for `if`, `while`, `switch`, fork state, walk branches, merge.
204. **Task 204:** Implement loop analysis: track modified variables, mark as `unknown` after loop exit.
205. **Task 205:** Add `defer_stack` tracking for scope exit processing.

#### SignatureAnalyzer (Pass 6)
206. **Task 206:** Implement `analyzeSignature(fn_node)`: check parameter/return types for C89 compatibility.
207. **Task 207:** Reject `void` parameter types → `ERR_VOID_PARAMETER`.
208. **Task 208:** Reject incomplete struct/union in signature → `ERR_INCOMPLETE_TYPE`.
209. **Task 209:** Reject `anytype` and opaque types → `ERR_ANYTYPE_NOT_SUPPORTED`.
210. **Task 210:** Warn on return types > 64 bytes → `WARN_LARGE_RETURN`.

#### NullPointerAnalyzer (Pass 7)
211. **Task 211:** Define `PtrState` enum: `uninit`, `is_null`, `safe`, `maybe`.
212. **Task 212:** Implement state transitions for assignments, null checks, captures, function calls.
213. **Task 213:** Implement `classifyExpr()` for nullability: address-of → `safe`, null literal → `is_null`, function call → `maybe`.
214. **Task 214:** Implement null guard detection: recognize `if (ptr != null)`, `if (opt) |val|`, `while (opt) |val|`.
215. **Task 215:** On dereference (`.*`, `[i]`), check pointer state: `is_null` → error, `uninit`/`maybe` → warning.
216. **Task 216:** Add unit tests: null guard refinement, optional capture, branch merging.

#### LifetimeAnalyzer (Pass 8)
217. **Task 217:** Define `Provenance` enum: `unknown`, `local`, `param`, `param_addr`, `global`, `heap`.
218. **Task 218:** Implement `resolveOrigin(expr)`: walk field/index to find base local variable.
219. **Task 219:** Implement `classifyProvenance()`: address-of local → `local`, address-of param → `param_addr`, function call → `heap`.
220. **Task 220:** On `return`, check provenance: `local` or `param_addr` → error (dangling pointer).
221. **Task 221:** On slice creation (`arr[0..n]`), check base origin: local array → warning.
222. **Task 222:** Add unit tests: returning &local, returning slice of local, parameter address.

#### DoubleFreeAnalyzer (Pass 9)
223. **Task 223:** Define `AllocState` enum: `untracked`, `allocated`, `freed`, `returned_val`, `transferred`, `unknown`.
224. **Task 224:** Implement allocation detection: recognize `arena_alloc` and `try arena_alloc` calls.
225. **Task 225:** Implement free detection: recognize `arena_free` call, extract pointer argument.
226. **Task 226:** Track state per pointer: on alloc → `allocated`; on free → `freed`; double free → error.
227. **Task 227:** On scope exit, check for unfreed pointers → leak warning.
228. **Task 228:** On pointer overwrite or function pass, mark as `transferred` or `returned_val`.
229. **Task 229:** Implement composite name tracking for struct fields (e.g., `container.ptr`).
230. **Task 230:** Add unit tests: double free, leak detection, ownership transfer, defer handling.

#### Static Analyzer Integration & Pipeline
231. **Task 231:** Create `runAllAnalyzers(ctx, module_root)`: iterate functions, run each analyzer, reset scratch arena between functions.
232. **Task 232:** Add CLI flags: `--no-null-check`, `--no-lifetime-check`, `--no-leak-check`, `--warn-all`, `--warn-error`.
233. **Task 233:** Integrate analyzer diagnostics into `DiagnosticCollector` with appropriate error/warning codes.
234. **Task 234:** Write integration tests: `eval.zig` (complex control flow), `mud.zig` (arena usage), `game_of_life.zig` (tagged unions).
235. **Task 235:** Verify static analyzers do not exceed per-function scratch memory budget (512 KB).

---

### Milestone 7: LIR Lowering

#### LIR Data Structures
236. **Task 236:** Define `LirInst` union: `decl_temp`, `assign`, `binary`, `branch`, `switch_br`, `call`, `ret`, etc. (see `AST_LIR_Lowering.md` Appendix A).
237. **Task 237:** Define `BasicBlock` struct: `id: u32`, `insts: ArrayList(LirInst)`, `is_terminated: bool`.
238. **Task 238:** Define `LirFunction` struct: `name_id`, `return_type`, `params: ArrayList(LirParam)`, `blocks: ArrayList(BasicBlock)`, `hoisted_temps: ArrayList(TempDecl)`.
239. **Task 239:** Define `LirLowerer` struct with `func: *LirFunction`, `current_bb: u32`, `temp_counter: u32`, `defer_stack`, `loop_stack`.
240. **Task 240:** Implement basic block creation: `createBlock()` returns `u32` block ID.

#### Expression Lowering
241. **Task 241:** Implement `lowerExpr(node_idx) -> u32` (returns temp ID).
242. **Task 242:** Implement literal lowering: `int_const`, `float_const`, `string_const`, `bool_const`, `null_const`.
243. **Task 243:** Implement binary/unary operator lowering: emit `binary`/`unary` LIR instructions.
244. **Task 244:** Implement field/index access lowering: `load_field`, `load_index`, `load`, `addr_of`.
245. **Task 245:** Implement function call lowering: lower callee and args, emit `call` instruction.

#### Control Flow Lowering
246. **Task 246:** Implement `if` lowering: `branch` to then/else blocks, merge with phi-like temp assignment.
247. **Task 247:** Implement `while` lowering: `loop_header`, condition branch, body, back-edge jump.
248. **Task 248:** Implement `for` lowering: range (init index, cond, increment) and slice (extract ptr/len, index loop).
249. **Task 249:** Implement `switch` lowering: extract tag, emit `switch_br` with case targets.
250. **Task 250:** Implement `break`/`continue`/`return` lowering with defer expansion.

#### Defer & Errdefer Expansion
251. **Task 251:** Implement `DeferAction` stack: push on `defer`/`errdefer` statements.
252. **Task 252:** Implement `expandDefers(target_depth, is_error_path)`: unwind stack, emit deferred statements.
253. **Task 253:** Integrate defer expansion at all exit points: `return`, `break`, `continue`, block end.
254. **Task 254:** Implement TCO pattern handling: `continue` inside `while(true)` skips outer defers.
255. **Task 255:** Add `try` lowering: `check_error`, branch to propagate (expand errdefers) or unwrap payload.

#### Coercion & Temporary Hoisting
256. **Task 256:** Implement `applyCoercion(src_temp, coercion)`: emit `wrap_optional`, `int_cast`, `make_slice`, etc.
257. **Task 257:** Implement temporary generation: `nextTemp(type_id)` appends to `hoisted_temps`.
258. **Task 258:** Implement `hoistTemps()`: move all `decl_temp` instructions to entry block.
259. **Task 259:** Implement `std.debug.print` lowering: emit `print_str` and `print_val` instructions.
260. **Task 260:** Add LIR lowering unit tests: basic arithmetic, control flow, defer, coercion.

---

### Milestone 8: C89 Code Emission

#### Emitter Foundation
261. **Task 261:** Implement `BufferedWriter` with 4KB buffer, `write()`, `writeIndent()`, `flush()`.
262. **Task 262:** Implement `C89Emitter` struct: `writer`, `indent`, `reg`, `interner`, `mangler`, `diag`.
263. **Task 263:** Implement `NameMangler` with FNV-1a hash, keyword detection, 31-char truncation.
264. **Task 264:** Implement `mangleName(name_id, kind, module_id)`: produce `zF_HASH_name` format.
265. **Task 265:** Generate `zig_compat.h` with `__int64`, `bool`, `true`/`false` definitions.

#### Type Emission (Phase 1)
266. **Task 266:** Implement topological sort of types for `zig_special_types.h` emission.
267. **Task 267:** Emit slice types: `typedef struct { T* ptr; unsigned int len; } zS_Slice_T;`.
268. **Task 268:** Emit optional types: `typedef struct { T value; int has_value; } zS_Opt_T;`.
269. **Task 269:** Emit error union types: `typedef struct { union { T payload; int err; } data; int is_error; } zS_EU_T;`.
270. **Task 270:** Emit tagged union types: `typedef struct { int tag; union { ... } payload; } zS_TU_Name;`.

#### Function Body Emission (Phase 2)
271. **Task 271:** Implement `emitFunctionSignature(fn)`: write return type, mangled name, parameters.
272. **Task 272:** Implement `emitHoistedDecls(fn)`: write `T __tmp_N;` for all hoisted temps.
273. **Task 273:** Implement block emission: iterate blocks in ID order, emit `z_bb_N:` labels.
274. **Task 274:** Implement instruction emission: map `LirInst` variants to C89 syntax (see mapping table).
275. **Task 275:** Implement `switch_br` emission: generate C89 `switch(cond) { case V: goto z_bb_N; default: ... }`.

#### Coercion & Runtime Helpers
276. **Task 276:** Emit `wrap_optional` as struct field assignments.
277. **Task 277:** Emit `int_cast` as C cast or `__bootstrap_checked_cast_*` call.
278. **Task 278:** Emit `make_slice` as struct construction `{ .ptr = p, .len = l }`.
279. **Task 279:** Emit `print_str`/`print_val` as `__bootstrap_print*` calls.
280. **Task 280:** Generate `zig_runtime.c` with panic handler, arena allocator, checked conversions.

#### Module Output & Integration
281. **Task 281:** Implement `emitModule(module)`: write `.c` and `.h` files.
282. **Task 282:** Write `build_target.bat`/`build_target.sh` scripts for C89 compilation.
283. **Task 283:** Implement `--dump-c89` flag for differential testing.
284. **Task 284:** Validate generated C89 compiles with `gcc -std=c89 -pedantic -Wall -Werror`.
285. **Task 285:** Run differential test: `zig0` vs `zig1` C89 output for reference programs.

---

### Milestone 9: Integration, Testing & Self-Hosting

#### Full Pipeline Integration
286. **Task 286:** Wire all passes together in `main.zig`: import resolution → symbol registration → type resolution → semantic analysis → static analyzers → LIR lowering → C89 emission.
287. **Task 287:** Implement phase gates: stop after semantic analysis if `hasErrors()`.
288. **Task 288:** Add CLI flags for all pipeline options: `--dump-tokens`, `--dump-ast`, `--dump-types`, `--dump-lir`, `--dump-c89`.
289. **Task 289:** Implement peak memory tracking across all arenas.
290. **Task 290:** Add `--max-mem=N` enforcement: panic if limit exceeded.

#### Reference Program Validation
291. **Task 291:** Compile `mandelbrot.zig` through full pipeline, verify C89 output runs correctly.
292. **Task 292:** Compile `game_of_life.zig`, verify output.
293. **Task 293:** Compile `mud.zig`, verify output.
294. **Task 294:** Compile `eval.zig` (Lisp interpreter), verify TCO and deep switches work.
295. **Task 295:** Run memory gate on all reference programs: peak < 16 MB.

#### Self-Hosting Bootstrap
296. **Task 296:** Compile `zig1` source with `zig0` → `zig1.exe`.
297. **Task 297:** Compile `zig1` source with `zig1.exe` → `zig2.exe`.
298. **Task 298:** Verify `fc /b zig1.exe zig2.exe` (byte-identical).
299. **Task 299:** Run full test suite with `zig1.exe`.
300. **Task 300:** Document build process, known limitations, and extensibility hooks.

---

## Pipeline Summary with Static Analyzer Placement

```
Source Files
    │
    ▼
[1. Lexing] ───► Tokens
    │
    ▼
[2. Parsing] ──► AST
    │
    ▼
[3. Import Resolution] ──► Module Graph
    │
    ▼
[4. Symbol Registration] ──► Symbol Tables + Type Stubs
    │
    ▼
[5. Type Resolution] (Kahn) ──► Resolved Types
    │
    ▼
[6. Semantic Analysis] ──► ResolvedTypeTable + CoercionTable
    │
    ▼
┌─────────────────────────────────────────────┐
│ [Pass 6] SignatureAnalyzer                  │
│ [Pass 7] NullPointerAnalyzer                │  ◄── Static Analyzers
│ [Pass 8] LifetimeAnalyzer                   │      (per-function, flow-sensitive)
│ [Pass 9] DoubleFreeAnalyzer                 │
└─────────────────────────────────────────────┘
    │
    ▼
[10. LIR Lowering] ──► LirFunction basic blocks
    │
    ▼
[11. LIR Optimization] (optional placeholder)
    │
    ▼
[12. C89 Emission] ──► .c / .h files
```

**Static analyzers run after semantic analysis** because they need fully resolved types and symbol information. They run **before LIR lowering** so that any detected errors prevent code generation (consistent with `hasErrors()` gate). They are per‑function and use the `scratch` arena, resetting between functions to stay within memory budget.
