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
52. **Task 52:** Implement `parseDeferStatement`.
    - Parse `defer` followed by a single statement.
53. **Task 53:** Implement `parseReturnStatement`.
    - Parse `return` followed by an optional expression and a semicolon.
54. **Task 54:** Implement `parsePrimaryExpr` for primary expressions.
    - Handle integer, float, char, and string literals.
    - Handle identifiers.
    - Handle parenthesized expressions `(expr)`.
55. **Task 55:** Implement parsing for postfix expressions.
    - Parse function calls with arguments `(arg1, arg2, ...)`.
    - Parse array access expressions `[index]`.
56. **Task 56:** Implement `parseUnaryExpr` for unary operators.
    - Handle prefix operators like `-`, `!`, `~`, `&`.
57. **Task 57:** Implement `parseBinaryExpr` for binary operator precedence.
    - Use a precedence climbing or Pratt parsing algorithm.
    - Correctly handle the order of operations for additive, multiplicative, and comparison operators.
58. **Task 58:** Create Integration Tests for the Parser.
    - Write a suite of tests that parse snippets of Zig-like code combining multiple features (e.g., a function with a `while` loop containing an `if` statement).
    - Verify that the resulting AST is structured correctly.

### Milestone 4: Type System & Symbol Table
58. **Task 58:** Define the `Type` struct and `TypeKind` enum for all supported types.
59. **Task 59:** Implement the `Symbol` struct and `SymbolTable` class.
60. **Task 60:** Implement scope management in `SymbolTable` (`pushScope`, `popScope`).
61. **Task 61:** Implement symbol lookup and insertion logic.
62. **Task 62:** Implement the type-checking visitor/pass.
63. **Task 63:** Add type-checking logic for variable declarations, ensuring the expression type matches the declared type.
64. **Task 64:** Implement type compatibility rules for assignments (e.g., integer widening).
65. **Task 65:** Type-check binary expressions (e.g., `int + int`).
66. **Task 66:** Type-check function calls, matching argument types to parameter types.
67. **Task 67:** Write unit tests for the type checker, including tests for valid and invalid programs.

### Milestone 5: Code Generation (C89)
68. **Task 68:** Implement a basic C89 emitter class in codegen.hpp that outputs valid C89-compliant code.
69. **Task 69:** Implement the CVariableAllocator to manage variable names and scopes for C output, avoiding C reserved words and managing name conflicts.
70. **Task 70:** Generate function declarations in C89 format with proper type mapping (e.g., Zig i32 → C int, Zig bool → C int).
71. **Task 71:** Generate code for loading and outputting integer literals as C constants.
72. **Task 72:** Generate code for local variable declarations and access in C89 format with proper scoping.
73. **Task 73:** Generate code for basic arithmetic operations that map directly to C89 operators (+, -, *, /, %).
74. **Task 74:** Generate code for comparison operators and logical operations compatible with C89.
75. **Task 75:** Generate code for if statements using standard C89 if/else constructs.
76. **Task 76:** Generate code for while loops and for loops in C89 format.
77. **Task 77:** Generate code for return statements, ensuring proper return type handling in C89.
78. **Task 78:** Implement the function call generation with proper argument passing and type mapping for C89.
79. **Task 79:** Implement code generation for defer statements by emitting them in reverse order at scope exit as C cleanup code.
80. **Task 80:** Generate code for slice types by mapping them to C structures with pointer and length fields.
81. **Task 81:** Generate code for error unions by mapping them to C structures with payload and error code fields.
82. **Task 82:** Write integration tests that compile simple Zig programs and verify the output C89 code compiles with a C89 compiler.

### Milestone 6: C Library Integration & Final Bootstrap
83. **Task 83:** Implement the CBackend class skeleton for final code emission.
84. **Task 84:** Add logic to generate proper C89 headers and include guards for the emitted code.
85. **Task 85:** Implement logic to create wrapper functions for Zig-specific runtime features that map to C library calls.
86. **Task 86:** Implement logic to handle Zig's memory management and safety features using C89-compatible patterns.
87. **Task 87:** Integrate the CBackend with the code generator to write complete C89 .c files with proper includes.
88. **Task 88:** Compile a "hello world" style Zig program using the full C++ bootstrap compiler (zig0.exe) to generate C89 output, then compile that C89 code with a C compiler to create the final executable.

## Phase 1: The Cross-Compiler (Zig)
89. **Task 89:** Begin translating the C++ compiler logic (lexer, parser, etc.) into the supported Zig subset in lib/compiler.zig.
90. **Task 90:** Use the C++ bootstrap compiler (zig0.exe) to compile lib/compiler.zig into zig1.exe.
91. **Task 91:** Verify that zig1.exe is a functional compiler by using it to compile the test suite.

## Phase 2: Self-Hosting
92. **Task 92:** Use the generated Zig compiler (zig1.exe) to compile its own source code (lib/compiler.zig) to produce zig2.exe.
93. **Task 93:** Perform a binary comparison (fc /b) between zig1.exe and zig2.exe. If they are identical, the compiler is officially self-hosting.
