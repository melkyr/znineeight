# AI Agent Tasks for RetroZig Compiler

This document outlines a granular, step-by-step roadmap for an AI agent to implement the RetroZig compiler. The tasks are organized by phase and component, starting with the C++ bootstrap compiler.

## Phase 0: The Bootstrap Compiler (C++98)

### Milestone 1: Core Infrastructure
1.  **Task 1:** Set up the basic directory structure. (DONE)
2.  **Task 2:** Create the `common.hpp` compatibility header. (DONE)
3.  **Task 3:** Implement the `ArenaAllocator` class. (DONE)
4.  **Task 4:** Add alignment support to `ArenaAllocator`. (DONE)
5.  **Task 5:** Implement the `StringInterner` class. (DONE)
6.  **Task 6:** Implement the `SourceManager` class. (DONE)
7.  **Task 7:** Define the `ErrorReport` struct and `ErrorCode` enum. (DONE)
8.  **Task 8:** Implement a basic diagnostic printing function. (DONE)
9.  **Task 9:** Create a minimal unit testing framework. (DONE)
10. **Task 10:** Create initial `build.bat` and `test.bat` scripts. (DONE)

### Milestone 2: Lexer Implementation
11. **Task 11:** Define initial `TokenType` enum in `lexer.hpp`. (DONE)
12. **Task 12:** Implement the `Token` struct with a union for literal values. (DONE)
13. **Task 13:** Implement the `Lexer` class skeleton. (DONE)
14. **Task 14:** Implement lexing for single-character tokens. (DONE)
15. **Task 15:** Implement lexing for multi-character tokens. (DONE)
16. **Task 16:** Implement basic identifier and keyword recognition. (DONE)
17. **Task 17:** Update `TokenType` enum in `src/include/lexer.hpp` to include all missing tokens as defined in `Lexer.md`.
18. **Task 18:** Implement lexing for `TOKEN_CHAR_LITERAL` (e.g., `'a'`). (DONE)
19. **Task 19:** Implement lexing for `TOKEN_FLOAT_LITERAL` (e.g., `3.14`). (DONE)
20. **Task 20:** Implement lexing for remaining arithmetic and bitwise operators (`%`, `~`, `&`, `|`, `^`, `<<`, `>>`).
21. **Task 21:** Implement lexing for compound assignment operators (`+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=`, `>>=`). (DONE)
22. **Task 22:** Implement lexing for special and wrapping operators (`.`, `.*`, `.?`, `?`, `++`, `**`, `||`, `+%`, `-%`, `*%`).
23. **Task 23:** Implement lexing for remaining delimiters (`:`, `->`, `=>`, `...`).
24. **Task 24:** Implement keyword recognition for control flow (`break`, `catch`, `continue`, `else`, `for`, `if`, `orelse`, `resume`, `suspend`, `switch`, `try`, `while`). (DONE)
25. **Task 25:** Implement keyword recognition for type declarations (`enum`, `error`, `struct`, `union`, `opaque`).
26. **Task 26:** Implement keyword recognition for visibility and linkage (`export`, `extern`, `pub`, `linksection`, `usingnamespace`). (DONE)
27. **Task 27:** Implement keyword recognition for compile-time and special functions (`asm`, `comptime`, `errdefer`, `inline`, `noinline`, `test`, `unreachable`). (DONE)
28. **Task 28:** Implement keyword recognition for memory and calling conventions (`addrspace`, `align`, `allowzero`, `and`, `anyframe`, `anytype`, `callconv`, `noalias`, `nosuspend`, `or`, `packed`, `threadlocal`, `volatile`). (DONE)
29. **Task 29:** Implement logic to skip single-line and block comments. (This was previously part of other tasks, now consolidated).
30. **Task 30:** Write comprehensive unit tests for the lexer, covering all new token types and edge cases.
31. **Task 31:** Implement lexing for `TOKEN_STRING_LITERAL` and properly handle `TOKEN_IDENTIFIER` values. This includes storing the string content (for string literals) and the identifier name, likely using the string interner.
32. **Task 32:** Extend the lexer to handle escaped characters in string literals (e.g., `\n`, `\t`, `\\`, `\"`).
33. **Task 33:** Implement lexing for crucial missing keywords (`fn`, `var`, `defer`).
34. **Task 34:** Implement lexing for missing operators (`--`, `&&`).

### Milestone 3: Parser & AST
35. **Task 35:** Define foundational AST structures and nodes for Expressions (Literals, Unary, Binary).
36. **Task 36:** Define AST nodes for Statements (`IfStmt`, `WhileStmt`, `ReturnStmt`, `DeferStmt`, `BlockStmt`).
37. **Task 37:** Define AST nodes for Declarations (`FnDecl`, `VarDecl`, `ParamDecl`).
38. **Task 38:** Define AST nodes for Type Expressions (`TypeName`, `PointerType`, `ArrayType`). (DONE)
39. **Task 39:** Define AST nodes for Container Declarations (`struct`, `enum`, `union`). (DONE)
    - Add `ASTStructDeclNode`, `ASTEnumDeclNode`, `ASTUnionDeclNode`.
    - Add corresponding `NodeType` enums.
    - Create a basic compile-time test to validate the new structures.
