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
35. **Task 35:** Review and Finalize AST Node Definitions. (DONE)
    - Consolidates previous tasks #35-43. The node definitions in `ast.hpp` are comprehensive and considered complete for the parser implementation phase.
36. **Task 36:** Implement the `Parser` class skeleton with helper methods (`advance`, `match`, `expect`).
37. **Task 37:** Implement `parseType` to handle type expressions (e.g., `i32`, `*u8`, `[]bool`).
38. **Task 38:** Implement parsing for top-level variable declarations (`var` and `const`).
39. **Task 39:** Implement `parseFnDecl` for function definitions (stubbed). (DONE)
40. **Task 40:** Implement `parseBlockStatement`. (DONE)
41. **Task 41:** Implement `parseIfStatement`.
42. **Task 42:** Implement `parseWhileStatement`.
43. **Task 43:** Implement `parseDeferStatement`.
44. **Task 44:** Implement `parseReturnStatement`. (DONE)
45. **Task 45:** Implement `parsePrimaryExpr` for primary expressions.
46. **Task 46:** Implement parsing for postfix expressions (function calls, array access).
47. **Task 47:** Implement `parseUnaryExpr` for unary operators.
48. **Task 48:** Implement `parseBinaryExpr` for Core Binary Operators.
49. **Task 49:** Extend `parseBinaryExpr` for Bitwise Operators.
50. **Task 50:** Extend `parseBinaryExpr` for Logical Operators.
51. **Task 51:** Add support for Expression Statements in `parseStatement`.
    - An expression statement is an expression followed by a semicolon (e.g., `foo();`).
52. **Task 52:** Implement `parseForStatement`.
    - Parse `for` `(` `iterable` `)` `|item, index|` `block_statement`.
53. **Task 53:** Implement `parseSwitchExpression`.
    - Parse `switch` `(` `expr` `)` `{` `(case_expr => value),*` `}`.
54. **Task 54:** Implement parsing for Error Handling Syntax.
    - Add logic to parse `try` and `catch` expressions.
    - Add logic to parse `errdefer` statements.
55. **Task 55:** Implement parsing for Container Declarations.
    - Implement `parseStructDecl`.
    - Implement `parseUnionDecl`.
    - Implement `parseEnumDecl`.
56. **Task 56:** Extend `parseFnDecl` to support parameters and non-empty bodies.
    - Update the parser to handle comma-separated parameter declarations.
    - Update the parser to call `parseBlockStatement` for the function body.
57. **Task 57:** Implement a top-level `parseProgram` loop.
    - Create an entry-point function that parses a sequence of top-level declarations (functions, variables) until it reaches the EOF token.
58. **Task 58:** Update Parser Documentation (`AST_parser.md` and Doxygen).
    - Update the operator precedence table in `AST_parser.md` to match the implementation.
    - Remove the outdated "Future AST Node Requirements" section.
    - Add Doxygen comments for all new public parsing functions.
59. **Task 59:** Create Integration Tests for the Parser.
    - Write a suite of tests that parse snippets of Zig-like code combining multiple features (e.g., a function with a `while` loop containing an `if` statement with complex expressions).
    - Verify that the resulting AST is structured correctly.

### Milestone 4: Bootstrap Type System & Semantic Analysis
60. **Task 60:** Define core Type struct and TypeKind for C89-compatible types.
61. **Task 61:** Implement minimal Symbol struct and SymbolTable.
62. **Task 62:** Implement basic scope management.
63. **Task 63:** Implement symbol insertion and lookup.
64. **Task 64:** Implement TypeChecker skeleton for bootstrap types.
65. **Task 65:** Implement basic type compatibility.
66. **Task 66:** Type-check variable declarations (basic).
67. **Task 67:** Type-check function signatures.
68. **Task 68:** Implement basic expression type checking.
69. **Task 69:** Implement function call checking.
70. **Task 70:** Implement basic control flow checking.
71. **Task 71:** Implement basic pointer operation checking.
72. **Task 72:** Implement C89 compatibility checking.
73. **Task 73:** Implement basic memory safety for bootstrap.
74. **Task 74:** Implement struct type checking (simple).
75. **Task 75:** Implement basic enum type checking.
76. **Task 76:** Implement basic error checking.
77. **Task 77:** Implement basic function overloading resolution.
78. **Task 78:** Write bootstrap-specific unit tests.
79. **Task 79:** Implement basic integration tests.
80. **Task 80:** Optimize for bootstrap performance.
81. **Task 81:** Document bootstrap limitations clearly.

### Milestone 5: Code Generation (C89)
82. **Task 82:** Implement a basic C89 emitter class in `codegen.hpp`.
83. **Task 83:** Implement `CVariableAllocator` to manage C variable names.
84. **Task 84:** Generate C89 function declarations.
85. **Task 85:** Generate C89 code for integer literals.
86. **Task 86:** Generate C89 code for local variable declarations.
87. **Task 87:** Generate C89 code for basic arithmetic operations.
88. **Task 88:** Generate C89 code for comparison and logical operations.
89. **Task 89:** Generate C89 code for if statements.
90. **Task 90:** Generate C89 code for while and for loops.
91. **Task 91:** Generate C89 code for return statements.
92. **Task 92:** Implement C89 function call generation.
93. **Task 93:** Implement C89 code generation for defer statements.
94. **Task 94:** Generate C89 code for slice types.
95. **Task 95:** Generate C89 code for error unions.
96. **Task 96:** Write integration tests for the C89 code generator.

### Milestone 6: C Library Integration & Final Bootstrap
97. **Task 97:** Implement the CBackend class skeleton for final code emission.
98. **Task 98:** Add logic to generate proper C89 headers and include guards.
99. **Task 99:** Implement wrappers for Zig runtime features to C library calls.
100. **Task 100:** Handle Zig memory management with C89-compatible patterns.
101. **Task 101:** Integrate CBackend to write complete C89 `.c` files.
102. **Task 102:** Compile a "hello world" Zig program end-to-end.

## Phase 1: The Cross-Compiler (Zig)
103. **Task 103:** Translate the C++ compiler logic into the supported Zig subset.
104. **Task 104:** Use the C++ bootstrap compiler (`zig0.exe`) to compile the new Zig compiler (`zig1.exe`).
105. **Task 105:** Verify `zig1.exe` by using it to compile the test suite.

## Phase 2: Self-Hosting
106. **Task 106:** Use `zig1.exe` to compile its own source code, producing `zig2.exe`.
107. **Task 107:** Perform a binary comparison between `zig1.exe` and `zig2.exe` to confirm self-hosting.