40. **Task 40:** Define AST nodes for Control Flow (`for`, `switch`).
    - Add `ASTForStmtNode` and `ASTSwitchExprNode`.
    - Add corresponding `NodeType` enums.
    - Create a basic compile-time test to validate the new structures.
41. **Task 41:** Define AST nodes for Error Handling (`try`, `catch`, `errdefer`).
    - Add `ASTTryExprNode`, `ASTCatchExprNode`, and `ASTErrDeferStmtNode`.
    - Add corresponding `NodeType` enums.
    - Create a basic compile-time test to validate the new structures.
42. **Task 42:** Define AST nodes for Async Operations (`async`, `await`).
    - Add `ASTAsyncExprNode` and `ASTAwaitExprNode`.
    - Add corresponding `NodeType` enums.
    - Create a basic compile-time test to validate the new structures.
43. **Task 43:** Define AST nodes for Comptime Operations (`comptime`). (DONE)
    - Add `ASTComptimeBlockNode`.
    - Add corresponding `NodeType` enum.
    - Create a basic compile-time test to validate the new structure.
44. **Task 44:** Implement the `Parser` class skeleton with helper methods (`advance`, `match`, `expect`).
45. **Task 45:** Implement `parseType` to handle type expressions (e.g., `i32`, `*u8`, `[]bool`).
46. **Task 46:** Implement parsing for top-level variable declarations (`var` and `const`).
47. **Task 47:** Refactor Parser Error Handling and Cleanup.
    - Remove the forbidden `<cstdio>` header include from `src/bootstrap/parser.cpp`.
    - Modify the `error()` function to remove the `fprintf` call, ensuring it only uses `OutputDebugStringA` (under `#ifdef _WIN32`) and `abort()`.
    - Remove duplicate function implementations (`error`, `match`, `parseType` and its helpers) from `parser.cpp`.
    - Clean up any duplicate header includes at the top of the file.
48. **Task 48:** Implement `parseFnDecl` for function definitions. (DONE)
    - Parse the `fn` keyword, function name (identifier), parameter list `(`, `)`, and return type `-> type`.
    - For now, the function body should be parsed as an empty block `{}`.
49. **Task 49:** Implement `parseBlockStatement`. (DONE)
    - Parse a `{` followed by a sequence of statements (currently only other empty blocks `{}`) and a closing `}`.
    - Handle empty blocks `{}` and blocks with empty statements `{;}`.
50. **Task 50:** Implement `parseIfStatement`.
    - Parse `if`, a parenthesized condition `(expr)`, a `then` block, and an optional `else` block.
    - The condition `expr` will be a stub that calls `parseExpression`.
51. **Task 51:** Implement `parseWhileStatement`.
    - Parse `while`, a parenthesized condition `(expr)`, and a body block.
52. **Task 52:** Refactor `AST_parser.md` for clarity and correctness.
    - Remove the duplicated section for `ASTFnDeclNode`.
    - Relocate the "Parsing Logic (`parseIfStatement`)" description to be under the `ASTIfStmtNode` section where it belongs.
    - Add a "Parsing Logic" subsection for `ASTWhileStmtNode` for consistency.
53. **Task 53:** Add Doxygen comments to `parser.cpp` functions.
    - Add comprehensive Doxygen-style comments to `parseVarDecl`, `parseFnDecl`, `parseStatement`, and `parseIfStatement` to explain their purpose, grammar, and behavior, similar to the existing comment for `parseWhileStatement`.
54. **Task 54:** Resolve Technical Constraint Violations in Parser. (DONE)
    - Remove the forbidden `#include <cstdlib>` from `src/bootstrap/parser.cpp` to comply with the project's C++ Standard Library Usage Policy.
55. **Task 55:** Implement `parseDeferStatement`.
    - Parse `defer` followed by a single statement.
56. **Task 56:** Implement `parseReturnStatement`. (DONE)
    - Parse `return` followed by an optional expression and a semicolon.
57. **Task 57:** Implement `parsePrimaryExpr` for primary expressions.
    - Handle integer, float, char, and string literals.
    - Handle identifiers.
    - Handle parenthesized expressions `(expr)`.
58. **Task 58:** Implement parsing for postfix expressions.
    - Parse function calls with arguments `(arg1, arg2, ...)`.
    - Parse array access expressions `[index]`.
59. **Task 59:** Implement `parseUnaryExpr` for unary operators.
    - Handle prefix operators like `-`, `!`, `~`, `&`.
60. **Task 60:** Implement `parseBinaryExpr` for binary operator precedence.
    - Use a precedence climbing or Pratt parsing algorithm.
    - Correctly handle the order of operations for additive, multiplicative, and comparison operators.
61. **Task 61:** Create Integration Tests for the Parser.
    - Write a suite of tests that parse snippets of Zig-like code combining multiple features (e.g., a function with a `while` loop containing an `if` statement).
    - Verify that the resulting AST is structured correctly.

### Milestone 4: Bootstrap Type System & Semantic Analysis
62. **Task 62:** Define core Type struct and TypeKind for C89-compatible types.
    - Focus only on types that map directly to C89: i8, i16, i32, i64, u8, u16, u32, u64, isize, usize, f32, f64, bool, void, *T.
    - No advanced Zig types like slices, error unions, or optionals for now.
63. **Task 63:** Implement minimal Symbol struct and SymbolTable.
    - Basic symbol storage for functions, global variables, and local variables.
    - Simple name-to-type mapping.
64. **Task 64:** Implement basic scope management.
    - Only global and function scopes are needed initially.
65. **Task 65:** Implement symbol insertion and lookup.
    - Basic name resolution for variables/functions with simple duplicate detection.
66. **Task 66:** Implement TypeChecker skeleton for bootstrap types.
    - Focus only on basic C89-compatible operations with minimal error reporting.
67. **Task 67:** Implement basic type compatibility.
    - Integer and pointer type compatibility; basic function signature matching.
68. **Task 68:** Type-check variable declarations (basic).
    - Simple type annotation checking and basic initializer compatibility.
69. **Task 69:** Type-check function signatures.
    - Parameter and return type verification.
70. **Task 70:** Implement basic expression type checking.
    - Handle literals, variable access, basic arithmetic, and simple comparisons.
71. **Task 71:** Implement function call checking.
    - Argument count validation and basic type matching for arguments.
72. **Task 72:** Implement basic control flow checking.
    - Ensure `if` and `while` statements have boolean conditions.
73. **Task 73:** Implement basic pointer operation checking.
    - Check address-of (`&`) and dereference (`*`) operators.
74. **Task 74:** Implement C89 compatibility checking.
    - Ensure all generated types map to C89 equivalents and no unsupported Zig features are used.
75. **Task 75:** Implement basic memory safety for bootstrap.
    - Simple pointer safety and compile-time array bounds checking.
76. **Task 76:** Implement struct type checking (simple).
    - Basic struct field access and initialization.
77. **Task 77:** Implement basic enum type checking.
    - Simple enum value access and compatibility.
78. **Task 78:** Implement basic error checking.
    - Simple function return type validation.
79. **Task 79:** Implement basic function overloading resolution.
    - Only simple function resolution needed, focusing on C89-compatible generation.
80. **Task 80:** Write bootstrap-specific unit tests.
    - Test basic type checking functionality and verify C89 compatibility of generated types.
81. **Task 81:** Implement basic integration tests.
    - Parse, type-check, and generate C89 for simple Zig code, and verify the C89 output compiles.
82. **Task 82:** Optimize for bootstrap performance.
    - Minimal type checking overhead and fast symbol lookups.
83. **Task 83:** Document bootstrap limitations clearly.
    - List unsupported Zig features and document C89 mapping decisions.

### Milestone 5: Code Generation (C89)
84. **Task 84:** Implement a basic C89 emitter class in `codegen.hpp`.
85. **Task 85:** Implement `CVariableAllocator` to manage C variable names.
86. **Task 86:** Generate C89 function declarations.
87. **Task 87:** Generate C89 code for integer literals.
88. **Task 88:** Generate C89 code for local variable declarations.
89. **Task 89:** Generate C89 code for basic arithmetic operations.
90. **Task 90:** Generate C89 code for comparison and logical operations.
91. **Task 91:** Generate C89 code for if statements.
92. **Task 92:** Generate C89 code for while and for loops.
93. **Task 93:** Generate C89 code for return statements.
94. **Task 94:** Implement C89 function call generation.
95. **Task 95:** Implement C89 code generation for defer statements.
96. **Task 96:** Generate C89 code for slice types.
97. **Task 97:** Generate C89 code for error unions.
98. **Task 98:** Write integration tests for the C89 code generator.

### Milestone 6: C Library Integration & Final Bootstrap
99. **Task 99:** Implement the CBackend class skeleton for final code emission.
100. **Task 100:** Add logic to generate proper C89 headers and include guards.
101. **Task 101:** Implement wrappers for Zig runtime features to C library calls.
102. **Task 102:** Handle Zig memory management with C89-compatible patterns.
103. **Task 103:** Integrate CBackend to write complete C89 `.c` files.
104. **Task 104:** Compile a "hello world" Zig program end-to-end.

## Phase 1: The Cross-Compiler (Zig)
105. **Task 105:** Translate the C++ compiler logic into the supported Zig subset.
106. **Task 106:** Use the C++ bootstrap compiler (`zig0.exe`) to compile the new Zig compiler (`zig1.exe`).
107. **Task 107:** Verify `zig1.exe` by using it to compile the test suite.

## Phase 2: Self-Hosting
108. **Task 108:** Use `zig1.exe` to compile its own source code, producing `zig2.exe`.
109. **Task 109:** Perform a binary comparison between `zig1.exe` and `zig2.exe` to confirm self-hosting.
